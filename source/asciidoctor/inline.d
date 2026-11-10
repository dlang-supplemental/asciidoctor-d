module asciidoctor.inline;

import std.array : appender, replace;
import std.conv : to;
import std.regex;
import std.string;
import std.algorithm : canFind;

/// Escape HTML special characters.
string escapeHtml(string s)
{
    return s.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("\"", "&quot;");
}

/// True when `url` may be written into `href` or `src`.
/// Allows `http`, `https`, `mailto`, a fragment, and a relative path.
/// Rejects every other scheme, a protocol-relative URL (`//host`), and any
/// ASCII space or control. Browsers strip those characters before they read
/// the scheme, so a pattern that only looks for the word `javascript` misses them.
bool urlSchemeAllowed(string url) pure
{
    foreach (c; url)
    {
        if (c <= 0x20 || c == 0x7F)
            return false;
    }
    if (url.length == 0)
        return false;
    if (url.length >= 2 && url[0] == '/' && url[1] == '/')
        return false;

    if (isAsciiAlpha(url[0]))
    {
        size_t i = 1;
        while (i < url.length && isSchemeChar(url[i]))
            i++;
        if (i < url.length && url[i] == ':')
        {
            auto scheme = url[0 .. i];
            return schemeEquals(scheme, "http")
                || schemeEquals(scheme, "https")
                || schemeEquals(scheme, "mailto");
        }
    }
    return true;
}

/// Apply `filter` when set, then the scheme allowlist.
/// `accepted` is the URL to emit when this returns true.
bool tryAcceptUrl(string url, bool isImage, string delegate(string, bool) filter, out string accepted)
{
    if (filter !is null)
        url = filter(url, isImage);
    if (!urlSchemeAllowed(url))
        return false;
    accepted = url;
    return true;
}

private bool isAsciiAlpha(char c) pure
{
    return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
}

private bool isSchemeChar(char c) pure
{
    return isAsciiAlpha(c) || (c >= '0' && c <= '9') || c == '+' || c == '-' || c == '.';
}

private bool schemeEquals(string scheme, string expect) pure
{
    if (scheme.length != expect.length)
        return false;
    foreach (i, c; scheme)
    {
        char folded = (c >= 'A' && c <= 'Z') ? cast(char)(c + 32) : c;
        if (folded != expect[i])
            return false;
    }
    return true;
}

unittest
{
    assert(urlSchemeAllowed("https://example.com/a"));
    assert(urlSchemeAllowed("HTTP://example.com/a"));
    assert(urlSchemeAllowed("mailto:a@b.com"));
    assert(urlSchemeAllowed("page.html"));
    assert(urlSchemeAllowed("../img/a.png"));
    assert(urlSchemeAllowed("/abs/path"));
    assert(urlSchemeAllowed("#section"));
    assert(!urlSchemeAllowed(""));
    assert(!urlSchemeAllowed("javascript:alert(1)"));
    assert(!urlSchemeAllowed("JavaScript:alert(1)"));
    assert(!urlSchemeAllowed("data:text/html,hi"));
    assert(!urlSchemeAllowed("//evil.example/a"));
    assert(!urlSchemeAllowed("java\tscript:alert(1)"));
    assert(!urlSchemeAllowed("java\nscript:alert(1)"));
}

/// Apply attribute substitutions of the form {name}.
string substituteAttributes(string text, string[string] attrs)
{
    if (attrs.length == 0)
        return text;

    auto re = regex(`\{([A-Za-z0-9_][A-Za-z0-9_-]*)\}`);
    return replaceAll!((Captures!string c) {
        auto key = c[1];
        if (auto p = key in attrs)
            return *p;
        // common builtins
        if (key == "nbsp")
            return "\u00a0";
        if (key == "zwsp")
            return "\u200b";
        if (key == "wj")
            return "\u2060";
        if (key == "apos")
            return "'";
        if (key == "quot")
            return "\"";
        if (key == "lt")
            return "<";
        if (key == "gt")
            return ">";
        if (key == "amp")
            return "&";
        return c.hit;
    })(text, re);
}

private struct Piece
{
    bool rawHtml;
    string value;
}

/// Convert AsciiDoc inline markup to HTML.
string renderInline(string text, string[string] attrs = null, bool escape = true,
    string delegate(string, bool) urlFilter = null)
{
    text = substituteAttributes(text, attrs);

    Piece[] pieces;
    auto work = text;

    // Extract passthrough +++...+++ and $$...$$ first
    work = extractPassthrough(work, pieces);

    // Links: http(s)://...[label] and link:target[label]
    work = extractLinks(work, pieces, urlFilter);

    // image:target[alt]
    work = extractImages(work, pieces, urlFilter);

    // kbd / btn / menu (experimental macros)
    work = extractUiMacros(work, pieces);

    // xref:target[text] and <<id,text>>
    work = extractXrefs(work, pieces, urlFilter);

    // footnote:[text] and footnote:id[text]
    work = extractFootnotes(work, pieces);

    // Now escape remaining text and apply formatting
    auto result = appender!string;
    size_t i = 0;
    while (i < work.length)
    {
        if (work[i] == '\x01')
        {
            // placeholder \x01 N \x02
            i++;
            size_t start = i;
            while (i < work.length && work[i] != '\x02')
                i++;
            auto idx = to!size_t(work[start .. i]);
            if (i < work.length)
                i++; // skip \x02
            auto p = pieces[idx];
            if (p.rawHtml)
                result.put(p.value);
            else
                result.put(escape ? escapeHtml(p.value) : p.value);
            continue;
        }
        // take run until next placeholder
        size_t start = i;
        while (i < work.length && work[i] != '\x01')
            i++;
        auto chunk = work[start .. i];
        result.put(formatInlineMarkup(escape ? escapeHtml(chunk) : chunk));
    }
    return result.data;
}

/// Reset per-document inline state (footnotes numbering).
void resetInlineState()
{
    footnoteCounter = 0;
}

/// When true, inline passthrough (`+++`, `$$`) is HTML-escaped instead of emitted raw.
void setSecureInlineMode(bool enabled)
{
    secureInlineMode = enabled;
}

private int footnoteCounter;
private bool secureInlineMode;

private string extractPassthrough(string work, ref Piece[] pieces)
{
    auto re = regex(`\+\+\+(.+?)\+\+\+|\$\$(.+?)\$\$`);
    return replaceAll!((Captures!string c) {
        auto content = c[1].length ? c[1] : c[2];
        auto idx = pieces.length;
        if (secureInlineMode)
            pieces ~= Piece(true, escapeHtml(content));
        else
            pieces ~= Piece(true, content);
        return "\x01" ~ to!string(idx) ~ "\x02";
    })(work, re);
}

private string anchorHtml(string url, string label, bool isImage, string delegate(string, bool) urlFilter)
{
    string accepted;
    if (!tryAcceptUrl(url, isImage, urlFilter, accepted))
        return escapeHtml(label);
    return `<a href="` ~ escapeHtml(accepted) ~ `">` ~ escapeHtml(label) ~ `</a>`;
}

private string imageHtml(string url, string alt, string delegate(string, bool) urlFilter)
{
    string accepted;
    if (!tryAcceptUrl(url, true, urlFilter, accepted))
        return escapeHtml(alt);
    return `<img src="` ~ escapeHtml(accepted) ~ `" alt="` ~ escapeHtml(alt) ~ `">`;
}

private string stash(ref Piece[] pieces, string html)
{
    auto idx = pieces.length;
    pieces ~= Piece(true, html);
    return "\x01" ~ to!string(idx) ~ "\x02";
}

private string extractLinks(string work, ref Piece[] pieces, string delegate(string, bool) urlFilter)
{
    // URL with optional [label]
    auto urlRe = regex(`(https?://[^\s\[\]]+)(?:\[([^\]]*)\])?`);
    work = replaceAll!((Captures!string c) {
        auto url = c[1];
        auto label = c[2].length ? c[2] : url;
        return stash(pieces, anchorHtml(url, label, false, urlFilter));
    })(work, urlRe);

    auto linkRe = regex(`link:([^\[]+)\[([^\]]*)\]`);
    work = replaceAll!((Captures!string c) {
        return stash(pieces, anchorHtml(c[1], c[2], false, urlFilter));
    })(work, linkRe);

    auto mailtoRe = regex(`mailto:([^\[]+)\[([^\]]*)\]`);
    work = replaceAll!((Captures!string c) {
        auto label = c[2].length ? c[2] : c[1];
        return stash(pieces, anchorHtml("mailto:" ~ c[1], label, false, urlFilter));
    })(work, mailtoRe);

    return work;
}

private string extractImages(string work, ref Piece[] pieces, string delegate(string, bool) urlFilter)
{
    auto re = regex(`image:([^\[]+)\[([^\]]*)\]`);
    return replaceAll!((Captures!string c) {
        auto alt = c[2];
        // first positional is alt; ignore width/height for now beyond alt
        auto altText = alt.split(",")[0].strip;
        return stash(pieces, imageHtml(c[1], altText, urlFilter));
    })(work, re);
}

private string extractXrefs(string work, ref Piece[] pieces, string delegate(string, bool) urlFilter)
{
    auto xrefRe = regex(`xref:([^\[]+)\[([^\]]*)\]`);
    work = replaceAll!((Captures!string c) {
        auto target = c[1];
        auto label = c[2].length ? c[2] : target;
        auto href = target.canFind("#") || target.canFind(".") ? target : ("#" ~ target);
        return stash(pieces, anchorHtml(href, label, false, urlFilter));
    })(work, xrefRe);

    auto angleRe = regex(`<<([^,>]+)(?:,([^>]*))?>>`);
    work = replaceAll!((Captures!string c) {
        auto id = c[1].strip;
        auto label = c[2].length ? c[2].strip : id;
        return stash(pieces, anchorHtml("#" ~ id, label, false, urlFilter));
    })(work, angleRe);

    return work;
}

private string extractFootnotes(string work, ref Piece[] pieces)
{
    auto re = regex(`footnote:(?:[A-Za-z0-9_-]+)?\[([^\]]*)\]`);
    return replaceAll!((Captures!string c) {
        footnoteCounter++;
        auto n = footnoteCounter;
        auto html = `<sup class="footnote">[` ~ to!string(n) ~ `]</sup>`
            ~ `<span class="footnote" id="fn-` ~ to!string(n) ~ `" hidden>`
            ~ escapeHtml(c[1]) ~ `</span>`;
        auto idx = pieces.length;
        pieces ~= Piece(true, html);
        return "\x01" ~ to!string(idx) ~ "\x02";
    })(work, re);
}

private string extractUiMacros(string work, ref Piece[] pieces)
{
    auto kbdRe = regex(`kbd:\[([^\]]*)\]`);
    work = replaceAll!((Captures!string c) {
        auto keys = c[1].split("+");
        auto app = appender!string;
        app.put(`<kbd>`);
        foreach (i, k; keys)
        {
            if (i)
                app.put("+");
            app.put(escapeHtml(k.strip));
        }
        app.put(`</kbd>`);
        auto idx = pieces.length;
        pieces ~= Piece(true, app.data);
        return "\x01" ~ to!string(idx) ~ "\x02";
    })(work, kbdRe);

    auto btnRe = regex(`btn:\[([^\]]*)\]`);
    work = replaceAll!((Captures!string c) {
        auto html = `<b class="button">[` ~ escapeHtml(c[1]) ~ `]</b>`;
        auto idx = pieces.length;
        pieces ~= Piece(true, html);
        return "\x01" ~ to!string(idx) ~ "\x02";
    })(work, btnRe);

    auto menuRe = regex(`menu:([^\[]+)\[([^\]]*)\]`);
    work = replaceAll!((Captures!string c) {
        auto html = `<span class="menu">` ~ escapeHtml(c[1]);
        if (c[2].length)
            html ~= `&nbsp;<b class="caret">&#8250;</b> ` ~ escapeHtml(c[2].replace("&gt;", "›").replace(">", "›"));
        html ~= `</span>`;
        auto idx = pieces.length;
        pieces ~= Piece(true, html);
        return "\x01" ~ to!string(idx) ~ "\x02";
    })(work, menuRe);

    return work;
}

/// Apply bold/italic/mono/etc. on already-escaped text (so markers still present).
private string formatInlineMarkup(string text)
{
    // Unconstrained then constrained. Work on escaped text; markers are ASCII.
    // Unconstrained ** **
    text = replaceAll(text, regex(`\*\*(.+?)\*\*`), `<strong>$1</strong>`);
    text = replaceAll(text, regex(`__(.+?)__`), `<em>$1</em>`);
    text = replaceAll(text, regex("``(.+?)``"), `<code>$1</code>`);
    text = replaceAll(text, regex(`##(.+?)##`), `<mark>$1</mark>`);

    // Constrained: word-boundary-ish. Use simple patterns.
    text = replaceAll(text, regex(`(^|[^\w*;])\*([^*\n]+)\*([^\w*]|$)`), `$1<strong>$2</strong>$3`);
    text = replaceAll(text, regex(`(^|[^\w_;])_([^_\n]+)_([^\w_]|$)`), `$1<em>$2</em>$3`);
    text = replaceAll(text, regex(`(^|[^\w\x60;])\x60([^\x60\n]+)\x60([^\w\x60]|$)`), `$1<code>$2</code>$3`);
    text = replaceAll(text, regex(`(^|[^\w#;])#([^#\n]+)#([^\w#]|$)`), `$1<mark>$2</mark>$3`);

    text = replaceAll(text, regex(`\^([^\^\n]+)\^`), `<sup>$1</sup>`);
    text = replaceAll(text, regex(`~([^~\n]+)~`), `<sub>$1</sub>`);

    // Replacements
    text = text.replace("-&gt;", "→").replace("=&gt;", "⇒")
        .replace("&lt;-", "←").replace("&lt;=", "⇐")
        .replace("...", "…")
        .replace("(C)", "©").replace("(R)", "®").replace("(TM)", "™");

    return text;
}

/// Join paragraph lines with hard-break support (" +" at end of line).
string joinParagraphLines(string[] lines)
{
    auto app = appender!string;
    foreach (i, line; lines)
    {
        auto stripped = line;
        if (stripped.endsWith(" +"))
        {
            app.put(stripped[0 .. $ - 2]);
            app.put("<br>\n");
        }
        else
        {
            if (i)
                app.put(" ");
            app.put(stripped);
        }
    }
    return app.data;
}
