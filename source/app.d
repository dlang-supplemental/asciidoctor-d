import std.stdio;
import std.file;
import std.path;
import std.string;
import std.getopt;
import std.conv : to;
import std.uni : toLower;
import asciidoctor;
import asciidoctor.serve;
import asciidoctor.watch;
import core.time : msecs;

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

void printConvertHelp()
{
    writeln(`Usage: asciidoctor-d [options] input_file`);
    writeln(`       asciidoctor-d serve [--stdio|--http HOST:PORT]`);
    writeln(`       asciidoctor-d watch [--interval MS] file.adoc [more...]`);
    writeln();
    writeln(`Hot reload IPC: docs/HOT-RELOAD.adoc (protocol v1, antora-solidstart orchestrator).`);
}

int runConvert(string[] args)
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

    if (help)
    {
        printConvertHelp();
        defaultGetoptPrinter("Convert options:", opts.options);
        return 0;
    }

    if (args.length < 2)
    {
        printConvertHelp();
        return 1;
    }

    auto inputFile = args[1];
    if (!inputFile.exists)
    {
        stderr.writeln("Error: Input file '", inputFile, "' does not exist.");
        return 1;
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

    if (backend.toLower == "pdf")
        std.file.write(outputFilename, cast(void[]) result);
    else
        std.file.write(outputFilename, result);
    writeln("Converted ", inputFile, " to ", outputFilename);
    return 0;
}

int runServe(string[] args)
{
    string httpBind;
    bool help;

    auto opts = getopt(
        args,
        "http", "Listen for HTTP POST /v1/convert (HOST:PORT); default stdio NDJSON", &httpBind,
        "help|h", "Show help", &help
    );

    if (help)
    {
        writeln("Usage: asciidoctor-d serve [--http HOST:PORT]");
        writeln("  Default: NDJSON requests on stdin, responses on stdout.");
        return 0;
    }

    if (httpBind.length)
    {
        auto colon = httpBind.indexOf(":");
        if (colon < 0)
        {
            stderr.writeln("Invalid --http; use HOST:PORT");
            return 1;
        }
        auto host = httpBind[0 .. colon];
        ushort port = cast(ushort) to!uint(httpBind[colon + 1 .. $]);
        return runServeHttp(host, port);
    }

    return runServeStdio();
}

int runWatchCmd(string[] args)
{
    uint intervalMs = 500;
    bool standalone = false;
    bool insecure = false;
    bool help;

    string[] files;
    auto opts = getopt(
        args,
        "interval|i", "Poll interval in milliseconds", &intervalMs,
        "standalone", "Emit full HTML documents (default: fragment)", &standalone,
        "insecure", "Allow raw HTML passthrough in output", &insecure,
        "help|h", "Show help", &help
    );

    if (help)
    {
        writeln("Usage: asciidoctor-d watch [options] file.adoc [more...]");
        return 0;
    }

    files = args[2 .. $];
    if (!files.length)
    {
        stderr.writeln("watch: provide at least one .adoc path");
        return 1;
    }

    return runWatch(files, msecs(intervalMs), standalone, !insecure);
}

version (unittest)
{
    void main()
    {
    }
}
else
{
    int main(string[] args)
    {
        if (args.length >= 2)
        {
            switch (args[1])
            {
            case "serve":
                return runServe(args);
            case "watch":
                return runWatchCmd(args);
            case "convert":
                return runConvert(["asciidoctor-d"] ~ args[2 .. $]);
            case "-h":
            case "--help":
                printConvertHelp();
                return 0;
            default:
                break;
            }
        }

        return runConvert(args);
    }
}
