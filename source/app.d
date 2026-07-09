import std.stdio;
import std.file;
import std.path;
import std.string;
import std.getopt;
import asciidoctor;

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
            "backend|b", "Output format (html5)", &backend,
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
            outputFilename = buildPath(dir, inputFile.baseName.setExtension(".html"));
        }

        std.file.write(outputFilename, result);
        writeln("Converted ", inputFile, " to ", outputFilename);
    }
}
