module asciidoctor;

public import asciidoctor.parser;
public import asciidoctor.ast;
public import asciidoctor.converter;
public import asciidoctor.inline;
public import asciidoctor.util;
public import asciidoctor.semantictokens;

import std.path : dirName;

/**
 * Convert AsciiDoc source to the given backend (default html5).
 *
 * Params:
 *   source  = AsciiDoc text
 *   backend = output backend name
 *   baseDir = directory used to resolve include:: paths
 */
string convert(string source, string backend = "html5", string baseDir = ".")
{
    auto parser = new Parser(source, baseDir);
    auto document = parser.parse();
    auto converter = ConverterFactory.create(backend);
    return converter.convert(document);
}
