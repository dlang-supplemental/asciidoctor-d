module asciidoctor;

public import asciidoctor.parser;
public import asciidoctor.ast;
public import asciidoctor.converter;

/**
 * Main entry point for converting AsciiDoc source.
 */
module Convert
{
    import std.stdio;

    string convert(string source, string backend = "html5")
    {
        auto parser = new Parser(source);
        auto document = parser.parse();
        auto converter = ConverterFactory.create(backend);
        return converter.convert(document);
    }
}
