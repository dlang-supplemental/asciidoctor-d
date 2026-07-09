module asciidoctor.converter;

import asciidoctor.ast;
import asciidoctor.inline;
import asciidoctor.util;
import std.algorithm;
import std.array;
import std.conv : to;
import std.format;
import std.string;

interface Converter
{
    string convert(Document node);
}

class ConverterFactory
{
    static Converter create(string backend)
    {
        import std.uni : toLower;

        switch (backend.toLower)
        {
        case "html5":
            return new Html5Converter();
        case "manpage":
            import asciidoctor.manpage : ManpageConverter;
            return new ManpageConverter();
        case "pdf":
            import asciidoctor.pdf : PdfConverter;
            return new PdfConverter();
        default:
            throw new Exception("Unknown backend: " ~ backend);
        }
    }
}

class Html5Converter : Converter
{
    private string[string] attrs;
    private Section[] tocSections;

    override string convert(Document node)
    {
        resetInlineState();
        attrs = node.docAttributes;
        tocSections = assignSectionIds(node);
        auto app = appender!string;

        app.put("<!DOCTYPE html>\n");
        app.put("<html lang=\"en\">\n");
        app.put("<head>\n");
        app.put("<meta charset=\"UTF-8\">\n");
        app.put(
            "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n");
        if (!node.doctitle.empty)
            app.put("<title>" ~ escapeHtml(node.doctitle) ~ "</title>\n");
        app.put("<style>\n");
        app.put(defaultCss());
        app.put("</style>\n");
        app.put("</head>\n");
        app.put("<body class=\"article\">\n");
        app.put("<div id=\"header\">\n");
        if (!node.doctitle.empty)
            app.put("<h1>" ~ renderInline(node.doctitle, attrs) ~ "</h1>\n");
        if (!node.authors.empty)
            app.put("<div class=\"details\"><span id=\"author\" class=\"author\">"
                ~ escapeHtml(node.authors) ~ "</span></div>\n");
        if ("toc" in attrs)
            app.put(renderToc());
        app.put("</div>\n");
        app.put("<div id=\"content\">\n");

        foreach (block; node.blocks)
            app.put(convertNode(block));

        app.put("</div>\n");
        app.put("</body>\n");
        app.put("</html>\n");
        return app.data;
    }

    private string renderToc()
    {
        auto title = attrs.get("toc-title", "Table of Contents");
        int maxLevel = 2;
        if (auto p = "toclevels" in attrs)
        {
            try
                maxLevel = to!int(*p);
            catch (Exception)
            {
            }
        }
        return renderTocStacked(title, maxLevel);
    }

    private string renderTocStacked(string title, int maxLevel)
    {
        auto app = appender!string;
        app.put(`<div id="toc" class="toc">`);
        app.put(`<div id="toctitle">` ~ escapeHtml(title) ~ `</div>`);
        auto filtered = tocSections.filter!(s => !s.discrete && s.level <= maxLevel).array;
        app.put(buildTocList(filtered, 1, 0, filtered.length));
        app.put(`</div>` ~ "\n");
        return app.data;
    }

    private string buildTocList(Section[] secs, int level, size_t start, size_t end)
    {
        auto app = appender!string;
        bool opened = false;
        size_t i = start;
        while (i < end)
        {
            auto sec = secs[i];
            if (sec.level < level)
                break;
            if (sec.level > level)
            {
                // shouldn't happen at start; skip orphan deeper
                i++;
                continue;
            }
            if (!opened)
            {
                app.put(`<ul class="sectlevel` ~ to!string(level) ~ `">`);
                opened = true;
            }
            app.put(`<li><a href="#` ~ escapeHtml(sec.id) ~ `">`
                ~ renderInline(sec.title, attrs) ~ `</a>`);
            // children
            size_t j = i + 1;
            while (j < end && secs[j].level > level)
                j++;
            if (j > i + 1)
                app.put(buildTocList(secs, level + 1, i + 1, j));
            app.put(`</li>`);
            i = j;
        }
        if (opened)
            app.put(`</ul>`);
        return app.data;
    }

    private string convertNode(AbstractNode node)
    {
        if (auto section = cast(Section) node)
            return convertSection(section);
        if (auto table = cast(Table) node)
            return convertTable(table);
        if (auto list = cast(ListBlock) node)
            return convertList(list);
        if (auto block = cast(Block) node)
            return convertBlock(block);
        return "";
    }

    private string convertBlock(Block block)
    {
        switch (block.context)
        {
        case "paragraph":
            return convertParagraph(block);
        case "listing":
        case "literal":
            return convertListing(block);
        case "pass":
            return block.content;
        case "admonition":
            return convertAdmonition(block);
        case "quote":
            return convertQuote(block);
        case "sidebar":
            return convertSidebar(block);
        case "example":
            return convertExample(block);
        case "open":
            return convertOpen(block);
        case "image":
            return convertImage(block);
        case "thematic_break":
            return "<hr>\n";
        case "page_break":
            return `<div style="page-break-after:always;"></div>` ~ "\n";
        case "colist":
            return convertColist(block);
        default:
            if (block.blocks.length)
            {
                auto app = appender!string;
                foreach (c; block.blocks)
                    app.put(convertNode(c));
                return app.data;
            }
            return "";
        }
    }

    private string convertParagraph(Block block)
    {
        auto joined = joinParagraphLines(block.lines);
        auto body = renderInline(joined, attrs);
        auto cls = block.style == "lead" ? "paragraph lead" : "paragraph";
        return `<div class="` ~ cls ~ `"><p>` ~ body ~ `</p></div>` ~ "\n";
    }

    private string convertListing(Block block)
    {
        auto app = appender!string;
        auto lang = "";
        if (auto p = "language" in block.attributes)
            lang = *p;
        else if (auto p = "positional-1" in block.attributes)
            lang = *p;

        auto isSource = block.style == "source" || lang.length > 0
            || block.context == "listing";
        if (block.title.length)
            app.put(`<div class="title">` ~ renderInline(block.title, attrs) ~ `</div>` ~ "\n");

        auto outer = block.context == "literal" ? "literalblock" : "listingblock";
        app.put(`<div class="` ~ outer ~ `">`);
        app.put(`<div class="content">`);
        auto body = renderListingCalloutsEscaped(block.content);
        if (isSource && block.context != "literal")
        {
            app.put(`<pre class="highlight"><code`);
            if (lang.length)
                app.put(` class="language-` ~ escapeHtml(lang) ~ `" data-lang="` ~ escapeHtml(lang) ~ `"`);
            app.put(`>`);
            app.put(body);
            app.put(`</code></pre>`);
        }
        else
        {
            app.put(`<pre>`);
            app.put(body);
            app.put(`</pre>`);
        }
        app.put(`</div></div>` ~ "\n");
        return app.data;
    }

    private string convertColist(Block block)
    {
        auto app = appender!string;
        app.put(`<div class="colist arabic"><ol>`);
        foreach (c; block.blocks)
        {
            if (auto item = cast(ListItem) c)
                app.put(`<li><p>` ~ renderInline(item.text, attrs) ~ `</p></li>`);
        }
        app.put(`</ol></div>` ~ "\n");
        return app.data;
    }

    private string convertAdmonition(Block block)
    {
        auto name = block.style.length ? block.style : "NOTE";
        auto app = appender!string;
        app.put(`<div class="admonitionblock ` ~ name.toLower ~ `">`);
        app.put(`<table><tr>`);
        app.put(`<td class="icon"><div class="title">` ~ escapeHtml(name) ~ `</div></td>`);
        app.put(`<td class="content">`);
        if (block.title.length)
            app.put(`<div class="title">` ~ renderInline(block.title, attrs) ~ `</div>`);
        if (block.blocks.length)
        {
            foreach (c; block.blocks)
                app.put(convertNode(c));
        }
        else
        {
            auto joined = joinParagraphLines(block.lines);
            app.put(renderInline(joined, attrs));
        }
        app.put(`</td></tr></table></div>` ~ "\n");
        return app.data;
    }

    private string convertQuote(Block block)
    {
        auto app = appender!string;
        app.put(`<div class="quoteblock">`);
        if (block.title.length)
            app.put(`<div class="title">` ~ renderInline(block.title, attrs) ~ `</div>`);
        app.put(`<blockquote>`);
        if (block.blocks.length)
        {
            foreach (c; block.blocks)
                app.put(convertNode(c));
        }
        else
            app.put(`<p>` ~ renderInline(joinParagraphLines(block.lines), attrs) ~ `</p>`);
        app.put(`</blockquote>`);
        string attribution;
        string citetitle;
        if (auto p = "positional-1" in block.attributes)
            attribution = *p;
        if (auto p = "positional-2" in block.attributes)
            citetitle = *p;
        if (attribution.length || citetitle.length)
        {
            app.put(`<div class="attribution">`);
            if (attribution.length)
                app.put(`— ` ~ escapeHtml(attribution));
            if (citetitle.length)
                app.put(`<br><cite>` ~ escapeHtml(citetitle) ~ `</cite>`);
            app.put(`</div>`);
        }
        app.put(`</div>` ~ "\n");
        return app.data;
    }

    private string convertSidebar(Block block)
    {
        auto app = appender!string;
        app.put(`<div class="sidebarblock">`);
        app.put(`<div class="content">`);
        if (block.title.length)
            app.put(`<div class="title">` ~ renderInline(block.title, attrs) ~ `</div>`);
        foreach (c; block.blocks)
            app.put(convertNode(c));
        if (!block.blocks.length && block.lines.length)
            app.put(`<div class="paragraph"><p>` ~ renderInline(joinParagraphLines(block.lines),
                attrs) ~ `</p></div>`);
        app.put(`</div></div>` ~ "\n");
        return app.data;
    }

    private string convertExample(Block block)
    {
        auto app = appender!string;
        app.put(`<div class="exampleblock">`);
        app.put(`<div class="content">`);
        if (block.title.length)
            app.put(`<div class="title">` ~ renderInline(block.title, attrs) ~ `</div>`);
        foreach (c; block.blocks)
            app.put(convertNode(c));
        app.put(`</div></div>` ~ "\n");
        return app.data;
    }

    private string convertOpen(Block block)
    {
        auto app = appender!string;
        app.put(`<div class="openblock"><div class="content">`);
        foreach (c; block.blocks)
            app.put(convertNode(c));
        app.put(`</div></div>` ~ "\n");
        return app.data;
    }

    private string convertImage(Block block)
    {
        auto target = block.attributes.get("target", "");
        auto alt = block.attributes.get("alt", "");
        auto imagesdir = attrs.get("imagesdir", "");
        if (imagesdir.length && !target.canFind("://") && !target.startsWith("/"))
            target = imagesdir ~ "/" ~ target;
        auto app = appender!string;
        app.put(`<div class="imageblock">`);
        app.put(`<div class="content">`);
        app.put(`<img src="` ~ escapeHtml(target) ~ `" alt="` ~ escapeHtml(alt) ~ `"`);
        if (auto w = "width" in block.attributes)
            if ((*w).length)
                app.put(` width="` ~ escapeHtml(*w) ~ `"`);
        if (auto h = "height" in block.attributes)
            if ((*h).length)
                app.put(` height="` ~ escapeHtml(*h) ~ `"`);
        app.put(`>`);
        app.put(`</div>`);
        if (block.title.length)
            app.put(`<div class="title">` ~ renderInline(block.title, attrs) ~ `</div>`);
        app.put(`</div>` ~ "\n");
        return app.data;
    }

    private string convertSection(Section section)
    {
        auto app = appender!string;
        auto level = section.level;
        auto tag = "h" ~ to!string(level + 1);
        if (section.discrete)
        {
            app.put(`<` ~ tag);
            if (section.id.length)
                app.put(` id="` ~ escapeHtml(section.id) ~ `"`);
            app.put(` class="discrete">` ~ renderInline(section.title, attrs) ~ `</` ~ tag ~ `>` ~ "\n");
            return app.data;
        }
        app.put(`<div class="sect` ~ to!string(level) ~ `">`);
        app.put(`<` ~ tag);
        if (section.id.length)
            app.put(` id="` ~ escapeHtml(section.id) ~ `"`);
        app.put(`>` ~ renderInline(section.title, attrs) ~ `</` ~ tag ~ `>`);
        app.put(`<div class="sectionbody">`);
        foreach (child; section.blocks)
            app.put(convertNode(child));
        app.put(`</div></div>` ~ "\n");
        return app.data;
    }

    private string convertListItem(ListItem item, string listType, string listStyle)
    {
        auto app = appender!string;
        app.put(`<li>`);
        if (item.checklist || listStyle == "checklist")
        {
            auto mark = item.checked ? "&#10003;" : "&#10063;";
            app.put(`<p>` ~ mark ~ ` ` ~ renderInline(item.text, attrs) ~ `</p>`);
        }
        else
            app.put(`<p>` ~ renderInline(item.text, attrs) ~ `</p>`);
        if (item.lines.length)
            app.put(`<p>` ~ renderInline(joinParagraphLines(item.lines), attrs) ~ `</p>`);

        ListItem[] nestedItems;
        foreach (c; item.blocks)
        {
            if (auto ni = cast(ListItem) c)
                nestedItems ~= ni;
            else
                app.put(convertNode(c));
        }
        if (nestedItems.length)
        {
            auto ntag = listType == "olist" ? "ol" : "ul";
            app.put(`<` ~ ntag ~ `>`);
            foreach (ni; nestedItems)
                app.put(convertListItem(ni, listType, listStyle));
            app.put(`</` ~ ntag ~ `>`);
        }
        app.put(`</li>`);
        return app.data;
    }

    private string convertList(ListBlock list)
    {
        if (list.listType == "dlist")
            return convertDlist(list);
        if (list.listType == "colist")
            return convertColist(list);

        auto app = appender!string;
        auto tag = list.listType == "olist" ? "ol" : "ul";
        auto cls = list.style == "checklist" ? ` class="checklist"` : "";
        app.put(`<div class="` ~ list.listType ~ `">`);
        app.put(`<` ~ tag ~ cls ~ `>`);
        foreach (node; list.blocks)
        {
            auto item = cast(ListItem) node;
            if (item is null)
                continue;
            app.put(convertListItem(item, list.listType, list.style));
        }
        app.put(`</` ~ tag ~ `></div>` ~ "\n");
        return app.data;
    }

    private string convertDlist(ListBlock list)
    {
        auto app = appender!string;
        app.put(`<div class="dlist"><dl>`);
        foreach (node; list.blocks)
        {
            auto item = cast(DescriptionListItem) node;
            if (item is null)
                continue;
            app.put(`<dt class="hdlist1">` ~ renderInline(item.term, attrs) ~ `</dt>`);
            app.put(`<dd>` ~ renderInline(item.definition, attrs) ~ `</dd>`);
        }
        app.put(`</dl></div>` ~ "\n");
        return app.data;
    }

    private string convertTable(Table table)
    {
        auto app = appender!string;
        auto widths = parseColsWidths(table.colsSpec);
        int total = 0;
        foreach (w; widths)
            total += w;

        app.put(`<table class="tableblock frame-all grid-all stretch">`);
        if (table.title.length)
            app.put(`<caption class="title">` ~ renderInline(table.title, attrs) ~ `</caption>`);
        if (widths.length && total > 0)
        {
            app.put(`<colgroup>`);
            foreach (w; widths)
            {
                auto pct = (w * 100) / total;
                app.put(`<col style="width:` ~ to!string(pct) ~ `%;">`);
            }
            app.put(`</colgroup>`);
        }
        bool headerDone = false;
        foreach (row; table.rows)
        {
            if (row.header && !headerDone)
            {
                app.put(`<thead>`);
                app.put(`<tr>`);
                foreach (cell; row.cells)
                    app.put(`<th class="tableblock">` ~ renderCellContent(cell) ~ `</th>`);
                app.put(`</tr></thead><tbody>`);
                headerDone = true;
                continue;
            }
            if (!headerDone)
            {
                app.put(`<tbody>`);
                headerDone = true;
            }
            app.put(`<tr>`);
            foreach (cell; row.cells)
            {
                auto tag = cell.style == "h" ? "th" : "td";
                app.put(`<` ~ tag ~ ` class="tableblock">` ~ renderCellContent(cell)
                    ~ `</` ~ tag ~ `>`);
            }
            app.put(`</tr>`);
        }
        if (headerDone)
            app.put(`</tbody>`);
        app.put(`</table>` ~ "\n");
        return app.data;
    }

    private string renderCellContent(TableCell cell)
    {
        if (cell.style == "a" && cell.blocks.length)
        {
            auto app = appender!string;
            foreach (b; cell.blocks)
                app.put(convertNode(b));
            return app.data;
        }
        if (cell.style == "l" || cell.style == "m")
            return `<p class="tableblock"><code>` ~ escapeHtml(cell.text) ~ `</code></p>`;
        if (cell.style == "e")
            return `<p class="tableblock"><em>` ~ renderInline(cell.text, attrs) ~ `</em></p>`;
        if (cell.style == "s")
            return `<p class="tableblock"><strong>` ~ renderInline(cell.text, attrs) ~ `</strong></p>`;
        return renderInline(cell.text, attrs);
    }

    private string defaultCss()
    {
        return `
body{font-family:system-ui,sans-serif;line-height:1.5;max-width:52rem;margin:1.5rem auto;padding:0 1rem;color:#1a1a1a}
#header h1{font-size:2rem;margin-bottom:.25rem}
.details{color:#555;margin-bottom:1.5rem}
#toc{margin:1rem 0 1.5rem;padding:1rem;background:#f7f7f7;border:1px solid #e0e0e0;border-radius:4px}
#toctitle{font-weight:700;margin-bottom:.5rem}
#toc ul{margin:.25rem 0;padding-left:1.25rem}
#toc a{text-decoration:none;color:#1a5276}
#toc a:hover{text-decoration:underline}
h2{border-bottom:1px solid #ddd;padding-bottom:.2rem}
h2.discrete,h3.discrete,h4.discrete{border:0;font-style:italic;color:#444}
.admonitionblock{margin:1rem 0;border-left:4px solid #4a90d9;background:#f5f9fc;padding:.5rem .75rem}
.admonitionblock.important,.admonitionblock.warning,.admonitionblock.caution{border-left-color:#c0392b;background:#fdf2f2}
.admonitionblock.tip{border-left-color:#27ae60;background:#f2fdf6}
.admonitionblock table{border:0;width:100%}
.admonitionblock .icon .title{font-weight:700;margin-right:.75rem}
.listingblock,.literalblock{margin:1rem 0}
.listingblock pre,.literalblock pre{background:#f4f4f4;padding:.75rem 1rem;overflow:auto;border-radius:4px}
.conum{font-style:normal;background:#333;color:#fff;border-radius:50%;display:inline-block;width:1.2em;height:1.2em;text-align:center;line-height:1.2em;font-size:.75em;margin:0 .15em}
.conum b{font-weight:700}
.colist{margin:.5rem 0 1rem}
.sidebarblock{border:1px solid #ddd;background:#fafafa;padding:1rem;margin:1rem 0}
.quoteblock{margin:1rem 0;padding-left:1rem;border-left:3px solid #ccc}
.quoteblock .attribution{text-align:right;color:#555;margin-top:.5rem}
table.tableblock{border-collapse:collapse;width:100%;margin:1rem 0}
table.tableblock th,table.tableblock td{border:1px solid #ccc;padding:.4rem .6rem;vertical-align:top}
table.tableblock th{background:#f0f0f0}
.imageblock{margin:1rem 0;text-align:center}
.paragraph.lead p{font-size:1.15rem;font-weight:350}
code{background:#f4f4f4;padding:.1rem .3rem;border-radius:3px}
`;
    }
}
