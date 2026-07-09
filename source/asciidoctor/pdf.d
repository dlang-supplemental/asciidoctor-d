module asciidoctor.pdf;

import asciidoctor.ast;
import asciidoctor.converter : Converter;
import asciidoctor.inline : joinParagraphLines, substituteAttributes;
import asciidoctor.util;
import std.array;
import std.conv : to;
import std.format;
import std.regex;
import std.string;
import std.uni : asUpperCase;

/// Minimal native PDF 1.4 backend (text + basic structure, Helvetica).
/// Produces a valid multi-page PDF without external dependencies.
class PdfConverter : Converter
{
    private string[string] attrs;
    private string[] lines;
    private enum float pageWidth = 612;
    private enum float pageHeight = 792;
    private enum float margin = 54;
    private enum float fontSize = 11;
    private enum float lineHeight = 14;
    private enum float titleSize = 18;
    private enum float headingSize = 14;

    override string convert(Document node)
    {
        attrs = node.docAttributes;
        lines.length = 0;

        if (node.doctitle.length)
        {
            pushHeading(plainInline(node.doctitle), 0);
            if (node.authors.length)
                pushText(node.authors);
            pushBlank();
        }

        foreach (block; node.blocks)
            walk(block);

        return buildPdf(lines);
    }

    private void walk(AbstractNode node)
    {
        if (auto section = cast(Section) node)
        {
            pushHeading(plainInline(section.title), section.level);
            foreach (child; section.blocks)
                walk(child);
            return;
        }
        if (auto table = cast(Table) node)
        {
            foreach (row; table.rows)
            {
                string[] cells;
                foreach (cell; row.cells)
                    cells ~= plainInline(cell.text);
                pushText(cells.join(" | "));
            }
            pushBlank();
            return;
        }
        if (auto list = cast(ListBlock) node)
        {
            size_t n = 1;
            foreach (itemNode; list.blocks)
            {
                if (auto item = cast(ListItem) itemNode)
                {
                    string prefix;
                    if (list.listType == "olist")
                        prefix = to!string(n++) ~ ". ";
                    else if (item.checklist)
                        prefix = item.checked ? "[x] " : "[ ] ";
                    else
                        prefix = "* ";
                    pushText(prefix ~ plainInline(item.text));
                    foreach (c; item.blocks)
                        walk(c);
                }
                else if (auto di = cast(DescriptionListItem) itemNode)
                {
                    pushText(plainInline(di.term) ~ ":");
                    pushText("  " ~ plainInline(di.definition));
                }
            }
            pushBlank();
            return;
        }
        if (auto block = cast(Block) node)
            walkBlock(block);
    }

    private void walkBlock(Block block)
    {
        switch (block.context)
        {
        case "paragraph":
            pushWrapped(plainInline(joinParagraphLines(block.lines)));
            pushBlank();
            break;
        case "listing":
        case "literal":
            if (block.title.length)
                pushText(plainInline(block.title));
            foreach (line; block.content.splitLines)
                pushText("    " ~ line);
            pushBlank();
            break;
        case "admonition":
            auto label = block.style.length ? block.style.asUpperCase.to!string : "NOTE";
            pushText(label ~ ": " ~ plainInline(block.content));
            foreach (c; block.blocks)
                walk(c);
            pushBlank();
            break;
        case "quote":
        case "sidebar":
        case "example":
        case "open":
            if (block.title.length)
                pushText(plainInline(block.title));
            if (block.blocks.length)
                foreach (c; block.blocks)
                    walk(c);
            else if (block.content.length)
                pushWrapped(plainInline(block.content));
            pushBlank();
            break;
        case "image":
            auto alt = block.attributes.get("alt", block.attributes.get("positional-0", "image"));
            pushText("[image: " ~ alt ~ "]");
            pushBlank();
            break;
        case "thematic_break":
            pushText("--------");
            pushBlank();
            break;
        case "page_break":
            lines ~= "\f";
            break;
        case "colist":
            size_t n = 1;
            foreach (c; block.blocks)
            {
                if (auto item = cast(ListItem) c)
                    pushText(to!string(n++) ~ ". " ~ plainInline(item.text));
            }
            pushBlank();
            break;
        case "pass":
            pushText(block.content);
            break;
        default:
            if (block.blocks.length)
                foreach (c; block.blocks)
                    walk(c);
            else if (block.content.length)
                pushWrapped(plainInline(block.content));
            break;
        }
    }

    private void pushHeading(string text, int level)
    {
        if (level <= 0)
            lines ~= "\x01" ~ text;
        else if (level == 1)
            lines ~= "\x02" ~ text;
        else
            lines ~= "\x03" ~ text;
        pushBlank();
    }

    private void pushText(string text)
    {
        lines ~= text;
    }

    private void pushBlank()
    {
        if (lines.length == 0 || lines[$ - 1] != "")
            lines ~= "";
    }

    private void pushWrapped(string text)
    {
        enum maxChars = 90;
        auto words = text.split();
        if (words.length == 0)
        {
            pushBlank();
            return;
        }
        auto cur = appender!string;
        foreach (w; words)
        {
            if (cur.data.length == 0)
                cur.put(w);
            else if (cur.data.length + 1 + w.length <= maxChars)
            {
                cur.put(" ");
                cur.put(w);
            }
            else
            {
                lines ~= cur.data;
                cur = appender!string;
                cur.put(w);
            }
        }
        if (cur.data.length)
            lines ~= cur.data;
    }

    private string plainInline(string text)
    {
        text = substituteAttributes(text, attrs);
        text = replaceAll(text, regex(`\*\*([^*]+)\*\*`), `$1`);
        text = replaceAll(text, regex(`\*([^*]+)\*`), `$1`);
        text = replaceAll(text, regex(`__([^_]+)__`), `$1`);
        text = replaceAll(text, regex(`_([^_]+)_`), `$1`);
        text = replaceAll(text, regex("`([^`]+)`"), `$1`);
        text = replaceAll(text, regex(`\+\+([^+]+)\+\+`), `$1`);
        text = replaceAll(text, regex(`link:[^\[]+\[([^\]]*)\]`), `$1`);
        text = replaceAll(text, regex(`https?://\S+\[([^\]]*)\]`), `$1`);
        text = replaceAll(text, regex(`xref:[^\[]+\[([^\]]*)\]`), `$1`);
        text = replaceAll!((Captures!string c) {
            return c[2].length ? c[2] : c[1];
        })(text, regex(`<<([^,>]+)(?:,([^>]+))?>>`));
        text = replaceAll(text, regex(`footnote:[^\[]*\[([^\]]*)\]`), `$1`);
        text = replaceAll(text, regex(`image:[^\[]+\[([^\]]*)\]`), `$1`);
        return text;
    }

    private string buildPdf(string[] srcLines)
    {
        string[][] pages;
        string[] current;
        float y = pageHeight - margin;

        void flushPage()
        {
            pages ~= current;
            current = null;
            y = pageHeight - margin;
        }

        foreach (line; srcLines)
        {
            if (line == "\f")
            {
                flushPage();
                continue;
            }
            float lh = lineHeight;
            if (line.length && line[0] == '\x01')
                lh = titleSize + 6;
            else if (line.length && line[0] == '\x02')
                lh = headingSize + 4;
            else if (line.length && line[0] == '\x03')
                lh = lineHeight + 2;
            else if (line.length == 0)
                lh = lineHeight * 0.5;

            if (current.length && y - lh < margin)
                flushPage();
            current ~= line;
            y -= lh;
        }
        if (current.length || pages.length == 0)
            flushPage();

        // Object plan:
        // 1 Catalog, 2 Pages, 3 Helvetica, 4 Helvetica-Bold,
        // then pairs of (content, page) for each page.
        struct PdfObj
        {
            string body;
        }

        PdfObj[] objs;
        objs.length = 4 + pages.length * 2;
        objs[0] = PdfObj("<< /Type /Catalog /Pages 2 0 R >>");
        objs[2] = PdfObj("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>");
        objs[3] = PdfObj("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>");

        auto kids = appender!string;
        kids.put("[ ");
        foreach (pi, pageLines; pages)
        {
            int contentId = 5 + cast(int) pi * 2; // 1-based
            int pageId = contentId + 1;
            kids.put(format("%d 0 R ", pageId));

            auto stream = appender!string;
            float cy = pageHeight - margin;
            foreach (line; pageLines)
            {
                float size = fontSize;
                string font = "/F1";
                string text = line;
                float lh = lineHeight;
                if (line.length && line[0] == '\x01')
                {
                    size = titleSize;
                    font = "/F2";
                    text = line[1 .. $];
                    lh = titleSize + 6;
                }
                else if (line.length && line[0] == '\x02')
                {
                    size = headingSize;
                    font = "/F2";
                    text = line[1 .. $];
                    lh = headingSize + 4;
                }
                else if (line.length && line[0] == '\x03')
                {
                    size = fontSize + 1;
                    font = "/F2";
                    text = line[1 .. $];
                    lh = lineHeight + 2;
                }
                else if (line.length == 0)
                {
                    cy -= lineHeight * 0.5;
                    continue;
                }

                stream.put(format("BT %s %.1f Tf 1 0 0 1 %.1f %.1f Tm (%s) Tj ET\n",
                    font, size, margin, cy, pdfEscape(text)));
                cy -= lh;
            }

            auto streamData = stream.data;
            objs[contentId - 1] = PdfObj(format("<< /Length %s >>\nstream\n%sendstream",
                streamData.length, streamData));
            objs[pageId - 1] = PdfObj(format(
                "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %.0f %.0f] "
                    ~ "/Contents %d 0 R /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> >>",
                pageWidth, pageHeight, contentId));
        }
        kids.put("]");
        objs[1] = PdfObj(format("<< /Type /Pages /Kids %s /Count %d >>",
            kids.data, pages.length));

        auto out_ = appender!string;
        out_.put("%PDF-1.4\n");
        out_.put("%\xE2\xE3\xCF\xD3\n");
        size_t[] offsets;
        offsets.length = objs.length + 1;
        foreach (i, obj; objs)
        {
            offsets[i + 1] = out_.data.length;
            out_.put(format("%d 0 obj\n%s\nendobj\n", i + 1, obj.body));
        }
        auto xrefPos = out_.data.length;
        out_.put(format("xref\n0 %d\n", objs.length + 1));
        out_.put("0000000000 65535 f \n");
        foreach (i; 1 .. objs.length + 1)
            out_.put(format("%010d 00000 n \n", offsets[i]));
        out_.put(format("trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n",
            objs.length + 1, xrefPos));
        return out_.data;
    }
}

private string pdfEscape(string s)
{
    auto app = appender!string;
    foreach (ch; s)
    {
        if (ch == '\\' || ch == '(' || ch == ')')
            app.put('\\');
        if (ch >= 32 && ch <= 126)
            app.put(ch);
        else if (ch == '\t')
            app.put(' ');
        else
            app.put('?');
    }
    return app.data;
}
