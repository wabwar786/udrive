using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;
using Npgsql;
using NpgsqlTypes;
using UDrive.Api.Common;
using UDrive.Api.Models;
using UDrive.Api.Security;

namespace UDrive.Api.Services;

/// <summary>
/// Hotel mode in the app: the owner's profile and the five-step hotel wizard.
/// </summary>
/// <remarks>
/// A hotel is created as a <c>Draft</c> after the first step and filled in by
/// the steps that follow, so an owner can stop half way and carry on later
/// from the same phone or another one. Nothing a Draft holds is visible to a
/// customer or to the admin until <see cref="SubmitAsync"/> sends it for
/// review.
///
/// An approved hotel can still be edited and stays live while it is; the admin
/// sees the latest version in the hotel list. Its photos and rooms cannot drop
/// below what a hotel needs to be bookable (three photos, one room type).
///
/// Every statement filters on <c>owner_user_id</c>: an owner can read and
/// change only their own hotels, and an id from somebody else's account
/// answers "not found", never "forbidden".
/// </remarks>
public sealed partial class HotelOwnerService(string connectionString, LocalFileStorageService fileStorage)
{
    public const int MinimumPhotos = 3;
    public const int MaximumPhotos = 9;

    private const string ImageCategory = "hotel-images";
    private const string DocumentCategory = "hotel-owner-documents";

    public static readonly string[] PropertyTypes = ["Hotel", "Guest house", "Resort", "Hut"];

    // ───────────────────────────────────────────────────────────── profile

    public async Task<ServiceResult<HotelOwnerProfileDto>> ProfileAsync(Guid userId, CancellationToken ct)
    {
        await using var c = await OpenAsync(ct);
        return ServiceResult<HotelOwnerProfileDto>.Ok(await ReadProfileAsync(c, userId, ct));
    }

    public async Task<ServiceResult<HotelOwnerProfileDto>> SaveProfileAsync(
        Guid userId, SaveHotelOwnerProfileRequest x, CancellationToken ct)
    {
        var ownerName = Clip(x.OwnerName, 80);
        var business = Clip(x.BusinessName, 120);
        if (ownerName.Length < 2) return Fail<HotelOwnerProfileDto>(400, "owner_name_required", "Owner ka naam likhein.");
        if (business.Length < 2) return Fail<HotelOwnerProfileDto>(400, "business_name_required", "Business ka naam likhein.");
        if (!PhoneNumberNormalizer.TryNormalizePakistan(x.Phone, out var phone))
            return Fail<HotelOwnerProfileDto>(400, "phone_invalid", "Sahi mobile number likhein, jaise 03001234567.");
        var email = Clip(x.Email, 160);
        if (email.Length > 0 && !EmailPattern().IsMatch(email))
            return Fail<HotelOwnerProfileDto>(400, "email_invalid", "Email sahi nahi lagti.");

        await using var c = await OpenAsync(ct);
        await using (var cmd = new NpgsqlCommand(
            """
            INSERT INTO udrive.hotel_owner_profiles
                (user_id, owner_name, business_name, phone, email, status, created_at, updated_at)
            VALUES (@u, @name, @business, @phone, @email, 'Active', now(), now())
            ON CONFLICT (user_id) DO UPDATE SET
                owner_name = EXCLUDED.owner_name,
                business_name = EXCLUDED.business_name,
                phone = EXCLUDED.phone,
                email = EXCLUDED.email,
                updated_at = now();
            INSERT INTO udrive.user_roles (user_id, role, created_at)
            VALUES (@u, 'HotelOwner', now()) ON CONFLICT (user_id, role) DO NOTHING;
            """, c))
        {
            cmd.Parameters.AddWithValue("u", userId);
            cmd.Parameters.AddWithValue("name", ownerName);
            cmd.Parameters.AddWithValue("business", business);
            cmd.Parameters.AddWithValue("phone", phone);
            cmd.Parameters.AddWithValue("email", email);
            await cmd.ExecuteNonQueryAsync(ct);
        }

        await MarkProfilePendingIfCompleteAsync(c, userId, ct);
        return ServiceResult<HotelOwnerProfileDto>.Ok(await ReadProfileAsync(c, userId, ct), "Profile save ho gaya.");
    }

    /// <summary>One side of the owner's CNIC. Admin-only to read back.</summary>
    public async Task<ServiceResult<HotelOwnerProfileDto>> UploadCnicAsync(
        Guid userId, string side, IFormFile? file, CancellationToken ct)
    {
        var column = side?.Trim().ToLowerInvariant() switch
        {
            "front" => "cnic_front_url",
            "back" => "cnic_back_url",
            _ => null,
        };
        if (column is null) return Fail<HotelOwnerProfileDto>(400, "side_invalid", "CNIC ka front ya back chunein.");
        if (file is null) return Fail<HotelOwnerProfileDto>(400, "file_required", "Photo chunein.");

        await using var c = await OpenAsync(ct);
        var current = await ReadProfileAsync(c, userId, ct);
        if (current.VerificationStatus == "Verified")
        {
            return Fail<HotelOwnerProfileDto>(409, "cnic_locked",
                "Aap ka CNIC verify ho chuka hai. Badalne ke liye UDrive support se rabta karein.");
        }

        StoredFile stored;
        try
        {
            stored = await fileStorage.SaveAsync(file, DocumentCategory, userId, ct);
        }
        catch (InvalidDataException error) { return Fail<HotelOwnerProfileDto>(400, "file_invalid", error.Message); }
        catch (InvalidOperationException error) { return Fail<HotelOwnerProfileDto>(503, "storage_unavailable", error.Message); }

        string? previous = null;
        await using (var ensure = new NpgsqlCommand(
            """
            INSERT INTO udrive.hotel_owner_profiles (user_id, status, created_at, updated_at)
            VALUES (@u, 'Active', now(), now())
            ON CONFLICT (user_id) DO NOTHING;
            """, c))
        {
            ensure.Parameters.AddWithValue("u", userId);
            await ensure.ExecuteNonQueryAsync(ct);
        }
        await using (var read = new NpgsqlCommand(
            $"SELECT {column} FROM udrive.hotel_owner_profiles WHERE user_id = @u;", c))
        {
            read.Parameters.AddWithValue("u", userId);
            previous = await read.ExecuteScalarAsync(ct) as string;
        }
        await using (var write = new NpgsqlCommand(
            $"UPDATE udrive.hotel_owner_profiles SET {column} = @url, updated_at = now() WHERE user_id = @u;", c))
        {
            write.Parameters.AddWithValue("u", userId);
            write.Parameters.AddWithValue("url", stored.RelativeUrl);
            await write.ExecuteNonQueryAsync(ct);
        }
        if (!string.IsNullOrWhiteSpace(previous) && previous != stored.RelativeUrl) fileStorage.DeleteProtectedFile(previous);

        await MarkProfilePendingIfCompleteAsync(c, userId, ct);
        return ServiceResult<HotelOwnerProfileDto>.Ok(await ReadProfileAsync(c, userId, ct), "Photo lag gayi.");
    }

    // ───────────────────────────────────────────────────────────── home

    public async Task<ServiceResult<HotelOwnerHomeDto>> HomeAsync(Guid userId, CancellationToken ct)
    {
        await using var c = await OpenAsync(ct);
        var profile = await ReadProfileAsync(c, userId, ct);
        var hotels = new List<OwnerHotelCardDto>();
        await using (var cmd = new NpgsqlCommand(
            """
            SELECT h.id, h.name, h.property_type, h.city, h.district, h.approval_status,
                   h.rejection_reason, h.is_active, h.main_image_url,
                   (SELECT count(*) FROM udrive.hotel_photos p WHERE p.hotel_id = h.id)::int,
                   (SELECT count(*) FROM udrive.hotel_rooms r WHERE r.hotel_id = h.id AND r.is_active)::int,
                   h.contact_phone
              FROM udrive.hotels h
             WHERE h.owner_user_id = @u
             ORDER BY h.created_at DESC;
            """, c))
        {
            cmd.Parameters.AddWithValue("u", userId);
            await using var r = await cmd.ExecuteReaderAsync(ct);
            while (await r.ReadAsync(ct))
            {
                hotels.Add(new OwnerHotelCardDto(
                    r.GetGuid(0), r.GetString(1), r.GetString(2), r.GetString(3), r.GetString(4),
                    r.GetString(5), r.IsDBNull(6) ? null : r.GetString(6), r.GetBoolean(7), r.GetString(8),
                    r.GetInt32(9), r.GetInt32(10), r.GetString(11)));
            }
        }
        return ServiceResult<HotelOwnerHomeDto>.Ok(new HotelOwnerHomeDto(profile, hotels));
    }

    // ───────────────────────────────────────────────────────────── hotel

    public async Task<ServiceResult<OwnerHotelDetailDto>> HotelAsync(Guid userId, Guid hotelId, CancellationToken ct)
    {
        await using var c = await OpenAsync(ct);
        var hotel = await ReadHotelAsync(c, userId, hotelId, ct);
        return hotel is null ? NotFound<OwnerHotelDetailDto>() : ServiceResult<OwnerHotelDetailDto>.Ok(hotel);
    }

    /// <summary>Step 1 of a new hotel. Creates the Draft.</summary>
    public async Task<ServiceResult<OwnerHotelDetailDto>> CreateAsync(Guid userId, SaveOwnerHotelRequest x, CancellationToken ct)
    {
        var name = Clip(x.Name, 120);
        if (name.Length < 2) return Fail<OwnerHotelDetailDto>(400, "name_required", "Hotel ka naam likhein.");
        var check = Validate(x);
        if (check is not null) return Fail<OwnerHotelDetailDto>(400, "validation", check);

        await using var c = await OpenAsync(ct);
        Guid id;
        await using (var owner = new NpgsqlCommand(
            """
            INSERT INTO udrive.hotel_owner_profiles (user_id, status, created_at, updated_at)
            VALUES (@u, 'Active', now(), now()) ON CONFLICT (user_id) DO NOTHING;
            INSERT INTO udrive.user_roles (user_id, role, created_at)
            VALUES (@u, 'HotelOwner', now()) ON CONFLICT (user_id, role) DO NOTHING;
            """, c))
        {
            owner.Parameters.AddWithValue("u", userId);
            await owner.ExecuteNonQueryAsync(ct);
        }
        await using (var cmd = new NpgsqlCommand(
            """
            INSERT INTO udrive.hotels
                (owner_user_id, name, property_type, description, address, city, district,
                 latitude, longitude, contact_phone, approval_status, created_at, updated_at)
            VALUES (@u, @name, @type, @description, '', '', '', 0, 0, '', 'Draft', now(), now())
            RETURNING id;
            """, c))
        {
            cmd.Parameters.AddWithValue("u", userId);
            cmd.Parameters.AddWithValue("name", name);
            cmd.Parameters.AddWithValue("type", PropertyTypeOf(x.PropertyType) ?? "Hotel");
            cmd.Parameters.AddWithValue("description", Clip(x.Description, 2000));
            id = (Guid)(await cmd.ExecuteScalarAsync(ct))!;
        }

        // Anything else the first step sent (it normally sends only the three above).
        await ApplyAsync(c, userId, id, x with { Name = null, PropertyType = null, Description = null }, ct);
        return ServiceResult<OwnerHotelDetailDto>.Created((await ReadHotelAsync(c, userId, id, ct))!, "Draft save ho gaya.");
    }

    /// <summary>Any later step, or an edit of a hotel that is already live.</summary>
    public async Task<ServiceResult<OwnerHotelDetailDto>> UpdateAsync(
        Guid userId, Guid hotelId, SaveOwnerHotelRequest x, CancellationToken ct)
    {
        if (x.Name is not null && Clip(x.Name, 120).Length < 2)
            return Fail<OwnerHotelDetailDto>(400, "name_required", "Hotel ka naam likhein.");
        var check = Validate(x);
        if (check is not null) return Fail<OwnerHotelDetailDto>(400, "validation", check);

        await using var c = await OpenAsync(ct);
        if (!await OwnsAsync(c, userId, hotelId, ct)) return NotFound<OwnerHotelDetailDto>();
        await ApplyAsync(c, userId, hotelId, x, ct);
        return ServiceResult<OwnerHotelDetailDto>.Ok((await ReadHotelAsync(c, userId, hotelId, ct))!, "Save ho gaya.");
    }

    /// <summary>Sends a Draft or a returned hotel to the admin.</summary>
    public async Task<ServiceResult<OwnerHotelDetailDto>> SubmitAsync(Guid userId, Guid hotelId, CancellationToken ct)
    {
        await using var c = await OpenAsync(ct);
        var hotel = await ReadHotelAsync(c, userId, hotelId, ct);
        if (hotel is null) return NotFound<OwnerHotelDetailDto>();
        if (hotel.Status is "Approved" or "Pending") return ServiceResult<OwnerHotelDetailDto>.Ok(hotel);

        var profile = await ReadProfileAsync(c, userId, ct);
        if (!profile.Complete)
        {
            return Fail<OwnerHotelDetailDto>(409, "profile_incomplete",
                "Pehle owner profile mukammal karein — naam, business, number aur CNIC ke dono rukh.");
        }
        if (hotel.Missing.Count > 0)
        {
            return Fail<OwnerHotelDetailDto>(409, "hotel_incomplete", "Abhi baqi hai: " + string.Join(", ", hotel.Missing) + ".");
        }

        await using (var cmd = new NpgsqlCommand(
            """
            UPDATE udrive.hotels
               SET approval_status = 'Pending', rejection_reason = NULL, submitted_at = now(), updated_at = now()
             WHERE id = @h AND owner_user_id = @u AND approval_status IN ('Draft', 'Rejected');
            """, c))
        {
            cmd.Parameters.AddWithValue("h", hotelId);
            cmd.Parameters.AddWithValue("u", userId);
            await cmd.ExecuteNonQueryAsync(ct);
        }
        return ServiceResult<OwnerHotelDetailDto>.Ok((await ReadHotelAsync(c, userId, hotelId, ct))!,
            "Admin ko bhej diya. Approve hote hi customers ko nazar aaye ga.");
    }

    // ───────────────────────────────────────────────────────────── photos

    public async Task<ServiceResult<OwnerHotelDetailDto>> AddPhotoAsync(Guid userId, Guid hotelId, IFormFile? file, CancellationToken ct)
    {
        if (file is null) return Fail<OwnerHotelDetailDto>(400, "file_required", "Photo chunein.");
        await using var c = await OpenAsync(ct);
        if (!await OwnsAsync(c, userId, hotelId, ct)) return NotFound<OwnerHotelDetailDto>();
        if (await PhotoCountAsync(c, hotelId, ct) >= MaximumPhotos)
            return Fail<OwnerHotelDetailDto>(409, "photos_full", $"Zyada se zyada {MaximumPhotos} photos.");

        var saved = await SaveImageAsync(file, hotelId, ct);
        if (!saved.Success) return Fail<OwnerHotelDetailDto>(saved.StatusCode, saved.ErrorCode!, saved.Message!);

        await using (var cmd = new NpgsqlCommand(
            """
            INSERT INTO udrive.hotel_photos (hotel_id, url, file_url, sort_order)
            VALUES (@h, @url, @file,
                    COALESCE((SELECT max(sort_order) + 1 FROM udrive.hotel_photos WHERE hotel_id = @h), 0));
            """, c))
        {
            cmd.Parameters.AddWithValue("h", hotelId);
            cmd.Parameters.AddWithValue("url", saved.Data!.PublicUrl);
            cmd.Parameters.AddWithValue("file", saved.Data!.FileUrl);
            await cmd.ExecuteNonQueryAsync(ct);
        }
        await SyncMainImageAsync(c, hotelId, ct);
        return ServiceResult<OwnerHotelDetailDto>.Ok((await ReadHotelAsync(c, userId, hotelId, ct))!, "Photo lag gayi.");
    }

    public async Task<ServiceResult<OwnerHotelDetailDto>> RemovePhotoAsync(Guid userId, Guid hotelId, Guid photoId, CancellationToken ct)
    {
        await using var c = await OpenAsync(ct);
        var hotel = await ReadHotelAsync(c, userId, hotelId, ct);
        if (hotel is null) return NotFound<OwnerHotelDetailDto>();
        if (hotel.Status is "Approved" or "Pending" && hotel.Photos.Count <= MinimumPhotos)
        {
            return Fail<OwnerHotelDetailDto>(409, "photos_minimum",
                $"Kam az kam {MinimumPhotos} photos zaroori hain. Pehle nayi photo lagayein, phir yeh hatayein.");
        }

        string? file = null;
        await using (var cmd = new NpgsqlCommand(
            "DELETE FROM udrive.hotel_photos WHERE id = @p AND hotel_id = @h RETURNING file_url;", c))
        {
            cmd.Parameters.AddWithValue("p", photoId);
            cmd.Parameters.AddWithValue("h", hotelId);
            file = await cmd.ExecuteScalarAsync(ct) as string;
        }
        if (file is null) return Fail<OwnerHotelDetailDto>(404, "photo_not_found", "Photo nahi mili.");
        fileStorage.DeleteProtectedFile(file);
        await SyncMainImageAsync(c, hotelId, ct);
        return ServiceResult<OwnerHotelDetailDto>.Ok((await ReadHotelAsync(c, userId, hotelId, ct))!, "Photo hata di.");
    }

    public async Task<ServiceResult<OwnerHotelDetailDto>> SetMainPhotoAsync(Guid userId, Guid hotelId, Guid photoId, CancellationToken ct)
    {
        await using var c = await OpenAsync(ct);
        if (!await OwnsAsync(c, userId, hotelId, ct)) return NotFound<OwnerHotelDetailDto>();
        await using (var cmd = new NpgsqlCommand(
            """
            WITH ordered AS (
                SELECT id, row_number() OVER (ORDER BY (id = @p) DESC, sort_order, created_at) - 1 AS n
                  FROM udrive.hotel_photos WHERE hotel_id = @h)
            UPDATE udrive.hotel_photos p SET sort_order = o.n
              FROM ordered o WHERE p.id = o.id;
            """, c))
        {
            cmd.Parameters.AddWithValue("p", photoId);
            cmd.Parameters.AddWithValue("h", hotelId);
            await cmd.ExecuteNonQueryAsync(ct);
        }
        await SyncMainImageAsync(c, hotelId, ct);
        return ServiceResult<OwnerHotelDetailDto>.Ok((await ReadHotelAsync(c, userId, hotelId, ct))!, "Main photo badal di.");
    }

    // ───────────────────────────────────────────────────────────── rooms

    public async Task<ServiceResult<OwnerHotelDetailDto>> SaveRoomAsync(
        Guid userId, Guid hotelId, Guid? roomId, SaveOwnerRoomRequest x, CancellationToken ct)
    {
        var type = Clip(x.RoomType, 60);
        if (type.Length < 2) return Fail<OwnerHotelDetailDto>(400, "room_type_required", "Room type likhein, jaise Double room.");
        if (x.Capacity is < 1 or > 20) return Fail<OwnerHotelDetailDto>(400, "capacity_invalid", "Ek kamre mein 1 se 20 log.");
        if (x.TotalRooms is < 1 or > 500) return Fail<OwnerHotelDetailDto>(400, "rooms_invalid", "Kamre 1 se 500 tak.");
        if (x.BaseRate is < 1 or > 1_000_000) return Fail<OwnerHotelDetailDto>(400, "rate_invalid", "Kiraya Rs 1 se Rs 10,00,000 tak.");

        await using var c = await OpenAsync(ct);
        if (!await OwnsAsync(c, userId, hotelId, ct)) return NotFound<OwnerHotelDetailDto>();

        var sql = roomId is null
            ? """
              INSERT INTO udrive.hotel_rooms (hotel_id, room_type, description, capacity, total_rooms, base_rate, image_url, amenities)
              VALUES (@h, @type, @description, @capacity, @total, @rate, '', '[]'::jsonb) RETURNING id;
              """
            : """
              UPDATE udrive.hotel_rooms
                 SET room_type = @type, description = @description, capacity = @capacity,
                     total_rooms = @total, base_rate = @rate, updated_at = now()
               WHERE id = @r AND hotel_id = @h AND is_active RETURNING id;
              """;
        await using (var cmd = new NpgsqlCommand(sql, c))
        {
            cmd.Parameters.AddWithValue("h", hotelId);
            cmd.Parameters.AddWithValue("r", roomId ?? Guid.Empty);
            cmd.Parameters.AddWithValue("type", type);
            cmd.Parameters.AddWithValue("description", Clip(x.Description, 500));
            cmd.Parameters.AddWithValue("capacity", x.Capacity);
            cmd.Parameters.AddWithValue("total", x.TotalRooms);
            cmd.Parameters.AddWithValue("rate", x.BaseRate);
            if (await cmd.ExecuteScalarAsync(ct) is not Guid) return Fail<OwnerHotelDetailDto>(404, "room_not_found", "Room nahi mila.");
        }
        await TouchAsync(c, hotelId, ct);
        return ServiceResult<OwnerHotelDetailDto>.Ok((await ReadHotelAsync(c, userId, hotelId, ct))!, "Room save ho gaya.");
    }

    /// <summary>Retires a room type. Past bookings keep pointing at it.</summary>
    public async Task<ServiceResult<OwnerHotelDetailDto>> RemoveRoomAsync(Guid userId, Guid hotelId, Guid roomId, CancellationToken ct)
    {
        await using var c = await OpenAsync(ct);
        var hotel = await ReadHotelAsync(c, userId, hotelId, ct);
        if (hotel is null) return NotFound<OwnerHotelDetailDto>();
        if (hotel.Status is "Approved" or "Pending" && hotel.Rooms.Count <= 1)
            return Fail<OwnerHotelDetailDto>(409, "rooms_minimum", "Kam az kam ek room type zaroori hai.");

        await using (var cmd = new NpgsqlCommand(
            "UPDATE udrive.hotel_rooms SET is_active = false, updated_at = now() WHERE id = @r AND hotel_id = @h AND is_active RETURNING id;", c))
        {
            cmd.Parameters.AddWithValue("r", roomId);
            cmd.Parameters.AddWithValue("h", hotelId);
            if (await cmd.ExecuteScalarAsync(ct) is not Guid) return Fail<OwnerHotelDetailDto>(404, "room_not_found", "Room nahi mila.");
        }
        await TouchAsync(c, hotelId, ct);
        return ServiceResult<OwnerHotelDetailDto>.Ok((await ReadHotelAsync(c, userId, hotelId, ct))!, "Room hata diya.");
    }

    public async Task<ServiceResult<OwnerHotelDetailDto>> RoomPhotoAsync(
        Guid userId, Guid hotelId, Guid roomId, IFormFile? file, CancellationToken ct)
    {
        if (file is null) return Fail<OwnerHotelDetailDto>(400, "file_required", "Photo chunein.");
        await using var c = await OpenAsync(ct);
        if (!await OwnsAsync(c, userId, hotelId, ct)) return NotFound<OwnerHotelDetailDto>();

        var saved = await SaveImageAsync(file, hotelId, ct);
        if (!saved.Success) return Fail<OwnerHotelDetailDto>(saved.StatusCode, saved.ErrorCode!, saved.Message!);

        await using (var cmd = new NpgsqlCommand(
            "UPDATE udrive.hotel_rooms SET image_url = @url, updated_at = now() WHERE id = @r AND hotel_id = @h AND is_active RETURNING id;", c))
        {
            cmd.Parameters.AddWithValue("url", saved.Data!.PublicUrl);
            cmd.Parameters.AddWithValue("r", roomId);
            cmd.Parameters.AddWithValue("h", hotelId);
            if (await cmd.ExecuteScalarAsync(ct) is not Guid)
            {
                fileStorage.DeleteProtectedFile(saved.Data.FileUrl);
                return Fail<OwnerHotelDetailDto>(404, "room_not_found", "Room nahi mila.");
            }
        }
        return ServiceResult<OwnerHotelDetailDto>.Ok((await ReadHotelAsync(c, userId, hotelId, ct))!, "Photo lag gayi.");
    }

    // ───────────────────────────────────────────────────────────── admin

    /// <summary>Everything the admin needs to review one hotel and its owner.</summary>
    public async Task<ServiceResult<object>> AdminDetailAsync(Guid hotelId, CancellationToken ct)
    {
        await using var c = await OpenAsync(ct);
        Guid ownerId;
        await using (var cmd = new NpgsqlCommand("SELECT owner_user_id FROM udrive.hotels WHERE id = @h;", c))
        {
            cmd.Parameters.AddWithValue("h", hotelId);
            if (await cmd.ExecuteScalarAsync(ct) is not Guid o) return ServiceResult<object>.Fail(404, "hotel_not_found", "Hotel not found.");
            ownerId = o;
        }
        var hotel = (await ReadHotelAsync(c, ownerId, hotelId, ct))!;
        var profile = await ReadProfileAsync(c, ownerId, ct);
        string? front = null, back = null;
        await using (var cmd = new NpgsqlCommand(
            "SELECT cnic_front_url, cnic_back_url FROM udrive.hotel_owner_profiles WHERE user_id = @u;", c))
        {
            cmd.Parameters.AddWithValue("u", ownerId);
            await using var r = await cmd.ExecuteReaderAsync(ct);
            if (await r.ReadAsync(ct))
            {
                front = r.IsDBNull(0) ? null : r.GetString(0);
                back = r.IsDBNull(1) ? null : r.GetString(1);
            }
        }
        return ServiceResult<object>.Ok(new
        {
            hotel,
            owner = new
            {
                profile.OwnerName,
                profile.BusinessName,
                profile.Phone,
                profile.Email,
                profile.VerificationStatus,
                cnicFrontUrl = front,
                cnicBackUrl = back,
            },
        });
    }

    // ───────────────────────────────────────────────────────────── internals

    private async Task<NpgsqlConnection> OpenAsync(CancellationToken ct)
    {
        var c = new NpgsqlConnection(connectionString);
        await c.OpenAsync(ct);
        return c;
    }

    private static async Task<HotelOwnerProfileDto> ReadProfileAsync(NpgsqlConnection c, Guid userId, CancellationToken ct)
    {
        await using var cmd = new NpgsqlCommand(
            """
            SELECT COALESCE(NULLIF(p.owner_name, ''), u.full_name, ''),
                   COALESCE(p.business_name, ''),
                   COALESCE(NULLIF(p.phone, ''), u.phone_number, ''),
                   COALESCE(NULLIF(p.email, ''), ''),
                   p.cnic_front_url IS NOT NULL, p.cnic_back_url IS NOT NULL,
                   COALESCE(p.verification_status, 'NotSubmitted'), p.verification_note,
                   COALESCE(p.owner_name <> '', false)
              FROM udrive.users u
              LEFT JOIN udrive.hotel_owner_profiles p ON p.user_id = u.id
             WHERE u.id = @u;
            """, c);
        cmd.Parameters.AddWithValue("u", userId);
        await using var r = await cmd.ExecuteReaderAsync(ct);
        if (!await r.ReadAsync(ct)) return new HotelOwnerProfileDto("", "", "", "", false, false, "NotSubmitted", null, false);

        var ownerName = r.GetString(0);
        // A "uDrive User 1234" placeholder is not a name the admin can check.
        if (ownerName.StartsWith("uDrive User", StringComparison.OrdinalIgnoreCase)) ownerName = "";
        var business = r.GetString(1);
        var front = r.GetBoolean(4);
        var back = r.GetBoolean(5);
        var saved = r.GetBoolean(8);
        var complete = saved && ownerName.Length >= 2 && business.Length >= 2 && r.GetString(2).Length > 0 && front && back;
        return new HotelOwnerProfileDto(ownerName, business, r.GetString(2), r.GetString(3), front, back,
            r.GetString(6), r.IsDBNull(7) ? null : r.GetString(7), complete);
    }

    private static async Task MarkProfilePendingIfCompleteAsync(NpgsqlConnection c, Guid userId, CancellationToken ct)
    {
        await using var cmd = new NpgsqlCommand(
            """
            UPDATE udrive.hotel_owner_profiles
               SET verification_status = 'Pending', verification_note = NULL, updated_at = now()
             WHERE user_id = @u
               AND verification_status IN ('NotSubmitted', 'Rejected')
               AND owner_name <> '' AND COALESCE(business_name, '') <> '' AND COALESCE(phone, '') <> ''
               AND cnic_front_url IS NOT NULL AND cnic_back_url IS NOT NULL;
            """, c);
        cmd.Parameters.AddWithValue("u", userId);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    private static async Task<bool> OwnsAsync(NpgsqlConnection c, Guid userId, Guid hotelId, CancellationToken ct)
    {
        await using var cmd = new NpgsqlCommand(
            "SELECT 1 FROM udrive.hotels WHERE id = @h AND owner_user_id = @u;", c);
        cmd.Parameters.AddWithValue("h", hotelId);
        cmd.Parameters.AddWithValue("u", userId);
        return await cmd.ExecuteScalarAsync(ct) is not null;
    }

    private static async Task<int> PhotoCountAsync(NpgsqlConnection c, Guid hotelId, CancellationToken ct)
    {
        await using var cmd = new NpgsqlCommand("SELECT count(*)::int FROM udrive.hotel_photos WHERE hotel_id = @h;", c);
        cmd.Parameters.AddWithValue("h", hotelId);
        return (int)(await cmd.ExecuteScalarAsync(ct))!;
    }

    private static async Task TouchAsync(NpgsqlConnection c, Guid hotelId, CancellationToken ct)
    {
        await using var cmd = new NpgsqlCommand("UPDATE udrive.hotels SET updated_at = now() WHERE id = @h;", c);
        cmd.Parameters.AddWithValue("h", hotelId);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    /// <summary>Keeps <c>hotels.main_image_url</c> equal to the first gallery photo.</summary>
    private static async Task SyncMainImageAsync(NpgsqlConnection c, Guid hotelId, CancellationToken ct)
    {
        await using var cmd = new NpgsqlCommand(
            """
            UPDATE udrive.hotels h
               SET main_image_url = COALESCE(
                       (SELECT p.url FROM udrive.hotel_photos p WHERE p.hotel_id = h.id
                         ORDER BY p.sort_order, p.created_at LIMIT 1), ''),
                   updated_at = now()
             WHERE h.id = @h;
            """, c);
        cmd.Parameters.AddWithValue("h", hotelId);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    /// <summary>Writes only the fields the step sent.</summary>
    private static async Task ApplyAsync(NpgsqlConnection c, Guid userId, Guid hotelId, SaveOwnerHotelRequest x, CancellationToken ct)
    {
        var sets = new List<string>();
        await using var cmd = new NpgsqlCommand { Connection = c };
        void Set(string column, string parameter, object value, NpgsqlDbType? type = null)
        {
            sets.Add($"{column} = @{parameter}");
            if (type is null) cmd.Parameters.AddWithValue(parameter, value);
            else cmd.Parameters.Add(new NpgsqlParameter(parameter, type.Value) { Value = value });
        }

        if (x.Name is not null) Set("name", "name", Clip(x.Name, 120));
        if (x.PropertyType is not null) Set("property_type", "type", PropertyTypeOf(x.PropertyType)!);
        if (x.Description is not null) Set("description", "description", Clip(x.Description, 2000));
        if (x.Address is not null) Set("address", "address", Clip(x.Address, 300));
        if (x.City is not null) Set("city", "city", Clip(x.City, 80));
        if (x.District is not null) Set("district", "district", Clip(x.District, 80));
        if (x.Latitude is not null && x.Longitude is not null)
        {
            Set("latitude", "lat", x.Latitude.Value);
            Set("longitude", "lng", x.Longitude.Value);
        }
        if (x.ContactPhone is not null)
        {
            PhoneNumberNormalizer.TryNormalizePakistan(x.ContactPhone, out var phone);
            Set("contact_phone", "phone", phone);
        }
        if (x.Amenities is not null)
        {
            var list = x.Amenities.Select(a => Clip(a, 40)).Where(a => a.Length > 0)
                .Distinct(StringComparer.OrdinalIgnoreCase).Take(20).ToArray();
            Set("amenities", "amenities", JsonSerializer.Serialize(list), NpgsqlDbType.Jsonb);
        }
        if (x.TransportAvailable is not null) Set("transport_available", "transport", x.TransportAvailable.Value);
        if (x.CheckInTime is not null) Set("check_in_time", "checkin", (object?)TimeOf(x.CheckInTime) ?? DBNull.Value, NpgsqlDbType.Time);
        if (x.CheckOutTime is not null) Set("check_out_time", "checkout", (object?)TimeOf(x.CheckOutTime) ?? DBNull.Value, NpgsqlDbType.Time);

        if (sets.Count == 0) return;
        cmd.CommandText = $"UPDATE udrive.hotels SET {string.Join(", ", sets)}, updated_at = now() WHERE id = @h AND owner_user_id = @u;";
        cmd.Parameters.AddWithValue("h", hotelId);
        cmd.Parameters.AddWithValue("u", userId);
        await cmd.ExecuteNonQueryAsync(ct);
    }

    private static string? Validate(SaveOwnerHotelRequest x)
    {
        if (x.PropertyType is not null && PropertyTypeOf(x.PropertyType) is null)
            return "Type chunein: " + string.Join(", ", PropertyTypes) + ".";
        if ((x.Latitude is null) != (x.Longitude is null)) return "Map par pin dobara lagayein.";
        if (x.Latitude is < -90 or > 90 || x.Longitude is < -180 or > 180) return "Map par pin dobara lagayein.";
        if (!string.IsNullOrWhiteSpace(x.ContactPhone) && !PhoneNumberNormalizer.TryNormalizePakistan(x.ContactPhone, out _))
            return "Booking WhatsApp number sahi likhein, jaise 03001234567.";
        if (!string.IsNullOrWhiteSpace(x.CheckInTime) && TimeOf(x.CheckInTime) is null) return "Check-in time sahi nahi.";
        if (!string.IsNullOrWhiteSpace(x.CheckOutTime) && TimeOf(x.CheckOutTime) is null) return "Check-out time sahi nahi.";
        return null;
    }

    private static async Task<OwnerHotelDetailDto?> ReadHotelAsync(NpgsqlConnection c, Guid userId, Guid hotelId, CancellationToken ct)
    {
        OwnerHotelDetailDto? hotel = null;
        await using (var cmd = new NpgsqlCommand(
            """
            SELECT id, name, property_type, description, address, city, district, latitude, longitude,
                   contact_phone, amenities::text, transport_available, check_in_time, check_out_time,
                   approval_status, rejection_reason, is_active
              FROM udrive.hotels WHERE id = @h AND owner_user_id = @u;
            """, c))
        {
            cmd.Parameters.AddWithValue("h", hotelId);
            cmd.Parameters.AddWithValue("u", userId);
            await using var r = await cmd.ExecuteReaderAsync(ct);
            if (!await r.ReadAsync(ct)) return null;
            var lat = r.GetDouble(7);
            var lng = r.GetDouble(8);
            var pinned = !(lat == 0 && lng == 0);
            hotel = new OwnerHotelDetailDto(
                r.GetGuid(0), r.GetString(1), r.GetString(2), r.GetString(3), r.GetString(4), r.GetString(5), r.GetString(6),
                pinned ? lat : null, pinned ? lng : null, r.GetString(9),
                JsonSerializer.Deserialize<string[]>(r.GetString(10)) ?? [],
                r.GetBoolean(11),
                r.IsDBNull(12) ? null : TimeOnly.FromTimeSpan(r.GetFieldValue<TimeSpan>(12)).ToString("HH:mm", CultureInfo.InvariantCulture),
                r.IsDBNull(13) ? null : TimeOnly.FromTimeSpan(r.GetFieldValue<TimeSpan>(13)).ToString("HH:mm", CultureInfo.InvariantCulture),
                r.GetString(14), r.IsDBNull(15) ? null : r.GetString(15), r.GetBoolean(16),
                [], [], []);
        }

        var photos = new List<OwnerHotelPhotoDto>();
        await using (var cmd = new NpgsqlCommand(
            "SELECT id, url FROM udrive.hotel_photos WHERE hotel_id = @h ORDER BY sort_order, created_at;", c))
        {
            cmd.Parameters.AddWithValue("h", hotelId);
            await using var r = await cmd.ExecuteReaderAsync(ct);
            while (await r.ReadAsync(ct)) photos.Add(new OwnerHotelPhotoDto(r.GetGuid(0), r.GetString(1), photos.Count == 0));
        }

        var rooms = new List<OwnerHotelRoomDto>();
        await using (var cmd = new NpgsqlCommand(
            """
            SELECT id, room_type, description, capacity, total_rooms, base_rate, image_url
              FROM udrive.hotel_rooms WHERE hotel_id = @h AND is_active ORDER BY base_rate, created_at;
            """, c))
        {
            cmd.Parameters.AddWithValue("h", hotelId);
            await using var r = await cmd.ExecuteReaderAsync(ct);
            while (await r.ReadAsync(ct))
            {
                rooms.Add(new OwnerHotelRoomDto(r.GetGuid(0), r.GetString(1), r.GetString(2), r.GetInt32(3),
                    r.GetInt32(4), r.GetDecimal(5), r.GetString(6)));
            }
        }

        var missing = new List<string>();
        if (hotel.Name.Length < 2) missing.Add("hotel ka naam");
        if (hotel.Description.Trim().Length < 10) missing.Add("description");
        if (hotel.Latitude is null) missing.Add("map par pin");
        if (hotel.Address.Trim().Length < 3) missing.Add("address");
        if (hotel.City.Length == 0 || hotel.District.Length == 0) missing.Add("city / district");
        if (photos.Count < MinimumPhotos) missing.Add($"kam az kam {MinimumPhotos} photos");
        if (rooms.Count == 0) missing.Add("ek room type");
        if (hotel.ContactPhone.Length == 0) missing.Add("booking WhatsApp number");

        return hotel with { Photos = photos, Rooms = rooms, Missing = missing };
    }

    private sealed record SavedImage(string FileUrl, string PublicUrl);

    /// <summary>Stores a public hotel picture. Served by PublicHotelImageController.</summary>
    private async Task<ServiceResult<SavedImage>> SaveImageAsync(IFormFile file, Guid hotelId, CancellationToken ct)
    {
        try
        {
            var stored = await fileStorage.SaveAsync(file, ImageCategory, hotelId, ct);
            if (stored.ContentType == "application/pdf")
            {
                fileStorage.DeleteProtectedFile(stored.RelativeUrl);
                return ServiceResult<SavedImage>.Fail(400, "file_invalid", "Photo JPG, PNG ya WebP honi chahiye.");
            }
            var segments = stored.RelativeUrl.Split('/', StringSplitOptions.RemoveEmptyEntries);
            return ServiceResult<SavedImage>.Ok(new SavedImage(
                stored.RelativeUrl, $"/api/v1/hotel-images/{segments[^2]}/{segments[^1]}"));
        }
        catch (InvalidDataException error) { return ServiceResult<SavedImage>.Fail(400, "file_invalid", error.Message); }
        catch (InvalidOperationException error) { return ServiceResult<SavedImage>.Fail(503, "storage_unavailable", error.Message); }
    }

    private static string? PropertyTypeOf(string? value)
    {
        var v = value?.Trim();
        return PropertyTypes.FirstOrDefault(t => string.Equals(t, v, StringComparison.OrdinalIgnoreCase));
    }

    private static TimeSpan? TimeOf(string? value) =>
        TimeOnly.TryParseExact(value?.Trim(), ["HH:mm", "H:mm"], CultureInfo.InvariantCulture, DateTimeStyles.None, out var t)
            ? t.ToTimeSpan()
            : null;

    private static string Clip(string? value, int max)
    {
        var v = (value ?? string.Empty).Trim();
        return v.Length > max ? v[..max] : v;
    }

    private static ServiceResult<T> Fail<T>(int status, string code, string message) => ServiceResult<T>.Fail(status, code, message);
    private static ServiceResult<T> NotFound<T>() => ServiceResult<T>.Fail(404, "hotel_not_found", "Yeh hotel aap ke account par nahi mila.");

    [GeneratedRegex(@"^[^@\s]+@[^@\s]+\.[^@\s]+$")]
    private static partial Regex EmailPattern();
}
