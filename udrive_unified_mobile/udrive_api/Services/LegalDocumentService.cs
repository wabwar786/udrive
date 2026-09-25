using System.Collections.Concurrent;
using System.Net;
using System.Reflection;
using System.Text;

namespace UDrive.Api.Services;

/// <summary>One legal document, as written and as rendered.</summary>
/// <param name="Name">File stem, e.g. <c>privacy-policy</c>.</param>
/// <param name="Language">"en" or "ur".</param>
/// <param name="Governing">True for the version that wins in a dispute.</param>
public sealed record LegalDocument(
    string Name,
    string Language,
    string Title,
    string Version,
    string Effective,
    bool Governing,
    string Markdown,
    string Html);

/// <summary>
/// The privacy policy, terms and account-deletion page, as Markdown.
/// </summary>
/// <remarks>
/// These used to be HTML inside a C# string literal, which meant a lawyer's
/// correction was a code change and a deploy. They are now Markdown files
/// embedded in the assembly, and the same files are bundled into the mobile app
/// so the text can be read with no connection at all — a real consideration in
/// Neelum and Leepa.
///
/// Because the app carries a copy, the two can drift. That is what the version
/// and effective date in each file's front matter are for, and what
/// <c>tool/check_legal_sync.py</c> in the mobile repo checks against the raw
/// endpoint below before a release.
///
/// The renderer is deliberately small and handles only the Markdown these
/// documents actually use. A general-purpose library would be a dependency, a
/// supply-chain surface and an HTML-injection question, for documents we write
/// ourselves and whose whole syntax fits on one screen.
/// </remarks>
public sealed class LegalDocumentService
{
    private static readonly string[] Names =
        ["privacy-policy", "terms", "account-deletion"];

    private static readonly string[] Languages = ["en", "ur"];

    private readonly ConcurrentDictionary<string, LegalDocument> _cache = new();

    public static bool IsKnownName(string name) => Names.Contains(name);

    /// <summary>Normalises anything a query string might carry into "en" or "ur".</summary>
    public static string NormaliseLanguage(string? value) =>
        string.Equals(value, "ur", StringComparison.OrdinalIgnoreCase) ? "ur" : "en";

    public LegalDocument Get(string name, string language)
    {
        if (!IsKnownName(name))
        {
            throw new ArgumentOutOfRangeException(nameof(name), name, "Unknown legal document.");
        }

        var lang = NormaliseLanguage(language);
        return _cache.GetOrAdd($"{name}.{lang}", _ => Load(name, lang));
    }

    private static LegalDocument Load(string name, string language)
    {
        var assembly = typeof(LegalDocumentService).Assembly;
        var resource = FindResource(assembly, $"{name}.{language}.md")
            // A missing translation falls back to English rather than throwing:
            // a policy page that 500s is worse than one in the wrong language,
            // and Google Play checks that the URL returns a page.
            ?? FindResource(assembly, $"{name}.en.md")
            ?? throw new InvalidOperationException(
                $"Legal document '{name}' is not embedded in the assembly.");

        using var stream = assembly.GetManifestResourceStream(resource)!;
        using var reader = new StreamReader(stream, Encoding.UTF8);
        var raw = reader.ReadToEnd();

        var (meta, body) = SplitFrontMatter(raw);
        return new LegalDocument(
            name,
            language,
            meta.GetValueOrDefault("title", name),
            meta.GetValueOrDefault("version", "1.0"),
            meta.GetValueOrDefault("effective", ""),
            string.Equals(meta.GetValueOrDefault("governing", "false"), "true", StringComparison.OrdinalIgnoreCase),
            raw,
            RenderHtml(body));
    }

    private static string? FindResource(Assembly assembly, string suffix) =>
        assembly.GetManifestResourceNames()
            .FirstOrDefault(n => n.EndsWith(suffix, StringComparison.OrdinalIgnoreCase));

    // ------------------------------------------------------------ front matter

    private static (Dictionary<string, string> Meta, string Body) SplitFrontMatter(string raw)
    {
        var meta = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var text = raw.Replace("\r\n", "\n");
        if (!text.StartsWith("---\n", StringComparison.Ordinal))
        {
            return (meta, text);
        }

        // From index 4, not 3. Index 3 is the newline that closes the OPENING
        // delimiter, so a file whose first front-matter line is itself "---"
        // — an empty metadata block, or a "----" rule — matched at 3 and made
        // the slice below text[4..3], which throws. That is a 500 on the URL
        // Google Play polls, caused by a lawyer deleting two lines.
        var end = text.IndexOf("\n---", 4, StringComparison.Ordinal);
        if (end < 4)
        {
            return (meta, text);
        }

        foreach (var line in text[4..end].Split('\n'))
        {
            var colon = line.IndexOf(':');
            if (colon <= 0) continue;
            meta[line[..colon].Trim()] = line[(colon + 1)..].Trim();
        }

        var after = text[(end + 4)..];
        return (meta, after.TrimStart('\n'));
    }

    // --------------------------------------------------------------- rendering

    /// <summary>
    /// Renders the Markdown subset these documents use: <c>##</c> headings,
    /// paragraphs, bullet and numbered lists, pipe tables, <c>**bold**</c> and
    /// <c>`code`</c>. Everything else is escaped and shown as written.
    /// </summary>
    private static string RenderHtml(string body)
    {
        var html = new StringBuilder();
        var lines = body.Replace("\r\n", "\n").Split('\n');
        var paragraph = new List<string>();
        var item = new List<string>();
        var listKind = '\0';   // 'u', 'o' or none
        var index = 0;

        // Paragraphs and list items are both accumulated whole and rendered
        // once. These documents wrap at 80 columns, so a **bold** span or a
        // `code` span routinely opens on one line and closes on the next;
        // rendering line by line would leave the opening marker on screen as
        // literal asterisks in the middle of a privacy policy.
        void CloseParagraph()
        {
            if (paragraph.Count == 0) return;
            html.Append("<p>").Append(Inline(string.Join(' ', paragraph))).Append("</p>\n");
            paragraph.Clear();
        }

        void CloseItem()
        {
            if (item.Count == 0) return;
            html.Append("<li>").Append(Inline(string.Join(' ', item))).Append("</li>\n");
            item.Clear();
        }

        void CloseList()
        {
            CloseItem();
            if (listKind == '\0') return;
            html.Append(listKind == 'u' ? "</ul>\n" : "</ol>\n");
            listKind = '\0';
        }

        while (index < lines.Length)
        {
            var line = lines[index];
            var trimmed = line.Trim();

            if (trimmed.Length == 0)
            {
                CloseParagraph();
                CloseList();
                index++;
                continue;
            }

            // Table: a header row followed by a |---|---| separator.
            if (trimmed.StartsWith('|')
                && index + 1 < lines.Length
                && IsTableSeparator(lines[index + 1]))
            {
                CloseParagraph();
                CloseList();
                index = AppendTable(html, lines, index);
                continue;
            }

            if (trimmed.StartsWith("## ", StringComparison.Ordinal))
            {
                CloseParagraph();
                CloseList();
                html.Append("<h2>").Append(Inline(trimmed[3..])).Append("</h2>\n");
                index++;
                continue;
            }

            if (trimmed.StartsWith("# ", StringComparison.Ordinal))
            {
                CloseParagraph();
                CloseList();
                html.Append("<h2>").Append(Inline(trimmed[2..])).Append("</h2>\n");
                index++;
                continue;
            }

            if (trimmed.StartsWith("- ", StringComparison.Ordinal))
            {
                CloseParagraph();
                CloseItem();
                if (listKind != 'u') { CloseList(); html.Append("<ul>\n"); listKind = 'u'; }
                item.Add(trimmed[2..]);
                index++;
                continue;
            }

            var numbered = NumberedItem(trimmed);
            if (numbered is not null)
            {
                CloseParagraph();
                CloseItem();
                if (listKind != 'o') { CloseList(); html.Append("<ol>\n"); listKind = 'o'; }
                item.Add(numbered);
                index++;
                continue;
            }

            // An indented line continues the list item above it.
            if (item.Count > 0 && line.StartsWith("  ", StringComparison.Ordinal))
            {
                item.Add(trimmed);
                index++;
                continue;
            }

            CloseList();
            paragraph.Add(trimmed);
            index++;
        }

        CloseParagraph();
        CloseList();
        return html.ToString();
    }

    private static bool IsTableSeparator(string line)
    {
        var t = line.Trim();
        return t.StartsWith('|') && t.Contains("---", StringComparison.Ordinal)
            && t.All(c => c is '|' or '-' or ':' or ' ');
    }

    private static string? NumberedItem(string trimmed)
    {
        var dot = trimmed.IndexOf('.');
        if (dot <= 0 || dot + 1 >= trimmed.Length || trimmed[dot + 1] != ' ') return null;
        return trimmed[..dot].All(char.IsDigit) ? trimmed[(dot + 2)..] : null;
    }

    private static int AppendTable(StringBuilder html, string[] lines, int index)
    {
        var header = SplitRow(lines[index]);
        html.Append("<table><thead><tr>");
        foreach (var cell in header) html.Append("<th>").Append(Inline(cell)).Append("</th>");
        html.Append("</tr></thead><tbody>\n");

        index += 2; // header + separator
        while (index < lines.Length && lines[index].Trim().StartsWith('|'))
        {
            html.Append("<tr>");
            foreach (var cell in SplitRow(lines[index]))
            {
                html.Append("<td>").Append(Inline(cell)).Append("</td>");
            }
            html.Append("</tr>\n");
            index++;
        }

        html.Append("</tbody></table>\n");
        return index;
    }

    private static string[] SplitRow(string line) =>
        line.Trim().Trim('|').Split('|').Select(c => c.Trim()).ToArray();

    /// <summary>
    /// Escapes first, then applies inline marks.
    /// </summary>
    /// <remarks>
    /// Order matters and is the whole security story here: everything is HTML
    /// encoded before any tag is introduced, so a stray angle bracket in a
    /// policy can never become markup. The marks are then matched against the
    /// already-encoded text, where the delimiters survive untouched.
    /// </remarks>
    private static string Inline(string text)
    {
        var encoded = WebUtility.HtmlEncode(text);
        encoded = Wrap(encoded, "**", "<strong>", "</strong>");
        encoded = Wrap(encoded, "`", "<code>", "</code>");
        return encoded;
    }

    private static string Wrap(string text, string mark, string open, string close)
    {
        var result = new StringBuilder(text.Length + 16);
        var position = 0;
        var isOpen = true;

        while (true)
        {
            var next = text.IndexOf(mark, position, StringComparison.Ordinal);
            if (next < 0) break;

            // An unpaired mark is left exactly as the author typed it.
            if (isOpen && text.IndexOf(mark, next + mark.Length, StringComparison.Ordinal) < 0)
            {
                break;
            }

            result.Append(text, position, next - position).Append(isOpen ? open : close);
            position = next + mark.Length;
            isOpen = !isOpen;
        }

        result.Append(text, position, text.Length - position);
        return result.ToString();
    }
}
