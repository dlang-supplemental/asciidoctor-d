import std.stdio;
import std.file;
import std.path;
import std.string;
import std.getopt;
import asciidoctor;

void main(string[] args)
{
    string backend = "html5";
    string destination;
    string inputFile;
    bool help;

    auto opts = getopt(
        args,
        "backend|b", "Output format (e.g. html5, pdf)", &backend,
        "destination|D", "Output directory", &destination,
        "help|h", "Show this help", &help
    );

    if (help || args.length < 2)
    {
        defaultGetoptPrinter("Usage: asciidoctor-d [options] input_file", opts.options);
        return;
    }

    inputFile = args[1];

    if (!inputFile.exists)
    {
        stderr.writeln("Error: Input file '" ~ inputFile ~ "' does not exist.");
        return;
    }

    string content = readText(inputFile);
    string result = convert(content, backend);

    if (destination.empty)
    {
        destination = inputFile.dirName;
    }
    string outputFilename = buildPath(destination, inputFile.baseName.setExtension(".html"));
    
    // For now assuming html5 produces .html and others produce appropriately.
    // The backend should dictate the extension ideally.

    std.file.write(outputFilename, result);
    writeln("Converted " ~ inputFile ~ " to " ~ outputFilename);
}
