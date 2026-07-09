module asciidoctor.ast;

import std.conv : to;

/// Base class for all document nodes.
abstract class AbstractNode
{
    string id;
    string context;
    AbstractNode parent;
    string[string] attributes;
    string[] roles;
    string title; // block title (.Title) or section title
}

/// A block that can contain other blocks (compound) or content (leaf).
class Block : AbstractNode
{
    string[] lines;
    string style; // e.g. "source", "sidebar", admonition name
    AbstractNode[] blocks;
    string contentSource; // raw / pre-joined text for leaf blocks

    string content() const
    {
        import std.array : join;

        if (contentSource.length)
            return contentSource;
        return lines.join("\n");
    }
}

class Section : Block
{
    int level; // 1..5 for == .. ======
    string sectname;
    bool numbered;
    bool discrete; // [discrete] heading — not nested, excluded from TOC

    this(int level)
    {
        this.context = "section";
        this.level = level;
        this.sectname = "sect" ~ to!string(level);
    }
}

class ListBlock : Block
{
    string listType; // ulist, olist, dlist, checklist
    int markerLevel; // nesting depth from marker length

    this(string listType)
    {
        this.context = listType;
        this.listType = listType;
    }
}

class ListItem : Block
{
    string text;
    string marker;
    int markerLevel;
    bool checklist;
    bool checked;

    this()
    {
        this.context = "list_item";
    }
}

class DescriptionListItem : Block
{
    string term;
    string definition;

    this()
    {
        this.context = "dlist_item";
    }
}

class Table : Block
{
    TableRow[] rows;
    bool hasHeader;
    string colsSpec;

    this()
    {
        this.context = "table";
    }
}

class TableRow
{
    TableCell[] cells;
    bool header;
}

class TableCell
{
    string text;
    string style; // a, e, s, l, m, h, or empty
    AbstractNode[] blocks; // for a| AsciiDoc cells
}

/// The root document node.
class Document : Block
{
    string doctitle;
    string authors;
    string revnumber;
    string revdate;
    string[string] docAttributes;
    int level;

    this()
    {
        this.context = "document";
        this.level = 0;
    }
}
