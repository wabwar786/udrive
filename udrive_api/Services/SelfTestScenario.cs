using System.Diagnostics;
using System.Globalization;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace UDrive.Api.Services;

/// <summary>
/// The journey itself: one customer, one driver, one hotel owner, one admin,
/// and every assertion that matters between them.
/// </summary>
/// <remarks>
/// Read <see cref="ExecuteAsync"/> from the top as a script. The order is the
/// order a real trip happens in, and the steps that cross from one role to
/// another are marked — those are the ones worth having, because a single role
/// talking to itself would still pass with the marketplace completely broken.
/// </remarks>
internal sealed class SelfTestScenario(HttpClient http, string baseUrl)
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    private readonly List<SelfTestStepResult> _steps = [];
    private string _token = string.Empty;
    private string _role = "System";

    /// <summary>Set once a step the rest depends on has failed.</summary>
    /// <remarks>
    /// Everything after it is recorded as Skipped rather than attempted. A
    /// cascade of forty red rows caused by one broken endpoint tells an Admin
    /// less than one red row and thirty-nine grey ones.
    /// </remarks>
    private bool _aborted;

    /// <summary>
    /// Opens a section that does not depend on the one before it.
    /// </summary>
    /// <remarks>
    /// Steps inside a section cascade, which is right: there is no point asking
    /// a driver to start a trip that was never booked. Sections do not.
    ///
    /// The first real run made the case. It stopped on an empty destinations
    /// catalogue and skipped the remaining forty steps — including the whole
    /// hotel journey, which needs no destination, no fare and no ride. One
    /// missing catalogue row hid every other answer the run had to give.
    /// </remarks>
    private void StartSection() => _aborted = false;

    public IReadOnlyList<SelfTestStepResult> Steps => _steps;

    public void RecordFailure(string name, string detail) =>
        Record(name, "Failed", detail, 0, "-", "-", null);

    private void As(string role, string token)
    {
        _role = role;
        _token = token;
    }

    private void Record(
        string name,
        string outcome,
        string? detail,
        int durationMs,
        string method,
        string path,
        int? status) =>
        _steps.Add(new SelfTestStepResult(
            _steps.Count + 1, name, _role, method, Readable(path), status,
            durationMs, outcome, detail));

    /// <summary>Turns an empty id in a path into something a person can read.</summary>
    /// <remarks>
    /// A step skipped because an earlier one failed never captured the id it
    /// would have used, so its path came out as
    /// <c>/api/v1/bookings/ride-requests//offers</c> — which reads like a bug
    /// in the harness rather than a step that never ran.
    /// </remarks>
    private static string Readable(string path) =>
        path.Contains("//", StringComparison.Ordinal)
            ? path.Replace("//", "/{id}/", StringComparison.Ordinal)
            : path;

    /// <summary>Records something checked without calling the API.</summary>
    private void Check(string name, bool passed, string? detail, bool critical = true)
    {
        if (_aborted)
        {
            Record(name, "Skipped", "An earlier step failed, so this was not checked.", 0, "-", "-", null);
            return;
        }

        Record(name, passed ? "Passed" : "Failed", passed ? null : detail, 0, "-", "-", null);
        if (!passed && critical)
        {
            _aborted = true;
        }
    }

    /// <summary>
    /// Makes one call and records what came back.
    /// </summary>
    /// <param name="expectedStatus">
    /// What a healthy platform answers. Usually 200; 409 where the run is
    /// deliberately asking for something that must be refused.
    /// </param>
    /// <param name="assert">
    /// Given the response's <c>data</c>, returns null when it is right or a
    /// sentence saying what was wrong. This is where most of the value is: a
    /// 200 that contains the wrong thing is the failure that reaches customers.
    /// </param>
    /// <param name="skipIfMissing">
    /// Treat 404/405/501 as Skipped instead of Failed, for an endpoint the
    /// platform is known not to have yet.
    /// </param>
    /// <param name="critical">
    /// False for a leaf check whose failure should not stop the rest of the run.
    /// </param>
    private async Task<JsonNode?> CallAsync(
        string name,
        HttpMethod method,
        string path,
        object? body = null,
        int expectedStatus = 200,
        Func<JsonNode?, string?>? assert = null,
        bool skipIfMissing = false,
        bool critical = true,
        CancellationToken cancellationToken = default)
    {
        if (_aborted)
        {
            Record(name, "Skipped", "An earlier step failed, so this was not attempted.",
                0, method.Method, path, null);
            return null;
        }

        var clock = Stopwatch.StartNew();
        try
        {
            using var request = new HttpRequestMessage(method, baseUrl + path);
            if (_token.Length > 0)
            {
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _token);
            }

            if (body is not null)
            {
                request.Content = new StringContent(
                    JsonSerializer.Serialize(body, Json), Encoding.UTF8, "application/json");
            }

            using var response = await http.SendAsync(request, cancellationToken);
            var text = await response.Content.ReadAsStringAsync(cancellationToken);
            clock.Stop();

            var status = (int)response.StatusCode;
            var payload = Parse(text);

            if (skipIfMissing && status is 404 or 405 or 501)
            {
                Record(name, "Skipped",
                    "This endpoint does not exist in the deployed API.",
                    (int)clock.ElapsedMilliseconds, method.Method, path, status);
                return null;
            }

            if (status != expectedStatus)
            {
                Record(name, "Failed",
                    $"Expected HTTP {expectedStatus}, got {status}. {Message(payload, text)}".TrimEnd(),
                    (int)clock.ElapsedMilliseconds, method.Method, path, status);
                if (critical)
                {
                    _aborted = true;
                }

                return null;
            }

            var data = payload?["data"];
            var problem = assert?.Invoke(data);
            if (problem is not null)
            {
                Record(name, "Failed", problem,
                    (int)clock.ElapsedMilliseconds, method.Method, path, status);
                if (critical)
                {
                    _aborted = true;
                }

                return null;
            }

            Record(name, "Passed", null, (int)clock.ElapsedMilliseconds, method.Method, path, status);
            return data;
        }
        catch (Exception exception)
        {
            clock.Stop();
            Record(name, "Failed", exception.Message,
                (int)clock.ElapsedMilliseconds, method.Method, path, null);
            if (critical)
            {
                _aborted = true;
            }

            return null;
        }
    }

    private static JsonNode? Parse(string text)
    {
        try
        {
            return JsonNode.Parse(text);
        }
        catch
        {
            return null;
        }
    }

    /// <summary>The API's own words, or the first of the body if it did not send any.</summary>
    private static string Message(JsonNode? payload, string raw)
    {
        var message = Text(payload, "message");
        if (!string.IsNullOrWhiteSpace(message))
        {
            return message;
        }

        var error = Text(payload, "error");
        if (!string.IsNullOrWhiteSpace(error))
        {
            return error;
        }

        return raw.Length <= 200 ? raw : raw[..200] + "...";
    }

    // --------------------------------------------------------------- helpers

    private static JsonArray? Items(JsonNode? data) =>
        data as JsonArray ?? data?["items"] as JsonArray;

    /// <summary>One property as text, whatever JSON type it arrived as.</summary>
    /// <remarks>
    /// Deliberately tolerant. <c>GetValue&lt;string&gt;()</c> throws when the
    /// value is a number or a boolean, and a self-test that throws on a
    /// perfectly valid response is worse than useless — it reports a platform
    /// fault that is really its own.
    /// </remarks>
    private static string? Text(JsonNode? node, string property)
    {
        if (node?[property] is not JsonValue value)
        {
            return null;
        }

        return value.TryGetValue<string>(out var text) ? text : value.ToJsonString().Trim('"');
    }

    private static decimal? Number(JsonNode? node, string property) =>
        node?[property] is JsonValue value && value.TryGetValue<decimal>(out var parsed)
            ? parsed
            : null;

    /// <summary>
    /// Asserts one property came back equal to a value, and says what it
    /// actually was when it did not.
    /// </summary>
    /// <remarks>
    /// Eight steps want exactly this. Written out each time it produced eight
    /// interpolated strings with quotes nested inside the holes — legal since
    /// C# 11, and awkward to read or to check with anything but a compiler.
    /// </remarks>
    private static Func<JsonNode?, string?> Expect(
        string property,
        string expected,
        string sentence) =>
        data =>
        {
            var actual = Text(data, property);
            return string.Equals(actual, expected, StringComparison.OrdinalIgnoreCase)
                ? null
                : sentence + " '" + (actual ?? "nothing") + "'.";
        };

    private static bool Contains(JsonNode? data, string property, string? wanted) =>
        wanted is not null
        && Items(data) is { } array
        && array.Any(item => string.Equals(Text(item, property), wanted, StringComparison.OrdinalIgnoreCase));

    // ------------------------------------------------------------- the script

    public async Task ExecuteAsync(
        string customerToken,
        string driverToken,
        string hotelOwnerToken,
        string adminToken,
        CancellationToken cancellationToken)
    {
        // Muzaffarabad, about seven kilometres apart. Real coordinates, because
        // the fare engine looks up a pricing zone and a made-up point in the sea
        // would fail for a reason that has nothing to do with the platform.
        const double pickupLat = 34.3700;
        const double pickupLng = 73.4700;
        const double dropLat = 34.4200;
        const double dropLng = 73.5300;
        const string serviceType = "City";
        const string vehicleCategory = "Car";
        const string bookingType = "WholeVehicle";
        const int seats = 2;

        // --------------------------------------------------- 1. the platform

        As("System", string.Empty);

        await CallAsync("API is answering", HttpMethod.Get, "/api/v1/system/status",
            assert: Expect("database", "connected", "The API reports its database as"),
            cancellationToken: cancellationToken);

        // Not critical, and that is the whole point.
        //
        // The first real run failed here — an empty destinations catalogue —
        // and took the other forty steps with it, none of which need a
        // destination. A ride, a trip, a rating and a hotel booking are all
        // perfectly testable without one. Only the tour package section needs
        // a destination, and that section now skips itself instead.
        var destinations = await CallAsync("Destinations catalogue is populated", HttpMethod.Get,
            "/api/v1/catalog/destinations",
            assert: data => Items(data)?.Count > 0
                ? null
                : "No destinations came back. Tour packages cannot be tested without one \u2014 "
                  + "the rest of the run is unaffected. Admin portal \u2192 Data management \u2192 "
                  + "\"Add demo data\" restores the catalogue.",
            critical: false,
            cancellationToken: cancellationToken);

        var destinationId = Items(destinations)?.FirstOrDefault() is { } first
            ? Text(first, "id")
            : null;

        await CallAsync($"Rate card exists for {serviceType}", HttpMethod.Get,
            $"/api/v1/catalog/service-rates?serviceType={serviceType}&lat={Fmt(pickupLat)}&lng={Fmt(pickupLng)}",
            assert: data => Items(data)?.Count > 0
                ? null
                : "No vehicle rates are configured, so every fare quote will fail and "
                  + "no ride can be booked. Admin portal \u2192 Data management \u2192 "
                  + "\"Add demo data\" restores the rate card.",
            cancellationToken: cancellationToken);

        // ---------------------------------------------------- 2. as Customer

        As("Customer", customerToken);

        var quote = await CallAsync("Fare quote is issued", HttpMethod.Post, "/api/v1/pricing/quote",
            new
            {
                serviceType,
                vehicleCategory,
                bookingType,
                seats,
                pickupLatitude = pickupLat,
                pickupLongitude = pickupLng,
                destinationLatitude = dropLat,
                destinationLongitude = dropLng,
                distanceKm = 7.5,
                durationMinutes = 20.0
            },
            assert: data =>
            {
                if (string.IsNullOrWhiteSpace(Text(data, "quoteToken")))
                {
                    return "The quote came back without a signed token, so no ride can be booked against it.";
                }

                var minimum = Number(data, "minimum") ?? 0;
                var recommended = Number(data, "recommended") ?? 0;
                var maximum = Number(data, "maximum") ?? 0;
                return minimum > 0 && recommended >= minimum && maximum >= recommended
                    ? null
                    : $"The fare band is not in order: minimum {minimum}, recommended {recommended}, maximum {maximum}.";
            },
            cancellationToken: cancellationToken);

        var quoteToken = Text(quote, "quoteToken");
        var offerAmount = Number(quote, "recommended") ?? 0m;

        var rideRequest = await CallAsync("Customer creates a ride request", HttpMethod.Post,
            "/api/v1/bookings/ride-requests",
            new
            {
                pickupLabel = "Self-test pickup, Muzaffarabad",
                destinationLabel = "Self-test destination, Muzaffarabad",
                pickupLatitude = pickupLat,
                pickupLongitude = pickupLng,
                destinationLatitude = dropLat,
                destinationLongitude = dropLng,
                // Instant, so the request is live now. An advance booking has to
                // be at least thirty minutes ahead, and the driver-side query
                // only shows requests whose pickup is not long past — instant is
                // the only time that satisfies both.
                pickupAt = DateTimeOffset.UtcNow,
                returnAt = (DateTimeOffset?)null,
                bookingType,
                seatsRequested = seats,
                adults = seats,
                children = 0,
                luggageCount = 1,
                customerOffer = offerAmount,
                vehicleCategory,
                partyType = "Family",
                familyOnly = false,
                womenOnly = false,
                notes = "Automated self-test. Safe to ignore.",
                instantRide = true,
                quoteToken,
                serviceType
            },
            assert: data => string.IsNullOrWhiteSpace(Text(data, "id"))
                ? "The request was created without an id."
                : null,
            cancellationToken: cancellationToken);

        var rideRequestId = Text(rideRequest, "id");

        await CallAsync("Customer sees their own request", HttpMethod.Get,
            "/api/v1/bookings/ride-requests/my",
            assert: data => Contains(data, "id", rideRequestId)
                ? null
                : "The request the customer just created is not in their own list.",
            cancellationToken: cancellationToken);

        // ------------------------------------------------------ 3. as Driver

        As("Driver", driverToken);

        await CallAsync("Driver goes online at the pickup", HttpMethod.Post,
            "/api/v1/driver/marketplace/presence",
            new
            {
                latitude = pickupLat,
                longitude = pickupLng,
                accuracy = 12.0,
                deviceTimestamp = DateTimeOffset.UtcNow
            },
            cancellationToken: cancellationToken);

        // CROSSES ROLES. The customer created it; the driver has to see it.
        // If the marketplace is broken this is the step that goes red, and
        // nothing before it would have told you.
        await CallAsync("Driver sees the Customer's request", HttpMethod.Get,
            "/api/v1/driver/marketplace/ride-requests",
            assert: data => Contains(data, "id", rideRequestId)
                ? null
                : "The request never reached the driver's marketplace list. "
                  + "Check presence freshness, the request radius, and the driver's commission balance.",
            cancellationToken: cancellationToken);

        var wallet = await CallAsync("Driver wallet is readable", HttpMethod.Get,
            "/api/v1/driver/wallet",
            assert: data => (Number(data, "balance") ?? -1) < 0
                ? "The wallet came back without a balance."
                : null,
            cancellationToken: cancellationToken);
        var balanceBefore = Number(wallet, "balance") ?? 0m;

        var vehicles = await CallAsync("Driver's own vehicle is listed", HttpMethod.Get,
            "/api/v1/driver/vehicles",
            assert: data => Items(data)?.Count > 0
                ? null
                : "The driver has no vehicle, so no offer can be made.",
            cancellationToken: cancellationToken);

        // The harness vehicle by its plate, not just the first row. If a
        // previous run ever left a second vehicle on this profile, picking
        // whichever came back first would send an offer on the wrong one.
        var vehicleId = Items(vehicles)?.FirstOrDefault(item => string.Equals(
            Text(item, "registrationNumber"),
            SelfTestAccounts.VehicleRegistration,
            StringComparison.OrdinalIgnoreCase)) is { } vehicle
            ? Text(vehicle, "id")
            : null;

        // The vehicle id is needed for the offer and the tour package. Stop here
        // with a clear reason rather than sending a null id and getting a
        // validation error that reads like a platform fault.
        Check("Harness vehicle is found by its registration",
            vehicleId is not null,
            $"No vehicle with registration {SelfTestAccounts.VehicleRegistration} came back.");

        var offer = await CallAsync("Driver offers a fare", HttpMethod.Post,
            $"/api/v1/driver/marketplace/ride-requests/{rideRequestId}/offers",
            new
            {
                vehicleId,
                amount = offerAmount,
                estimatedArrivalMinutes = 7,
                message = "Automated self-test offer."
            },
            assert: data => string.IsNullOrWhiteSpace(Text(data, "id"))
                ? "The offer was accepted but came back without an id."
                : null,
            cancellationToken: cancellationToken);

        var offerId = Text(offer, "id");

        // ---------------------------------------------- 4. Customer accepts

        As("Customer", customerToken);

        // CROSSES ROLES the other way: the driver's offer has to reach the
        // customer.
        await CallAsync("Customer sees the Driver's offer", HttpMethod.Get,
            $"/api/v1/bookings/ride-requests/{rideRequestId}/offers",
            assert: data => Contains(data, "id", offerId)
                ? null
                : "The driver's offer is not in the customer's offer list.",
            cancellationToken: cancellationToken);

        var booking = await CallAsync("Customer accepts the offer", HttpMethod.Post,
            $"/api/v1/bookings/ride-requests/{rideRequestId}/offers/{offerId}/select",
            new { advanceAmount = 0 },
            assert: data => string.IsNullOrWhiteSpace(Text(data, "id"))
                ? "No booking came back from accepting the offer."
                : null,
            cancellationToken: cancellationToken);

        var bookingId = Text(booking, "id");

        var myBookings = await CallAsync("Booking appears with its Trip OTP", HttpMethod.Get,
            "/api/v1/bookings/my",
            assert: data =>
            {
                var match = Items(data)?.FirstOrDefault(item =>
                    string.Equals(Text(item, "id"), bookingId, StringComparison.OrdinalIgnoreCase));
                if (match is null)
                {
                    return "The new booking is not in the customer's bookings list.";
                }

                var otp = Text(match, "tripOtp");
                return otp is { Length: 4 }
                    ? null
                    : "The booking has no four-digit Trip OTP, so the driver cannot start the ride.";
            },
            cancellationToken: cancellationToken);

        var tripOtp = Items(myBookings)?.FirstOrDefault(item =>
            string.Equals(Text(item, "id"), bookingId, StringComparison.OrdinalIgnoreCase)) is { } bookingRow
            ? Text(bookingRow, "tripOtp")
            : null;

        // ------------------------------------------------------- 5. the trip

        As("Driver", driverToken);

        await CallAsync("Trip is on the Driver's list", HttpMethod.Get, "/api/v1/trips/driver/my",
            assert: data =>
            {
                var match = Items(data)?.FirstOrDefault(item =>
                    string.Equals(Text(item, "bookingId"), bookingId, StringComparison.OrdinalIgnoreCase));
                if (match is null)
                {
                    return "The accepted booking is not among the driver's trips.";
                }

                var status = Text(match, "tripStatus");
                return string.Equals(status, "DriverAccepted", StringComparison.OrdinalIgnoreCase)
                    ? null
                    : $"The trip starts at '{status}', not 'DriverAccepted'.";
            },
            cancellationToken: cancellationToken);

        await CallAsync("Driver sets En route", HttpMethod.Put,
            $"/api/v1/trips/{bookingId}/driver-status",
            new { status = "DriverEnRoute", reason = "Self-test" },
            cancellationToken: cancellationToken);

        await CallAsync("Driver sets Arrived", HttpMethod.Put,
            $"/api/v1/trips/{bookingId}/driver-status",
            new { status = "DriverArrived", reason = "Self-test" },
            cancellationToken: cancellationToken);

        // A NEGATIVE test, and one of the most useful here. The Trip OTP is the
        // only thing standing between "the driver says the ride started" and
        // "the customer agrees it started". If a wrong code were ever accepted,
        // every other step in this run would still be green.
        await CallAsync("A wrong Trip OTP is refused", HttpMethod.Put,
            $"/api/v1/trips/{bookingId}/driver-status",
            new { status = "TripStarted", tripOtp = WrongOtp(tripOtp), reason = "Self-test" },
            expectedStatus: 409,
            cancellationToken: cancellationToken);

        await CallAsync("The right Trip OTP starts the ride", HttpMethod.Put,
            $"/api/v1/trips/{bookingId}/driver-status",
            new { status = "TripStarted", tripOtp, reason = "Self-test" },
            cancellationToken: cancellationToken);

        // Commission is charged inside the same transaction that starts the
        // trip, so the money and the status can never disagree. This checks the
        // charge actually happened rather than trusting the 200 above.
        await CallAsync("Commission was charged when the ride started", HttpMethod.Get,
            "/api/v1/driver/wallet",
            assert: data =>
            {
                var balanceAfter = Number(data, "balance") ?? balanceBefore;
                return balanceAfter < balanceBefore
                    ? null
                    : $"The commission balance did not move: {balanceBefore} before, {balanceAfter} after.";
            },
            critical: false,
            cancellationToken: cancellationToken);

        As("Customer", customerToken);

        await CallAsync("Customer can follow the trip", HttpMethod.Get,
            $"/api/v1/trips/{bookingId}/tracking",
            assert: Expect("tripStatus", "TripStarted",
                "The trip is under way, but tracking reports"),
            critical: false,
            cancellationToken: cancellationToken);

        As("Driver", driverToken);

        await CallAsync("Driver completes the trip", HttpMethod.Put,
            $"/api/v1/trips/{bookingId}/driver-status",
            new { status = "TripCompleted", reason = "Self-test" },
            cancellationToken: cancellationToken);

        // ----------------------------------------------------- 6. the rating

        As("Customer", customerToken);

        await CallAsync("Completed trip is rateable", HttpMethod.Get,
            "/api/v1/feedback/eligible-bookings",
            assert: data => Contains(data, "bookingId", bookingId)
                ? null
                : "The completed trip did not become eligible for a rating.",
            cancellationToken: cancellationToken);

        await CallAsync("Customer rates the Driver", HttpMethod.Post, "/api/v1/feedback/ratings",
            new
            {
                bookingId,
                overallRating = 5,
                drivingRating = 5,
                behaviourRating = 5,
                cleanlinessRating = 5,
                punctualityRating = 5,
                communicationRating = 5,
                reviewText = "Automated self-test rating."
            },
            cancellationToken: cancellationToken);

        As("Driver", driverToken);

        // CROSSES ROLES: the customer's rating has to arrive on the driver.
        await CallAsync("Rating reaches the Driver", HttpMethod.Get, "/api/v1/feedback/ratings/me",
            assert: data => (Number(data, "ratingCount") ?? 0) > 0
                ? null
                : "The driver's rating summary is still empty after being rated.",
            critical: false,
            cancellationToken: cancellationToken);

        // --------------------------------------------- 7. the tour package
        //
        // This section is where create, edit and withdraw are genuinely
        // exercised. The hotel endpoints have no edit and no delete at all, so
        // they cannot cover it.

        StartSection();
        As("Driver", driverToken);

        JsonNode? package = null;
        if (destinationId is null || vehicleId is null)
        {
            Record("Tour package: create, edit, submit, approve, pause, resume", "Skipped",
                destinationId is null
                    ? "The destinations catalogue is empty, and a package must name a "
                      + "destination. Everything else in this run is unaffected."
                    : "The harness vehicle was not found earlier, and a package must name "
                      + "a vehicle. Everything else in this run is unaffected.",
                0, "-", "-", null);
        }
        else
        {
            package = await CallAsync("Driver creates a tour package", HttpMethod.Post,
                "/api/v1/driver/marketplace/packages",
                PackageBody(vehicleId, destinationId, "Self-test package", 12000m),
                assert: data => string.IsNullOrWhiteSpace(Text(data, "id"))
                    ? "The package was created without an id."
                    : null,
                critical: false,
                cancellationToken: cancellationToken);
        }

        var packageId = Text(package, "id");

        if (packageId is null)
        {
            // Only when the create was actually attempted. If the section was
            // skipped for want of a destination or a vehicle, that has already
            // been said once and does not need saying twice.
            if (package is not null || (destinationId is not null && vehicleId is not null))
            {
                Record("Tour package edit, submit, approve, pause and resume", "Skipped",
                    "The package was not created, so the rest of this section was not attempted.",
                    0, "-", "-", null);
            }
        }
        else
        {
            await CallAsync("Driver edits the package", HttpMethod.Put,
                $"/api/v1/driver/marketplace/packages/{packageId}",
                PackageBody(vehicleId, destinationId, "Self-test package (edited)", 13500m),
                assert: Expect("title", "Self-test package (edited)",
                    "The edit was accepted, but the title is still"),
                critical: false,
                cancellationToken: cancellationToken);

            await CallAsync("Driver submits it for review", HttpMethod.Post,
                $"/api/v1/driver/marketplace/packages/{packageId}/submit",
                assert: Expect("status", "PendingApproval", "After submitting, the status is"),
                critical: false,
                cancellationToken: cancellationToken);

            As("Admin", adminToken);

            // CROSSES ROLES: what the driver submitted has to be in front of
            // the admin.
            await CallAsync("Package is waiting in the Admin queue", HttpMethod.Get,
                "/api/v1/admin/packages/pending",
                assert: data => Contains(data, "id", packageId)
                    ? null
                    : "The submitted package is not in the admin's pending list.",
                critical: false,
                cancellationToken: cancellationToken);

            await CallAsync("Admin approves the package", HttpMethod.Put,
                $"/api/v1/admin/packages/{packageId}/review",
                new { decision = "Approve", notes = "Automated self-test approval." },
                assert: Expect("status", "Active", "After approval, the status is"),
                critical: false,
                cancellationToken: cancellationToken);

            As("Driver", driverToken);

            await CallAsync("Driver withdraws the package", HttpMethod.Post,
                $"/api/v1/driver/marketplace/packages/{packageId}/pause",
                assert: Expect("status", "Paused", "After pausing, the status is"),
                critical: false,
                cancellationToken: cancellationToken);

            await CallAsync("Driver puts it back", HttpMethod.Post,
                $"/api/v1/driver/marketplace/packages/{packageId}/activate",
                assert: Expect("status", "Active", "After reactivating, the status is"),
                critical: false,
                cancellationToken: cancellationToken);
        }

        // ------------------------------------------------- 8. the Hotel Owner
        //
        // Nothing here depends on the ride, the fare or the package, so this
        // runs whatever happened above.

        StartSection();
        As("Hotel Owner", hotelOwnerToken);

        var hotelCity = "Muzaffarabad";
        var hotel = await CallAsync("Owner lists a hotel", HttpMethod.Post, "/api/v1/hotels/owner",
            new
            {
                name = "Self-test Guest House",
                description = "Created by the automated self-test. Safe to ignore.",
                address = "Self-test Road, Muzaffarabad",
                city = hotelCity,
                district = hotelCity,
                latitude = pickupLat,
                longitude = pickupLng,
                contactPhone = SelfTestAccounts.HotelOwnerPhone,
                mainImageUrl = string.Empty,
                amenities = new[] { "Wi-Fi", "Parking" },
                transportAvailable = true
            },
            assert: data => string.IsNullOrWhiteSpace(Text(data, "id"))
                ? "The hotel was created without an id."
                : null,
            critical: false,
            cancellationToken: cancellationToken);

        var hotelId = Text(hotel, "id");

        if (hotelId is null)
        {
            // Not `return`: that ended the whole run and took the Near Me
            // probes with it, which have nothing to do with hotels. Setting the
            // flag skips the rest of THIS section; StartSection() below opens
            // the next one.
            _aborted = true;
        }

        await CallAsync("New hotel starts as Pending", HttpMethod.Get, "/api/v1/hotels/owner/my",
            assert: data =>
            {
                var match = Items(data)?.FirstOrDefault(item =>
                    string.Equals(Text(item, "id"), hotelId, StringComparison.OrdinalIgnoreCase));
                if (match is null)
                {
                    return "The owner cannot see the hotel they just created.";
                }

                var approval = Text(match, "approvalStatus");
                return string.Equals(approval, "Pending", StringComparison.OrdinalIgnoreCase)
                    ? null
                    : "A brand new hotel is '" + approval + "' instead of 'Pending'.";
            },
            critical: false,
            cancellationToken: cancellationToken);

        var room = await CallAsync("Owner adds a room type", HttpMethod.Post,
            $"/api/v1/hotels/owner/{hotelId}/rooms",
            new
            {
                roomType = "Self-test Double",
                description = "Automated self-test room.",
                capacity = 2,
                totalRooms = 3,
                baseRate = 6500m,
                imageUrl = string.Empty,
                amenities = new[] { "Heater" }
            },
            assert: data => string.IsNullOrWhiteSpace(Text(data, "id"))
                ? "The room was added without an id."
                : null,
            critical: false,
            cancellationToken: cancellationToken);

        var roomId = Text(room, "id");

        As("Admin", adminToken);

        await CallAsync("Hotel is in the Admin approval queue", HttpMethod.Get,
            "/api/v1/hotels/admin/pending",
            assert: data => Contains(data, "id", hotelId)
                ? null
                : "The pending hotel is not in the admin's queue.",
            critical: false,
            cancellationToken: cancellationToken);

        await CallAsync("Admin approves the hotel", HttpMethod.Post,
            $"/api/v1/hotels/admin/{hotelId}/review",
            new { approve = true, reason = (string?)null },
            critical: false,
            cancellationToken: cancellationToken);

        As("Customer", customerToken);

        // CROSSES ROLES, and proves the visibility guard works in both
        // directions at once: the self-test customer finds this hotel, and
        // HotelService.SearchAsync's guard clause keeps every real customer
        // from finding it.
        await CallAsync("Approved hotel is findable by a Customer", HttpMethod.Get,
            $"/api/v1/hotels?city={Uri.EscapeDataString(hotelCity)}",
            assert: data => Contains(data, "id", hotelId)
                ? null
                : "The approved hotel does not appear in a customer search of its own city.",
            critical: false,
            cancellationToken: cancellationToken);

        await CallAsync("Hotel detail carries the room type", HttpMethod.Get,
            $"/api/v1/hotels/{hotelId}",
            assert: data => roomId is null || Contains(data?["rooms"], "id", roomId)
                ? null
                : "The room the owner added is not on the hotel's detail page.",
            critical: false,
            cancellationToken: cancellationToken);

        if (roomId is not null)
        {
            var checkIn = DateOnly.FromDateTime(DateTime.UtcNow.Date.AddDays(14));
            await CallAsync("Customer books a room", HttpMethod.Post,
                $"/api/v1/hotels/{hotelId}/bookings",
                new
                {
                    roomId,
                    checkIn = checkIn.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
                    checkOut = checkIn.AddDays(2).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
                    guests = 2,
                    rooms = 1,
                    includeTransport = false,
                    pickupAddress = (string?)null,
                    pickupLatitude = (double?)null,
                    pickupLongitude = (double?)null
                },
                assert: data => (Number(data, "amount") ?? 0) > 0
                    ? null
                    : "The hotel booking came back with no amount.",
                critical: false,
                cancellationToken: cancellationToken);

            As("Hotel Owner", hotelOwnerToken);

            // CROSSES ROLES: the customer's booking has to reach the owner.
            await CallAsync("Booking reaches the Owner", HttpMethod.Get,
                "/api/v1/hotels/owner/bookings",
                assert: data => Items(data)?.Count > 0
                    ? null
                    : "The owner's bookings list is empty after a customer booked a room.",
                critical: false,
                cancellationToken: cancellationToken);
        }

        As("Admin", adminToken);

        // The nearest thing the hotel endpoints have to an edit or a delete.
        // There is no owner-side update and no delete at all — see the README.
        await CallAsync("Admin can take the hotel offline", HttpMethod.Patch,
            $"/api/v1/hotels/admin/{hotelId}/active",
            new { isActive = false },
            critical: false,
            cancellationToken: cancellationToken);

        // ------------------------------------------- 9. Near Me, which is not
        //
        // The customer app calls these three. No controller, service or table
        // for them exists in the API, and the app's own repository says so:
        // "until the API ships them these calls surface an empty result rather
        // than an error screen". They are probed rather than asserted, so the
        // day the endpoints arrive these turn green on their own.

        StartSection();
        As("Customer", customerToken);

        await CallAsync("Near Me search", HttpMethod.Get,
            $"/api/v1/businesses/nearby?lat={Fmt(pickupLat)}&lng={Fmt(pickupLng)}&radiusKm=3&sort=distance",
            skipIfMissing: true,
            critical: false,
            cancellationToken: cancellationToken);

        As("Hotel Owner", hotelOwnerToken);

        await CallAsync("Owner's business listings", HttpMethod.Get, "/api/v1/businesses/mine",
            skipIfMissing: true,
            critical: false,
            cancellationToken: cancellationToken);

        await CallAsync("Create a business listing", HttpMethod.Post, "/api/v1/businesses",
            new
            {
                name = "Self-test Shop",
                category = "Restaurant",
                city = hotelCity,
                address = "Self-test Road",
                latitude = pickupLat,
                longitude = pickupLng,
                contactPhone = SelfTestAccounts.HotelOwnerPhone
            },
            skipIfMissing: true,
            critical: false,
            cancellationToken: cancellationToken);
    }

    /// <summary>A four-digit code that is definitely not the right one.</summary>
    private static string WrongOtp(string? real) =>
        string.Equals(real, "0000", StringComparison.Ordinal) ? "1111" : "0000";

    private static string Fmt(double value) =>
        value.ToString("0.######", CultureInfo.InvariantCulture);

    private static object PackageBody(
        string? vehicleId,
        string? destinationId,
        string title,
        decimal wholeVehiclePrice) =>
        new
        {
            vehicleId,
            destinationId,
            title,
            startingCity = "Muzaffarabad",
            pickupPoint = "Self-test pickup point",
            // Well clear of the six-hour minimum the package rules impose.
            departureAt = DateTimeOffset.UtcNow.AddDays(21),
            returnAt = DateTimeOffset.UtcNow.AddDays(23),
            totalSeats = 4,
            pricePerSeat = wholeVehiclePrice / 4m,
            wholeVehiclePrice,
            familyOnly = false,
            womenOnly = false,
            customerOffersAllowed = true,
            description = "Created by the automated self-test. Safe to ignore.",
            cancellationPolicy = "Self-test policy.",
            passengerPolicy = "Mixed",
            luggageAllowance = "One bag per passenger",
            routeStops = new[] { "Self-test stop" },
            inclusions = new[] { "Fuel" },
            exclusions = new[] { "Meals" },
            itinerary = new[] { "Day 1: self-test" },
            fuelIncluded = true,
            tollIncluded = false,
            hotelIncluded = false,
            mealsIncluded = false,
            guideIncluded = false,
            jeepTransferIncluded = false,
            driverAccommodationIncluded = false,
            coverImageUrl = (string?)null
        };
}
