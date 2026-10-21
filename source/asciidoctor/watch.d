module asciidoctor.watch;

import asciidoctor.ipc : fileModifiedUnix, handleIpcRequest, ipcProtocolVersion;
import std.file : exists;
import std.format : format;
import std.json : JSONValue, parseJSON;
import std.path : absolutePath;
import std.stdio;
import core.thread : Thread;
import core.time : dur, Duration, msecs;

struct WatchedFile
{
    string path;
    long lastMtime;
}

/// Poll `paths` and emit NDJSON convert events on change (full document, fragment HTML).
int runWatch(string[] paths, Duration interval, bool standalone, bool secure)
{
    WatchedFile[] watched;
    foreach (p; paths)
    {
        if (!p.exists)
        {
            stderr.writeln("watch: skipping missing file ", p);
            continue;
        }
        WatchedFile w;
        w.path = p.absolutePath;
        w.lastMtime = fileModifiedUnix(w.path);
        watched ~= w;
    }

    if (!watched.length)
    {
        stderr.writeln("watch: no files to watch");
        return 1;
    }

    stderr.writeln(format("watch: polling %s file(s) every %sms", watched.length, interval.total!"msecs"));

    for (;;)
    {
        foreach (ref w; watched)
        {
            if (!w.path.exists)
                continue;
            auto mtime = fileModifiedUnix(w.path);
            if (mtime == w.lastMtime)
                continue;
            w.lastMtime = mtime;

            JSONValue req = JSONValue.emptyObject;
            req["version"] = JSONValue(ipcProtocolVersion);
            req["id"] = JSONValue(format("watch-%s", mtime));
            req["op"] = JSONValue("convert");
            JSONValue params = JSONValue.emptyObject;
            params["path"] = JSONValue(w.path);
            params["standalone"] = JSONValue(standalone);
            params["secure"] = JSONValue(secure);
            req["params"] = params;

            auto response = handleIpcRequest(req.toString);
            JSONValue envelope = JSONValue.emptyObject;
            envelope["version"] = JSONValue(ipcProtocolVersion);
            envelope["event"] = JSONValue("converted");
            envelope["path"] = JSONValue(w.path);
            envelope["response"] = parseJSON(response);
            writeln(envelope.toString);
            stdout.flush();
        }
        Thread.sleep(interval);
    }
}
