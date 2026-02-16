module asciidoctor.parser;

import asciidoctor.ast;
import std.algorithm;
import std.array;
import std.string;

class Parser
{
    private string[] lines;
    private int currentLine;
    private Document doc;

    this(string source)
    {
        this.lines = source.splitLines();
        this.currentLine = 0;
    }

    Document parse()
    {
        doc = new Document();
        
        while (hasMoreLines())
        {
            string line = peekLine();
            
            if (line.strip().empty)
            {
                advanceLine();
                continue;
            }
            
            if (line.startsWith("="))
            {
                processHeader(line);
            }
            else
            {
                processParagraph();
            }
        }
        return doc;
    }

    private bool hasMoreLines()
    {
        return currentLine < lines.length;
    }

    private string peekLine()
    {
        if (!hasMoreLines()) return null;
        return lines[currentLine];
    }

    private string advanceLine()
    {
        if (!hasMoreLines()) return null;
        return lines[currentLine++];
    }

    private void processHeader(string line)
    {
        import std.conv : to;
        
        int level = 0;
        while (level < line.length && line[level] == '=')
        {
            level++;
        }
        
        string title = line[level..$].strip();
        
        if (level == 1 && doc.doctitle.empty)
        {
            doc.doctitle = title;
        }
        else
        {
            auto section = new Section(level - 1); // Document is level 0, so = is level 0 if doctitle, or level 1 section? 
            // AsciiDoc spec: = Title is Level 0 (Document Title). == Section Level 1.
            // Adjusting logic:
            // If = Title is found and it's the first thing, it's Document Title.
            // If found later, it might be invalid or part II.
            // Let's assume standard structure for now.
             
            section.title = title;
            doc.blocks ~= section;
        }
        advanceLine();
    }
    
    private void processParagraph()
    {
        auto block = new Block();
        block.context = "paragraph";
        
        while (hasMoreLines())
        {
            string line = peekLine();
            if (line.strip().empty || line.startsWith("="))
            {
                break;
            }
            block.lines ~= advanceLine();
        }
        
        doc.blocks ~= block;
    }
}
