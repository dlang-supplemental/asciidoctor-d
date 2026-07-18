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
string renderInline(string text, string[string] attrs = null, bool escape = true)
{
    text = substituteAttributes(text, attrs);

    Piece[] pieces;
    auto work = text;

    // Extract passthrough +++...+++ and $$...$$ first
    work = extractPassthrough(work, pieces);

    // Links: http(s)://...[label] and link:target[label]
    work = extractLinks(work, pieces);

    // image:target[alt]
    work = extractImages(work, pieces);

    // kbd / btn / menu (experimental macros)
    work = extractUiMacros(work, pieces);

    // xref:target[text] and <<id,text>>
    work = extractXrefs(work, pieces);

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

private string extractLinks(string work, ref Piece[] pieces)
{
    // URL with optional [label]
    auto urlRe = regex(`(https?://[^\s\[\]]+)(?:\[([^\]]*)\])?`);
    work = replaceAll!((Captures!string c) {
        auto url = c[1];
        auto label = c[2].length ? c[2] : url;
        auto html = `<a href="` ~ escapeHtml(url) ~ `">` ~ escapeHtml(label) ~ `</a>`;
        auto idx = pieces.length;
        pieces ~= Piece(true, html);
        return "\x01" ~ to!string(idx) ~ "\x02";
    })(work, urlRe);

    auto linkRe = regex(`link:([^\[]+)\[([^\]]*)\]`);
    work = replaceAll!((Captures!string c) {
        auto html = `<a href="` ~ escapeHtml(c[1]) ~ `">` ~ escapeHtml(c[2]) ~ `</a>`;
        auto idx = pieces.length;
        pieces ~= Piece(true, html);
        return "\x01" ~ to!string(idx) ~ "\x02";
    })(work, linkRe);

    auto mailtoRe = regex(`mailto:([^\[]+)\[([^\]]*)\]`);
    work = replaceAll!((Captures!string c) {
        auto html = `<a href="mailto:` ~ escapeHtml(c[1]) ~ `">` ~ escapeHtml(c[2].length ? c[2] : c[1]) ~ `</a>`;
        auto idx = pieces.length;
        pieces ~= Piece(true, html);
        return "\x01" ~ to!string(idx) ~ "\x02";
    })(work, mailtoRe);

    return work;
}

private string extractImages(string work, ref Piece[] pieces)
{
    auto re = regex(`image:([^\[]+)\[([^\]]*)\]`);
    return replaceAll!((Captures!string c) {
        auto target = c[1];
        auto alt = c[2];
        // first positional is alt; ignore width/height for now beyond alt
        auto altText = alt.split(",")[0].strip;
        auto html = `<img src="` ~ escapeHtml(target) ~ `" alt="` ~ escapeHtml(altText) ~ `">`;
        auto idx = pieces.length;
        pieces ~= Piece(true, html);
        return "\x01" ~ to!string(idx) ~ "\x02";
    })(work, re);
}

private string extractXrefs(string work, ref Piece[] pieces)
{
    auto xrefRe = regex(`xref:([^\[]+)\[([^\]]*)\]`);
    work = replaceAll!((Captures!string c) {
        auto target = c[1];
        auto label = c[2].length ? c[2] : target;
        auto href = target.canFind("#") || target.canFind(".") ? target : ("#" ~ target);
        auto html = `<a href="` ~ escapeHtml(href) ~ `">` ~ escapeHtml(label) ~ `</a>`;
        auto idx = pieces.length;
        pieces ~= Piece(true, html);
        return "\x01" ~ to!string(idx) ~ "\x02";
    })(work, xrefRe);

    auto angleRe = regex(`<<([^,>]+)(?:,([^>]*))?>>`);
    work = replaceAll!((Captures!string c) {
        auto id = c[1].strip;
        auto label = c[2].length ? c[2].strip : id;
        auto html = `<a href="#` ~ escapeHtml(id) ~ `">` ~ escapeHtml(label) ~ `</a>`;
        auto idx = pieces.length;
        pieces ~= Piece(true, html);
        return "\x01" ~ to!string(idx) ~ "\x02";
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
