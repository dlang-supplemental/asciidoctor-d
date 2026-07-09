module asciidoctor.semantictokens;

import asciidoctor.ast;
import asciidoctor.parser;
import asciidoctor.util;
import std.algorithm;
import std.array;
import std.conv : to;
import std.regex;
import std.string;

/// LSP semantic token types we emit (subset of the standard legend + custom).
enum TokenType : uint
{
    namespace = 0, // attribute names / defs
    type = 1, // block styles
    class_ = 2, // section titles
    enumMember = 3, // admonition labels
    function_ = 4, // macros
    variable = 5, // attribute refs
    string_ = 6, // quoted / paragraph text spans we care about
    keyword = 7, // directives, list markers
    comment = 8,
    operator = 9, // delimiters
}

enum TokenMod : uint
{
    none = 0,
    declaration = 1 << 0,
    documentation = 1 << 1,
}

struct SemanticToken
{
    uint line; // 0-based
    uint startChar; // 0-based UTF-16-ish (we use byte/code-unit offset; ASCII-safe)
    uint length;
    TokenType type;
    uint modifiers;
}

struct SemanticTokensResult
{
    string[] legendTypes;
    string[] legendModifiers;
    SemanticToken[] tokens;
    Document document;
}

/// Legend advertised to LSP clients.
string[] tokenTypeLegend()
{
    return [
        "namespace", "type", "class", "enumMember", "function", "variable",
        "string", "keyword", "comment", "operator"
    ];
}

string[] tokenModifierLegend()
{
    return ["declaration", "documentation"];
}

/// Parse source and produce semantic tokens for editor highlighting.
SemanticTokensResult semanticTokens(string source, string baseDir = ".")
{
    auto parser = new Parser(source, baseDir);
    auto doc = parser.parse();
    assignSectionIds(doc);

    SemanticToken[] tokens;
    auto lines = source.splitLines();

    void add(uint line, uint start, uint len, TokenType type, uint mods = TokenMod.none)
    {
        if (len == 0)
            return;
        tokens ~= SemanticToken(line, start, len, type, mods);
    }

    // Line-oriented scan (fast, aligned with AsciiDoc's line grammar).
    foreach (i, line; lines)
    {
        auto s = line;
        auto stripped = s.stripLeft;
        auto indent = cast(uint)(s.length - stripped.length);
        auto u = cast(uint) i;

        if (!stripped.length)
            continue;

        if (stripped.startsWith("//") && !stripped.startsWith("////"))
        {
            add(u, 0, cast(uint) s.length, TokenType.comment);
            continue;
        }

        if (isDelimiter(stripped, '/') || isDelimiter(stripped, '-')
            || isDelimiter(stripped, '.') || isDelimiter(stripped, '*')
            || isDelimiter(stripped, '=') || isDelimiter(stripped, '_')
            || isDelimiter(stripped, '+') || stripped == "--" || stripped == "'''"
            || stripped == "<<<" || stripped.startsWith("|==="))
        {
            add(u, indent, cast(uint) stripped.length, TokenType.operator);
            continue;
        }

        int level;
        string title;
        if (matchSectionTitle(stripped, level, title))
        {
            auto markLen = cast(uint)(level + 1);
            add(u, indent, markLen, TokenType.operator);
            auto titleStart = indent + markLen;
            while (titleStart < s.length && (s[titleStart] == ' ' || s[titleStart] == '\t'))
                titleStart++;
            add(u, titleStart, cast(uint)(s.length - titleStart), TokenType.class_);
            continue;
        }

        string name, value;
        if (matchAttrEntry(stripped, name, value))
        {
            add(u, indent, cast(uint) stripped.length, TokenType.namespace, TokenMod.declaration);
            continue;
        }

        if (stripped.startsWith("[") && stripped.endsWith("]"))
        {
            add(u, indent, cast(uint) stripped.length, TokenType.type);
            continue;
        }

        if (stripped.startsWith("include::") || stripped.startsWith("ifdef::")
            || stripped.startsWith("ifndef::") || stripped.startsWith("ifeval::")
            || stripped.startsWith("endif::") || stripped.startsWith("image::"))
        {
            add(u, indent, cast(uint) stripped.length, TokenType.function_);
            continue;
        }

        string admon, text;
        if (matchAdmonitionParagraph(stripped, admon, text))
        {
            add(u, indent, cast(uint)(admon.length + 1), TokenType.enumMember);
            continue;
        }

        string marker, itemText;
        int mlevel;
        bool ordered, checklist, checked;
        if (matchListItem(stripped, marker, itemText, mlevel, ordered, checklist, checked))
        {
            add(u, indent, cast(uint) marker.length, TokenType.keyword);
            continue;
        }

        string ct;
        if (matchCalloutListItem(stripped, ct))
        {
            add(u, indent, cast(uint) stripped.indexOf('>') + 1 - indent, TokenType.keyword);
            continue;
        }

        // Inline attribute refs and macros on the line
        foreach (m; matchAll(s, regex(`\{[A-Za-z0-9_][A-Za-z0-9_-]*\}`)))
            add(u, cast(uint) m.pre.length, cast(uint) m.hit.length, TokenType.variable);

        foreach (m; matchAll(s, regex(`(?:https?://[^\s\[\]]+|link:|xref:|mailto:|image:|kbd:|btn:|menu:|footnote:)`)))
            add(u, cast(uint) m.pre.length, cast(uint) m.hit.length, TokenType.function_);
    }

    // Sort by line/char as LSP requires
    tokens.sort!((a, b) => a.line < b.line || (a.line == b.line && a.startChar < b.startChar));

    SemanticTokensResult result;
    result.legendTypes = tokenTypeLegend();
    result.legendModifiers = tokenModifierLegend();
    result.tokens = tokens;
    result.document = doc;
    return result;
}

/// Encode tokens as LSP `data` integer array (delta-encoded).
uint[] encodeLspData(SemanticToken[] tokens)
{
    uint[] data;
    uint prevLine = 0;
    uint prevChar = 0;
    foreach (i, t; tokens)
    {
        uint dLine = t.line - (i ? prevLine : 0);
        uint dChar = (i && t.line == prevLine) ? (t.startChar - prevChar) : t.startChar;
        data ~= dLine;
        data ~= dChar;
        data ~= t.length;
        data ~= cast(uint) t.type;
        data ~= t.modifiers;
        prevLine = t.line;
        prevChar = t.startChar;
    }
    return data;
}
