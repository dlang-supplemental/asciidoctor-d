module asciidoctor.ast;

/// Base class for all document nodes
abstract class AbstractNode
{
    string id;
    string context;
    AbstractNode parent;
    string[string] attributes;
}

/// A block that can contain other blocks (compound) or content (leaf)
class Block : AbstractNode
{
    string[] lines;
    string title;
    string style; // e.g. "source", "sidebar"
    AbstractNode[] blocks;
    
    // For simple blocks that just have text lines
    string content() {
        import std.array : join;
        return lines.join("\n");
    }
}

class Section : Block
{
    int level;
    string sectname; // sect1, sect2, etc.
    bool numbered;

    this(int level)
    {
        this.context = "section";
        this.level = level;
    }
}

class List : Block
{
    string type; // ulist, olist, dlist
    
    this(string type)
    {
        this.context = type;
        this.type = type;
    }
}

class ListItem : Block
{
    string text;
    string marker;

    this()
    {
        this.context = "list_item";
    }
}

/// The root document node
class Document : Block
{
    string doctitle;
    
    this()
    {
        this.context = "document";
        this.level = 0;
    }
    
    // Header attributes
    int level;
}

