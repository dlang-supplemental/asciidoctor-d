module asciidoctor;

public import asciidoctor.parser;
public import asciidoctor.ast;
public import asciidoctor.converter;
public import asciidoctor.inline;
public import asciidoctor.util;
public import asciidoctor.semantictokens;
public import asciidoctor.manpage;
public import asciidoctor.pdf;

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
    ConvertOptions opts;
    opts.backend = backend;
    opts.baseDir = baseDir;
    return convert(source, opts);
}

/**
 * Convert AsciiDoc source with explicit options (fragment / secure HTML).
 *
 * Params:
 *   source = AsciiDoc text
 *   opts   = conversion options (`backend`, `baseDir`, `standalone`, `secure`)
 */
string convert(string source, ConvertOptions opts)
{
    auto parser = new Parser(source, opts.baseDir);
    auto document = parser.parse();
    auto converter = ConverterFactory.create(opts.backend, opts);
    return converter.convert(document);
}
