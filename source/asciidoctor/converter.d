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
    override string convert(Document node)
    {
        return "<html><head><title>" ~ node.doctitle ~ "</title></head><body>" ~ node.content ~ "</body></html>";
    }
}
