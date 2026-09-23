using System.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace UDrive.Api.Controllers;

/// <summary>
/// Public web pages Google Play requires for the store listing:
///   /privacy           privacy policy URL (Play Console → App content → Privacy policy)
///   /account-deletion  "delete account" web link (Play Console → Data safety)
///   /terms             terms of use, linked from the app's Settings
///
/// Served by the API so they live on a stable HTTPS domain without another
/// deployment. Contact details come from configuration:
///   PublicPages__SupportEmail   (default support@udrive.pk)
///   PublicPages__SupportPhone   (optional)
///   PublicPages__CompanyName    (default Tech Geni Ltd., the Play developer name)
/// </summary>
[ApiController]
[AllowAnonymous]
[ApiExplorerSettings(IgnoreApi = true)]
public sealed class PublicPagesController(IConfiguration configuration) : ControllerBase
{
    private const string EffectiveDate = "22 September 2026";
    // Must match the developer name on the Google Play listing; reviewers
    // compare the two. Override with PublicPages__CompanyName if it changes.
    private string Company =>
        configuration["PublicPages:CompanyName"] is { Length: > 0 } name ? WebUtility.HtmlEncode(name) : "Tech Geni Ltd.";

    private string SupportEmail =>
        configuration["PublicPages:SupportEmail"] is { Length: > 0 } email ? email : "support@udrive.pk";

    private string? SupportPhone =>
        configuration["PublicPages:SupportPhone"] is { Length: > 0 } phone ? phone : null;

    private string ContactHtml()
    {
        var email = WebUtility.HtmlEncode(SupportEmail);
        var phone = SupportPhone is null ? "" : $"<br>Phone / WhatsApp: {WebUtility.HtmlEncode(SupportPhone)}";
        return $"""<p><strong>{Company}</strong> (UDrive)<br>Email: <a href="mailto:{email}">{email}</a>{phone}</p>""";
    }

    [HttpGet("/privacy")]
    [HttpGet("/privacy-policy")]
    public ContentResult Privacy() => Page("Privacy Policy", $"""
        <p class="muted">Effective {EffectiveDate}</p>
        <p>This policy explains how {Company} ("UDrive", "we") collects, uses and protects information when you use the UDrive app and website for rides, tours and hotel bookings in Azad Jammu &amp; Kashmir.</p>

        <h2>1. Information we collect</h2>
        <ul>
          <li><strong>Account:</strong> mobile number, name, preferred language, and email if you provide it.</li>
          <li><strong>Location:</strong> precise location while the app is open, to find nearby drivers, set pickup points, show routes and share live trip progress. Drivers' location is shared during an active trip. We do not collect location in the background.</li>
          <li><strong>Trips and bookings:</strong> pickup and drop-off points, routes, fares, offers, ratings, chat messages between rider and driver, and trip status.</li>
          <li><strong>Payments:</strong> wallet top-ups, commission and payout records. Payments made through EasyPaisa or other providers are processed by them; we do not store card or wallet PINs.</li>
          <li><strong>Driver verification:</strong> CNIC and driving licence numbers and photos, selfie with CNIC, date of birth, address, emergency contact, vehicle details, registration documents and vehicle photos.</li>
          <li><strong>Safety:</strong> SOS alerts, and a short audio recording if you choose to record one during an emergency.</li>
          <li><strong>Device and usage:</strong> device name, IP address, app version and error logs, used for security and to fix problems.</li>
        </ul>

        <h2>2. How we use it</h2>
        <ul>
          <li>To create your account and verify your phone number.</li>
          <li>To match riders with drivers, calculate fares, and run trips, tours and bookings.</li>
          <li>To verify drivers and vehicles before they can accept rides.</li>
          <li>For safety: emergency response, investigating complaints and preventing fraud.</li>
          <li>For customer support, service messages and legal, tax and accounting obligations.</li>
        </ul>
        <p>We do not sell your personal information and do not show third-party advertising.</p>

        <h2>3. Who can see it</h2>
        <ul>
          <li><strong>Riders and drivers</strong> see each other's name, photo, rating, vehicle details and live location during a trip. Phone numbers are shared only as needed to complete the trip.</li>
          <li><strong>Trusted contacts</strong> you add receive trip and emergency details only when you choose to share them.</li>
          <li><strong>Service providers</strong> that host and run UDrive for us (cloud hosting, maps and places, payment providers), bound to use data only for UDrive.</li>
          <li><strong>Authorities</strong> when the law requires it, or to protect someone's safety.</li>
        </ul>

        <h2>4. Security</h2>
        <p>Data is sent over encrypted HTTPS connections. Sessions use short-lived tokens, verification documents are visible only to authorised staff and the driver, and access is logged.</p>

        <h2>5. How long we keep it</h2>
        <p>Account and profile data are kept while your account is active. When you delete your account, personal details are erased straight away (see <a href="/account-deletion">Account deletion</a>). Trip, payment and audit records are kept without your name for up to 5 years for tax, accounting and safety purposes, then deleted.</p>

        <h2>6. Your choices and rights</h2>
        <ul>
          <li>Update your name and language in the app.</li>
          <li>Turn off location permission in your phone settings (ride booking needs it).</li>
          <li>Delete your account at any time: <strong>Menu → Settings → Delete account</strong>, or through <a href="/account-deletion">this page</a>.</li>
          <li>Ask us for a copy of your data or to correct it by emailing us.</li>
        </ul>

        <h2>7. Children</h2>
        <p>UDrive is for people aged 18 and over. We do not knowingly collect data from children.</p>

        <h2>8. Changes</h2>
        <p>We will post any changes on this page and update the effective date. Important changes will also be shown in the app.</p>

        <h2>9. Contact</h2>
        {ContactHtml()}
        """);

    [HttpGet("/account-deletion")]
    [HttpGet("/delete-account")]
    public ContentResult AccountDeletion() => Page("Delete your UDrive account", $"""
        <p>You can permanently delete your UDrive account and personal data at any time.</p>

        <h2>Option 1: in the app (instant)</h2>
        <ol>
          <li>Open the UDrive app and sign in.</li>
          <li>Open the menu and tap <strong>Settings</strong>.</li>
          <li>Tap <strong>Delete account</strong>, type <strong>DELETE</strong> and confirm.</li>
        </ol>
        <p class="muted">If you have a ride in progress, finish or cancel it first.</p>

        <h2>Option 2: by email</h2>
        <p>If you cannot use the app, email <a href="mailto:{WebUtility.HtmlEncode(SupportEmail)}?subject=Delete%20my%20UDrive%20account">{WebUtility.HtmlEncode(SupportEmail)}</a> from any address with the subject <strong>"Delete my UDrive account"</strong> and the mobile number registered with UDrive. We will confirm it is your number and delete the account within 7 days.</p>

        <h2>What is deleted</h2>
        <ul>
          <li>Name, mobile number, email and profile photo</li>
          <li>Trusted contacts</li>
          <li>For drivers: CNIC and licence numbers, date of birth, address, emergency contact and payout details; vehicles are removed</li>
          <li>All sessions are signed out on every device</li>
        </ul>

        <h2>What is kept, and for how long</h2>
        <ul>
          <li>Past trips, bookings, payments, wallet and commission records are kept <strong>without your name</strong> for up to 5 years, as required for tax, accounting and safety investigations, then deleted.</li>
          <li>Any remaining wallet balance or welcome credit is forfeited.</li>
        </ul>
        <p>After deletion you can sign up again with the same number as a new account.</p>

        <h2>Contact</h2>
        {ContactHtml()}
        """);

    [HttpGet("/terms")]
    public ContentResult Terms() => Page("Terms of Use", $"""
        <p class="muted">Effective {EffectiveDate}</p>
        <p>These terms apply to your use of the UDrive app operated by {Company} ("UDrive"). By using UDrive you agree to them.</p>
        <h2>1. The service</h2>
        <p>UDrive is a technology platform that connects riders with independent drivers, tour operators and hotels. Drivers are not employees of UDrive; each driver is responsible for their vehicle, licence and conduct.</p>
        <h2>2. Your account</h2>
        <p>You must be 18 or older and give a real mobile number. Keep your phone and the verification code private. You are responsible for activity on your account.</p>
        <h2>3. Fares and payments</h2>
        <p>Fares are agreed in the app before a ride starts. Riders pay the driver the agreed fare. Drivers pay UDrive the commission shown in the app, which is deducted from the driver wallet. Cancellation fees shown in the app apply.</p>
        <h2>4. Safety and conduct</h2>
        <p>Treat others with respect, follow traffic laws and never misuse SOS. We may suspend or close accounts involved in fraud, abuse, unsafe behaviour or false documents.</p>
        <h2>5. Liability</h2>
        <p>UDrive provides the platform "as is". To the extent the law allows, UDrive is not liable for indirect losses, or for acts of drivers, riders, hotels or other third parties, and its total liability is limited to the fees you paid UDrive in the last 3 months.</p>
        <h2>6. Ending your account</h2>
        <p>You may delete your account at any time (<a href="/account-deletion">how</a>). How we handle your data is described in the <a href="/privacy">Privacy Policy</a>.</p>
        <h2>7. Law</h2>
        <p>These terms are governed by the laws in force in Azad Jammu &amp; Kashmir.</p>
        <h2>8. Contact</h2>
        {ContactHtml()}
        """);

    private ContentResult Page(string title, string body) => new()
    {
        ContentType = "text/html; charset=utf-8",
        StatusCode = StatusCodes.Status200OK,
        Content = $$"""
            <!doctype html>
            <html lang="en">
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>{{WebUtility.HtmlEncode(title)}} · UDrive</title>
            <style>
              :root { --ink:#0F1512; --muted:#5E6B65; --brand:#178B55; --line:#E3EAE6; --bg:#FFFFFF; }
              * { box-sizing: border-box; }
              body { margin:0; background:var(--bg); color:var(--ink);
                     font:16px/1.6 -apple-system, "Segoe UI", Roboto, Arial, sans-serif; }
              header { border-bottom:1px solid var(--line); padding:16px; }
              header b { color:var(--brand); font-size:20px; letter-spacing:.3px; }
              main { max-width:760px; margin:0 auto; padding:20px 16px 48px; }
              h1 { font-size:26px; line-height:1.25; margin:8px 0 12px; }
              h2 { font-size:18px; margin:28px 0 8px; }
              ul, ol { padding-left:22px; } li { margin:4px 0; }
              a { color:var(--brand); }
              .muted { color:var(--muted); font-size:14px; }
              footer { border-top:1px solid var(--line); padding:16px; text-align:center; color:var(--muted); font-size:13px; }
            </style>
            </head>
            <body>
            <header><b>UDrive</b></header>
            <main>
            <h1>{{WebUtility.HtmlEncode(title)}}</h1>
            {{body}}
            </main>
            <footer><a href="/privacy">Privacy</a> · <a href="/terms">Terms</a> · <a href="/account-deletion">Delete account</a><br>© {{Company}}</footer>
            </body>
            </html>
            """
    };
}
