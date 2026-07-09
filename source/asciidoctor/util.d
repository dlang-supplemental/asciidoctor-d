module asciidoctor.util;

import asciidoctor.ast;
import std.algorithm;
import std.array;
import std.conv : to;
import std.regex;
import std.string;
import std.uni : isAlphaNum;

/// Slugify a title into an HTML id (AsciiDoc-ish).
string slugify(string title)
{
    auto app = appender!string;
    bool lastDash = false;
    foreach (dchar c; title.toLower)
    {
        if (isAlphaNum(c))
        {
            app.put(c);
            lastDash = false;
        }
        else if (c == ' ' || c == '-' || c == '_')
        {
            if (!lastDash && app.data.length)
            {
                app.put('-');
                lastDash = true;
            }
        }
    }
    auto s = app.data;
    while (s.endsWith("-"))
        s = s[0 .. $ - 1];
    return s.length ? s : "section";
}

/// Ensure every section has an id; return flat list in document order.
Section[] assignSectionIds(Document doc)
{
    bool[string] used;
    Section[] result;

    void walk(Block parent)
    {
        foreach (node; parent.blocks)
        {
            if (auto sec = cast(Section) node)
            {
                if (sec.discrete)
                {
                    if (!sec.id.length)
                        sec.id = slugify(sec.title);
                    // still include discrete in TOC? Asciidoctor usually excludes them.
                }
                else
                {
                    if (!sec.id.length)
                    {
                        auto base = slugify(sec.title);
                        auto id = base;
                        int n = 2;
                        while (id in used)
                        {
                            id = base ~ "-" ~ to!string(n++);
                        }
                        sec.id = id;
                    }
                    used[sec.id] = true;
                    result ~= sec;
                    walk(sec);
                }
            }
            else if (auto block = cast(Block) node)
            {
                walk(block);
            }
        }
    }

    walk(doc);
    return result;
}

/// Parse cols= spec like "1,2,1" or "1a,2,3e" into relative widths (numbers only).
int[] parseColsWidths(string colsSpec)
{
    if (!colsSpec.length)
        return null;
    int[] widths;
    foreach (part; colsSpec.split(","))
    {
        auto p = part.strip;
        // strip trailing style letters
        while (p.length && p[$ - 1].isAlpha)
            p = p[0 .. $ - 1];
        if (!p.length)
        {
            widths ~= 1;
            continue;
        }
        try
            widths ~= to!int(p);
        catch (Exception)
            widths ~= 1;
    }
    return widths;
}

private bool isAlpha(dchar c)
{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

/// Evaluate a simple ifeval expression.
/// Supports: "{attr}" == "value", "{attr}" != "value", "{n}" > 1, comparisons with numbers,
/// and bare "{attr}" (true if defined and non-empty / not "false"/"0").
bool evalIfeval(string expr, string[string] attrs)
{
    expr = expr.strip;
    if (!expr.length)
        return false;

    // Substitute {name} first for comparisons
    auto substituted = substituteAttrRefs(expr, attrs);

    // Quoted string compare: "a" == "b" or 'a' != 'b'
    auto cmpRe = regex(`^["']([^"']*)["']\s*(==|!=|>=|<=|>|<)\s*["']([^"']*)["']$`);
    if (auto m = matchFirst(substituted, cmpRe))
        return compareValues(m[1], m[2], m[3]);

    // Number compare
    auto numRe = regex(`^([0-9]+(?:\.[0-9]+)?)\s*(==|!=|>=|<=|>|<)\s*([0-9]+(?:\.[0-9]+)?)$`);
    if (auto m = matchFirst(substituted, numRe))
        return compareNumbers(m[1], m[2], m[3]);

    // Mixed: left attr-subbed bare token vs quoted/number
    auto mixRe = regex(`^(.+?)\s*(==|!=|>=|<=|>|<)\s*(.+)$`);
    if (auto m = matchFirst(substituted, mixRe))
    {
        auto left = stripQuotes(m[1].strip);
        auto right = stripQuotes(m[3].strip);
        if (isNumeric(left) && isNumeric(right))
            return compareNumbers(left, m[2], right);
        return compareValues(left, m[2], right);
    }

    // Bare truthiness after substitution
    auto v = substituted.strip;
    v = stripQuotes(v);
    if (!v.length || v == "false" || v == "0" || v == "nil" || v == "null")
        return false;
    return true;
}

private string substituteAttrRefs(string expr, string[string] attrs)
{
    auto re = regex(`\{([A-Za-z0-9_][A-Za-z0-9_-]*)\}`);
    return replaceAll!((Captures!string c) {
        if (auto p = c[1] in attrs)
            return *p;
        return "";
    })(expr, re);
}

private string stripQuotes(string s)
{
    if (s.length >= 2 && ((s.startsWith("\"") && s.endsWith("\""))
            || (s.startsWith("'") && s.endsWith("'"))))
        return s[1 .. $ - 1];
    return s;
}

private bool isNumeric(string s)
{
    if (!s.length)
        return false;
    try
    {
        to!double(s);
        return true;
    }
    catch (Exception)
        return false;
}

private bool compareValues(string left, string op, string right)
{
    switch (op)
    {
    case "==":
        return left == right;
    case "!=":
        return left != right;
    case ">":
        return left > right;
    case "<":
        return left < right;
    case ">=":
        return left >= right;
    case "<=":
        return left <= right;
    default:
        return false;
    }
}

private bool compareNumbers(string left, string op, string right)
{
    double a, b;
    try
    {
        a = to!double(left);
        b = to!double(right);
    }
    catch (Exception)
        return compareValues(left, op, right);
    switch (op)
    {
    case "==":
        return a == b;
    case "!=":
        return a != b;
    case ">":
        return a > b;
    case "<":
        return a < b;
    case ">=":
        return a >= b;
    case "<=":
        return a <= b;
    default:
        return false;
    }
}

/// Render listing content: HTML-escape, then turn &lt;N&gt; callouts into badges.
string renderListingCalloutsEscaped(string content)
{
    import asciidoctor.inline : escapeHtml;

    auto escaped = escapeHtml(content);
    return replaceAll!((Captures!string c) {
        return `<i class="conum" data-value="` ~ c[1] ~ `"><b>(` ~ c[1] ~ `)</b></i>`;
    })(escaped, regex(`&lt;(\d+)&gt;`));
}
