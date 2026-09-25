using System.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UDrive.Api.Services;

namespace UDrive.Api.Controllers;

/// <summary>
/// The public legal pages, on the URLs Google Play already points at:
///   /privacy           privacy policy URL (Play Console → App content)
///   /account-deletion  "delete account" web link (Play Console → Data safety)
///   /terms             terms of service, linked from the app
///
/// The text lives in Markdown under Content/legal and is embedded in the
/// assembly — see <see cref="LegalDocumentService"/>. Do not edit wording here.
///
/// Both languages are served from one URL with ?lang=ur, so a link shared on
/// WhatsApp works for whoever opens it and the Play listing keeps a single
/// address. English governs; the switch is at the top of every page.
///
///   PublicPages__CompanyName  overrides the footer name (default Tech Geni Ltd.,
///                             which must match the Play developer name)
/// </summary>
[ApiController]
[AllowAnonymous]
[ApiExplorerSettings(IgnoreApi = true)]
public sealed class PublicPagesController(
    IConfiguration configuration,
    LegalDocumentService documents) : ControllerBase
{
    private string Company =>
        configuration["PublicPages:CompanyName"] is { Length: > 0 } name ? name : "Tech Geni Ltd.";

    [HttpGet("/privacy")]
    [HttpGet("/privacy-policy")]
    public ContentResult Privacy([FromQuery] string? lang) => Render("privacy-policy", lang);

    [HttpGet("/terms")]
    [HttpGet("/terms-of-service")]
    public ContentResult Terms([FromQuery] string? lang) => Render("terms", lang);

    [HttpGet("/account-deletion")]
    [HttpGet("/delete-account")]
    public ContentResult AccountDeletion([FromQuery] string? lang) => Render("account-deletion", lang);

    /// <summary>
    /// The document exactly as written, for the mobile app's release check.
    /// </summary>
    /// <remarks>
    /// The app bundles its own copy so the policy can be read with no
    /// connection. That copy can fall behind this one, so
    /// <c>tool/check_legal_sync.py</c> fetches this endpoint and refuses to let
    /// a release go out if the two differ by a single byte.
    /// </remarks>
    [HttpGet("/legal/{name}.{lang}.md")]
    public IActionResult Raw(string name, string lang)
    {
        if (!LegalDocumentService.IsKnownName(name))
        {
            return NotFound();
        }

        var document = documents.Get(name, lang);
        return Content(document.Markdown, "text/markdown; charset=utf-8");
    }

    private ContentResult Render(string name, string? lang)
    {
        var language = LegalDocumentService.NormaliseLanguage(lang);
        var document = documents.Get(name, language);
        var other = language == "ur" ? "en" : "ur";
        var otherLabel = language == "ur" ? "English" : "Roman Urdu";
        // Encoded before it goes into an href. The six route templates are
        // literals so nothing hostile can reach this today, but a raw
        // interpolation into markup is the kind of thing that stops being safe
        // the moment somebody adds a route with a parameter in it.
        var path = WebUtility.HtmlEncode(Request.Path.HasValue ? Request.Path.Value! : "/privacy");

        var effective = document.Effective.Length > 0
            ? $"Version {WebUtility.HtmlEncode(document.Version)} · in effect from {WebUtility.HtmlEncode(document.Effective)}"
            : $"Version {WebUtility.HtmlEncode(document.Version)}";

        var governingNote = document.Governing
            ? ""
            : "<p class=\"note\">This translation is for convenience. The English version governs.</p>";

        return new ContentResult
        {
            ContentType = "text/html; charset=utf-8",
            StatusCode = StatusCodes.Status200OK,
            Content = $$"""
                <!doctype html>
                <html lang="{{language}}">
                <head>
                <meta charset="utf-8">
                <meta name="viewport" content="width=device-width, initial-scale=1">
                <title>{{WebUtility.HtmlEncode(document.Title)}} · UDrive</title>
                <style>
                  :root { --ink:#0F1512; --muted:#5E6B65; --brand:#178B55; --line:#E3EAE6; --bg:#FFFFFF; --wash:#F5F9F7; }
                  * { box-sizing: border-box; }
                  body { margin:0; background:var(--bg); color:var(--ink);
                         font:16px/1.65 -apple-system, "Segoe UI", Roboto, Arial, sans-serif; }
                  header { border-bottom:1px solid var(--line); padding:14px 16px;
                           display:flex; align-items:center; justify-content:space-between; gap:12px; flex-wrap:wrap; }
                  header b { color:var(--brand); font-size:20px; letter-spacing:.3px; }
                  .switch { display:inline-flex; border:1px solid var(--line); border-radius:10px; overflow:hidden; }
                  .switch a { padding:7px 12px; font-size:13px; font-weight:700; text-decoration:none; color:var(--muted); }
                  .switch a.on { background:var(--brand); color:#fff; }
                  main { max-width:760px; margin:0 auto; padding:20px 16px 56px; }
                  h1 { font-size:26px; line-height:1.25; margin:8px 0 6px; }
                  h2 { font-size:18px; margin:30px 0 8px; }
                  p { margin:12px 0; }
                  ul, ol { padding-left:22px; } li { margin:6px 0; }
                  table { border-collapse:collapse; width:100%; margin:14px 0; font-size:15px; }
                  th, td { border:1px solid var(--line); padding:9px 11px; text-align:left; vertical-align:top; }
                  th { background:var(--wash); }
                  code { background:var(--wash); padding:1px 5px; border-radius:5px; font-size:14px; }
                  a { color:var(--brand); }
                  .muted { color:var(--muted); font-size:14px; margin:0 0 4px; }
                  .note { color:var(--muted); font-size:14px; background:var(--wash);
                          border-radius:10px; padding:10px 12px; }
                  footer { border-top:1px solid var(--line); padding:18px 16px; text-align:center;
                           color:var(--muted); font-size:13px; }
                  footer a { margin:0 6px; }
                </style>
                </head>
                <body>
                <header>
                  <b>UDrive</b>
                  <span class="switch">
                    <a class="{{(language == "en" ? "on" : "")}}" href="{{path}}?lang=en">English</a>
                    <a class="{{(language == "ur" ? "on" : "")}}" href="{{path}}?lang=ur">Roman Urdu</a>
                  </span>
                </header>
                <main>
                <h1>{{WebUtility.HtmlEncode(document.Title)}}</h1>
                <p class="muted">{{effective}}</p>
                {{governingNote}}
                {{document.Html}}
                </main>
                <footer>
                  <a href="/privacy?lang={{language}}">Privacy</a>·<a href="/terms?lang={{language}}">Terms</a>·<a href="/account-deletion?lang={{language}}">Delete account</a>
                  <br>Read in {{otherLabel}}: <a href="{{path}}?lang={{other}}">{{path}}?lang={{other}}</a>
                  <br>© {{WebUtility.HtmlEncode(Company)}}
                </footer>
                </body>
                </html>
                """
        };
    }
}
