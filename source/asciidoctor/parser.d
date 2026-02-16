module asciidoctor.parser;

import asciidoctor.ast;
import std.algorithm;
import std.array;
import std.string;

class Parser
{
    private string source;
    private Document doc;

    this(string source)
    {
        this.source = source;
    }

    Document parse()
    {
        doc = new Document();
        // Just split lines for now
        foreach (line; source.splitLines())
        {
            // Simple parsing to title/content
        }
        return doc;
    }
}
