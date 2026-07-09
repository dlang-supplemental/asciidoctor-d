import std.stdio;
import std.file;
import std.path;
import std.string;
import std.getopt;
import std.uni : toLower;
import asciidoctor;

string defaultExtension(string backend)
{
    switch (backend.toLower)
    {
    case "manpage":
        return ".1";
    case "pdf":
        return ".pdf";
    default:
        return ".html";
    }
}

version (unittest)
{
    void main()
    {
        // Unit tests run before main; nothing else required.
    }
}
else
{
    void main(string[] args)
    {
        string backend = "html5";
        string destination;
        string outFile;
        bool help;

        auto opts = getopt(
            args,
            "backend|b", "Output format (html5, manpage, pdf)", &backend,
            "destination-dir|D", "Output directory", &destination,
            "out-file|o", "Output file path", &outFile,
            "help|h", "Show this help", &help
        );

        if (help || args.length < 2)
        {
            defaultGetoptPrinter("Usage: asciidoctor-d [options] input_file", opts.options);
            return;
        }

        auto inputFile = args[1];
        if (!inputFile.exists)
        {
            stderr.writeln("Error: Input file '", inputFile, "' does not exist.");
            return;
        }

        auto content = readText(inputFile);
        auto baseDir = inputFile.absolutePath.dirName;
        auto result = convert(content, backend, baseDir);

        string outputFilename;
        if (outFile.length)
            outputFilename = outFile;
        else
        {
            auto dir = destination.length ? destination : inputFile.dirName;
            outputFilename = buildPath(dir, inputFile.baseName.setExtension(defaultExtension(backend)));
        }

        // PDF is binary; write as ubyte to avoid text encoding surprises on Windows.
        if (backend.toLower == "pdf")
            std.file.write(outputFilename, cast(void[]) result);
        else
            std.file.write(outputFilename, result);
        writeln("Converted ", inputFile, " to ", outputFilename);
    }
}
