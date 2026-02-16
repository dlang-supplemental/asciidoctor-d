module asciidoctor.converter;

import asciidoctor.ast;
import std.format;

interface Converter
{
    string convert(Document node);
}

class ConverterFactory
{
    static Converter create(string backend)
    {
        import std.algorithm;
        import std.uni;

        switch (backend.toLower())
        {
            case "html5":
                return new Html5Converter();
            // case "pdf":
            //     return new PdfConverter();
            default:
                throw new Exception("Unknown backend: " ~ backend);
        }
    }
}

class Html5Converter : Converter
{
    import std.range;
    
    override string convert(Document node)
    {
        import std.array : appender;
        auto app = appender!string;
        
        app.put("<!DOCTYPE html>");
        app.put("<html lang=\"en\">");
        app.put("<head>");
        app.put("<meta charset=\"UTF-8\">");
        if (!node.doctitle.empty)
        {
            app.put("<title>" ~ node.doctitle ~ "</title>");
        }
        app.put("</head>");
        app.put("<body>");
        
        if (!node.doctitle.empty)
        {
            app.put("<h1>" ~ node.doctitle ~ "</h1>");
        }
        
        foreach (block; node.blocks)
        {
            app.put(convertBlock(cast(Block)block));
        }
        
        app.put("</body>");
        app.put("</html>");
        
        return app.data;
    }
    
    private string convertBlock(Block block)
    {
        if (auto section = cast(Section)block)
        {
            return convertSection(section);
        }

        switch (block.context)
        {
            case "paragraph":
                return "<div class=\"paragraph\"><p>" ~ block.content ~ "</p></div>";
            case "document": 
                 return "";
            default:
                import std.stdio;
                stderr.writeln("Warning: Unknown conversion for block context: ", block.context);
                return "";
        }
    }
    
    private string convertSection(Section section)
    {
        import std.conv : to;
        import std.array : appender;
        auto app = appender!string;
        
        string tag = "h" ~ (section.level + 1).to!string;
        
        app.put("<div class=\"sect" ~ section.level.to!string ~ "\">");
        app.put("<" ~ tag ~ ">" ~ section.title ~ "</" ~ tag ~ ">");
        app.put("<div class=\"sectionbody\">");
        
        foreach (child; section.blocks)
        {
            app.put(convertBlock(cast(Block)child));
        }
        
        app.put("</div>");
        app.put("</div>");
        
        return app.data;
    }
}
