module asciidoctor.manpage;

import asciidoctor.ast;
import asciidoctor.converter : Converter;
import asciidoctor.inline : joinParagraphLines, substituteAttributes;
import asciidoctor.util;
import std.array;
import std.conv : to;
import std.regex;
import std.string;
import std.uni : asUpperCase;

/// Groff man-page backend (compatible with `man` / `groff -man`).
class ManpageConverter : Converter
{
    private string[string] attrs;

    override string convert(Document node)
    {
        attrs = node.docAttributes.dup;
        deriveManMetadata(node);
        harvestNameSection(node);

        auto app = appender!string;
        auto mantitle = attrs.get("mantitle", "UNTITLED");
        auto manvolnum = attrs.get("manvolnum", "1");
        auto manname = attrs.get("manname", mantitle);
        auto mansource = attrs.get("mansource", `\ \&`);
        auto manmanual = attrs.get("manmanual", `\ \&`);
        auto docdate = attrs.get("docdate", attrs.get("revdate", ""));

        app.put(`'\" t` ~ "\n");
        app.put(`.\"     Title: ` ~ mantitle ~ "\n");
        app.put(`.\"    Author: ` ~ (node.authors.length ? node.authors : "[see the \"AUTHORS\" section]") ~ "\n");
        app.put(`.\" Generator: asciidoctor-d manpage backend` ~ "\n");
        app.put(`.TH "` ~ manify(manname.asUpperCase.to!string) ~ `" "` ~ manify(manvolnum) ~ `" "`
            ~ manify(docdate) ~ `" "` ~ manify(mansource) ~ `" "` ~ manify(manmanual) ~ `"` ~ "\n");
        app.put(`.ie \n(.g .ds Aq \(aq` ~ "\n");
        app.put(`.el       .ds Aq '` ~ "\n");
        app.put(`.ss \n[.ss] 0` ~ "\n");
        app.put(`.nh` ~ "\n");
        app.put(`.ad l` ~ "\n");

        // Emit synthetic NAME only when purpose came from attributes, not a NAME section.
        if (("manpurpose" in attrs) && !hasNameSection(node))
        {
            app.put(`.SH "NAME"` ~ "\n");
            app.put(manify(manname) ~ ` \- ` ~ manify(attrs["manpurpose"]) ~ "\n");
        }

        foreach (block; node.blocks)
            app.put(convertNode(block));

        return app.data;
    }

    private bool hasNameSection(Document node)
    {
        foreach (block; node.blocks)
        {
            if (auto section = cast(Section) block)
            {
                if (section.level <= 1
                    && plainInline(section.title).asUpperCase.to!string == "NAME")
                    return true;
            }
        }
        return false;
    }

    private void harvestNameSection(Document node)
    {
        if ("manpurpose" in attrs)
            return;
        foreach (block; node.blocks)
        {
            if (auto section = cast(Section) block)
            {
                if (section.level > 1)
                    continue;
                if (plainInline(section.title).asUpperCase.to!string != "NAME")
                    continue;
                foreach (child; section.blocks)
                {
                    if (auto b = cast(Block) child)
                    {
                        if (b.context != "paragraph")
                            continue;
                        auto body = plainInline(joinParagraphLines(b.lines));
                        auto m = matchFirst(body, regex(`^\s*(\S+)\s+\\?-\s+(.+)$`));
                        if (!m)
                            m = matchFirst(body, regex(`^\s*(\S+)\s+[—–-]\s+(.+)$`));
                        if (m)
                        {
                            attrs["manname"] = m[1];
                            attrs["manpurpose"] = m[2];
                        }
                        return;
                    }
                }
            }
        }
    }

    private void deriveManMetadata(Document node)
    {
        if (("mantitle" in attrs) is null || ("manvolnum" in attrs) is null)
        {
            auto title = node.doctitle.length ? node.doctitle : attrs.get("doctitle", "");
            auto m = matchFirst(title, regex(`^([^\s(]+)\(([0-9][a-zA-Z]?)\)\s*$`));
            if (m)
            {
                if (("mantitle" in attrs) is null)
                    attrs["mantitle"] = m[1];
                if (("manvolnum" in attrs) is null)
                    attrs["manvolnum"] = m[2];
            }
            else if (("mantitle" in attrs) is null && title.length)
            {
                attrs["mantitle"] = title;
            }
        }
        if (("manname" in attrs) is null)
            attrs["manname"] = attrs.get("mantitle", "untitled");
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

    private string convertSection(Section section)
    {
        auto app = appender!string;
        auto title = plainInline(section.title);
        // Groff man pages conventionally use uppercase .SH titles.
        if (section.level <= 1)
            title = title.asUpperCase.to!string;
        auto macro_ = section.level <= 1 ? ".SH" : ".SS";
        app.put(macro_ ~ ` "` ~ manify(title) ~ `"` ~ "\n");

        foreach (child; section.blocks)
            app.put(convertNode(child));
        return app.data;
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
            return manify(block.content) ~ "\n";
        case "admonition":
            return convertAdmonition(block);
        case "quote":
        case "sidebar":
        case "example":
        case "open":
            return convertCompound(block);
        case "image":
            auto alt = block.attributes.get("alt", block.attributes.get("positional-0", "image"));
            return `.PP` ~ "\n" ~ `[image: ` ~ manify(alt) ~ `]` ~ "\n";
        case "thematic_break":
        case "page_break":
            return `.sp` ~ "\n";
        case "colist":
            return convertColist(block);
        default:
            return convertCompound(block);
        }
    }

    private string convertCompound(Block block)
    {
        auto app = appender!string;
        if (block.title.length)
            app.put(`.PP` ~ "\n" ~ `\fB` ~ manify(plainInline(block.title)) ~ `\fP` ~ "\n");
        if (block.blocks.length)
        {
            foreach (c; block.blocks)
                app.put(convertNode(c));
        }
        else if (block.content.length)
        {
            app.put(`.PP` ~ "\n");
            app.put(manify(plainInline(block.content)) ~ "\n");
        }
        return app.data;
    }

    private string convertParagraph(Block block)
    {
        auto joined = joinParagraphLines(block.lines);
        return `.PP` ~ "\n" ~ manify(plainInline(joined)) ~ "\n";
    }

    private string convertListing(Block block)
    {
        auto app = appender!string;
        if (block.title.length)
            app.put(`.PP` ~ "\n" ~ `\fB` ~ manify(plainInline(block.title)) ~ `\fP` ~ "\n");
        app.put(`.sp` ~ "\n");
        app.put(`.nf` ~ "\n");
        app.put(`.RS 4` ~ "\n");
        foreach (line; block.content.splitLines)
            app.put(manify(line) ~ "\n");
        app.put(`.RE` ~ "\n");
        app.put(`.fi` ~ "\n");
        return app.data;
    }

    private string convertAdmonition(Block block)
    {
            auto label = block.style.length ? block.style.asUpperCase.to!string : "NOTE";
        auto app = appender!string;
        app.put(`.PP` ~ "\n");
        app.put(`\fB` ~ manify(label) ~ `:\fP `);
        if (block.blocks.length)
        {
            app.put("\n");
            foreach (c; block.blocks)
                app.put(convertNode(c));
        }
        else
            app.put(manify(plainInline(block.content)) ~ "\n");
        return app.data;
    }

    private string convertList(ListBlock list)
    {
        if (list.listType == "dlist")
            return convertDlist(list);
        auto app = appender!string;
        size_t n = 1;
        foreach (itemNode; list.blocks)
        {
            if (auto item = cast(ListItem) itemNode)
            {
                app.put(`.IP `);
                if (list.listType == "olist")
                    app.put(`\fB` ~ to!string(n++) ~ `.\fP 3` ~ "\n");
                else if (item.checklist)
                    app.put((item.checked ? `[*]` : `[ ]`) ~ ` 4` ~ "\n");
                else
                    app.put(`\(bu 2` ~ "\n");
                app.put(manify(plainInline(item.text)) ~ "\n");
                foreach (c; item.blocks)
                    app.put(convertNode(c));
            }
        }
        return app.data;
    }

    private string convertDlist(ListBlock list)
    {
        auto app = appender!string;
        foreach (itemNode; list.blocks)
        {
            if (auto item = cast(DescriptionListItem) itemNode)
            {
                app.put(`.TP` ~ "\n");
                app.put(manify(plainInline(item.term)) ~ "\n");
                app.put(manify(plainInline(item.definition)) ~ "\n");
            }
        }
        return app.data;
    }

    private string convertColist(Block block)
    {
        auto app = appender!string;
        size_t n = 1;
        foreach (c; block.blocks)
        {
            if (auto item = cast(ListItem) c)
            {
                app.put(`.IP ` ~ to!string(n++) ~ ` 3` ~ "\n");
                app.put(manify(plainInline(item.text)) ~ "\n");
            }
        }
        return app.data;
    }

    private string convertTable(Table table)
    {
        auto app = appender!string;
        app.put(`.PP` ~ "\n");
        foreach (row; table.rows)
        {
            string[] cells;
            foreach (cell; row.cells)
                cells ~= plainInline(cell.text);
            app.put(manify(cells.join(" | ")) ~ "\n");
            app.put(`.br` ~ "\n");
        }
        return app.data;
    }

    private string plainInline(string text)
    {
        text = substituteAttributes(text, attrs);
        // Strip common AsciiDoc inline markup to plain text.
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
        text = replaceAll(text, regex(`kbd:\[([^\]]*)\]`), `$1`);
        text = replaceAll(text, regex(`btn:\[([^\]]*)\]`), `$1`);
        return text;
    }
}

/// Escape text for troff/man macros.
string manify(string s)
{
    if (s.length == 0)
        return `\ \&`;
    // Escape leading dots/apostrophes and backslashes.
    auto app = appender!string;
    foreach (i, ch; s)
    {
        if (ch == '\\')
            app.put(`\e`);
        else if (ch == '-' )
            app.put(`\-`);
        else if ((i == 0 || s[i - 1] == '\n') && (ch == '.' || ch == '\''))
        {
            app.put(`\&`);
            app.put(ch);
        }
        else
            app.put(ch);
    }
    return app.data;
}
