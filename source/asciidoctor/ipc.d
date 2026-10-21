module asciidoctor.ipc;

import asciidoctor;
import std.algorithm : startsWith;
import std.conv : to;
import std.file : exists, getTimes, readText;
import std.format : format;
import std.datetime.systime : SysTime;
import std.json : JSONType, JSONValue, parseJSON;
import std.path : absolutePath, dirName;
import std.string : strip;

/// Wire format version (`docs/HOT-RELOAD.adoc`).
enum ipcProtocolVersion = 1;

long fileModifiedUnix(string path)
{
    SysTime accessTime;
    SysTime modificationTime;
    getTimes(path, accessTime, modificationTime);
    return modificationTime.toUnixTime();
}

/// Process one NDJSON/HTTP JSON request; returns a JSON object string (single line).
string handleIpcRequest(string line)
{
    JSONValue root;
    try
        root = parseJSON(line);
    catch (Exception e)
        return errorResponse(null, "parse_error", e.msg);

    string id;
    if ("id" in root)
    {
        if (root["id"].type == JSONType.string)
            id = root["id"].str;
        else
            id = root["id"].toString;
    }

    if ("version" in root && root["version"].integer != ipcProtocolVersion)
    {
        return errorResponse(
            id,
            "unsupported_version",
            format("Expected protocol version %s", ipcProtocolVersion),
        );
    }

    if (!("op" in root) || root["op"].type != JSONType.string)
        return errorResponse(id, "invalid_request", "Missing or invalid op");

    auto op = root["op"].str;
    switch (op)
    {
    case "ping":
        return pingResponse(id);
    case "convert":
        return convertResponse(id, root);
    case "shutdown":
        return shutdownResponse(id);
    default:
        return errorResponse(id, "unknown_op", "Unknown op: " ~ op);
    }
}

private string pingResponse(string id)
{
    JSONValue res = JSONValue.emptyObject;
    res["version"] = JSONValue(ipcProtocolVersion);
    if (id.length)
        res["id"] = JSONValue(id);
    res["ok"] = JSONValue(true);
    res["engine"] = JSONValue("asciidoctor-d");
    return res.toString;
}

private string shutdownResponse(string id)
{
    JSONValue res = JSONValue.emptyObject;
    res["version"] = JSONValue(ipcProtocolVersion);
    if (id.length)
        res["id"] = JSONValue(id);
    res["ok"] = JSONValue(true);
    res["shutdown"] = JSONValue(true);
    return res.toString;
}

private string convertResponse(string id, JSONValue root)
{
    if (!("params" in root) || root["params"].type != JSONType.object)
        return errorResponse(id, "invalid_request", "convert requires params object");

    auto params = root["params"];
    string path = optString(params, "path");
    string source = optString(params, "source");
    string baseDir = optString(params, "baseDir");
    string backend = optString(params, "backend", "html5");

    bool standalone = optBool(params, "standalone", false);
    bool secure = optBool(params, "secure", true);

    int fromLine = optInt(params, "fromLine", -1);
    int toLine = optInt(params, "toLine", -1);
    string blockId = optString(params, "blockId");

    bool partialRequested = fromLine >= 0 || toLine >= 0 || blockId.length > 0;

    if (path.length && source.length)
        return errorResponse(id, "invalid_request", "Use path or source, not both");

    if (!path.length && !source.length)
        return errorResponse(id, "invalid_request", "convert requires path or source");

    try
    {
        if (path.length)
        {
            if (!path.exists)
                return errorResponse(id, "not_found", "File not found: " ~ path);
            source = readText(path);
            if (!baseDir.length)
                baseDir = path.absolutePath.dirName;
        }
        else if (!baseDir.length)
            baseDir = ".";

        ConvertOptions opts;
        opts.backend = backend;
        opts.baseDir = baseDir;
        opts.standalone = standalone;
        opts.secure = secure;

        auto html = convert(source, opts);

        JSONValue res = JSONValue.emptyObject;
        res["version"] = JSONValue(ipcProtocolVersion);
        if (id.length)
            res["id"] = JSONValue(id);
        res["ok"] = JSONValue(true);
        res["html"] = JSONValue(html);
        if (path.length)
        {
            res["path"] = JSONValue(path);
            res["mtime"] = JSONValue(fileModifiedUnix(path));
        }
        if (partialRequested)
        {
            JSONValue partial = JSONValue.emptyObject;
            partial["requested"] = JSONValue(true);
            partial["implemented"] = JSONValue(false);
            partial["message"] =
                JSONValue("Full-document convert only; block/line range is reserved for a future release.");
            if (fromLine >= 0)
                partial["fromLine"] = JSONValue(fromLine);
            if (toLine >= 0)
                partial["toLine"] = JSONValue(toLine);
            if (blockId.length)
                partial["blockId"] = JSONValue(blockId);
            res["partial"] = partial;
        }
        return res.toString;
    }
    catch (Exception e)
        return errorResponse(id, "convert_failed", e.msg);
}

private string errorResponse(string id, string code, string message)
{
    JSONValue res = JSONValue.emptyObject;
    res["version"] = JSONValue(ipcProtocolVersion);
    if (id.length)
        res["id"] = JSONValue(id);
    res["ok"] = JSONValue(false);
    JSONValue err = JSONValue.emptyObject;
    err["code"] = JSONValue(code);
    err["message"] = JSONValue(message);
    res["error"] = err;
    return res.toString;
}

private string optString(JSONValue obj, string key, string defaultVal = "")
{
    if (key !in obj || obj[key].type == JSONType.null_)
        return defaultVal;
    if (obj[key].type == JSONType.string)
        return obj[key].str;
    return obj[key].toString;
}

private bool optBool(JSONValue obj, string key, bool defaultVal)
{
    if (key !in obj)
        return defaultVal;
    if (obj[key].type == JSONType.true_)
        return true;
    if (obj[key].type == JSONType.false_)
        return false;
    return defaultVal;
}

private int optInt(JSONValue obj, string key, int defaultVal)
{
    if (key !in obj)
        return defaultVal;
    if (obj[key].type == JSONType.integer)
        return cast(int) obj[key].integer;
    if (obj[key].type == JSONType.string)
    {
        try
            return to!int(obj[key].str);
        catch (Exception)
            return defaultVal;
    }
    return defaultVal;
}

version (unittest)
{
    import std.algorithm : canFind;

    unittest
    {
        auto line = `{"version":1,"id":"a","op":"ping"}`;
        auto response = handleIpcRequest(line);
        assert(response.canFind(`"ok":true`));
        assert(response.canFind(`"engine":"asciidoctor-d"`));
    }

    unittest
    {
        auto line = `{"version":1,"id":2,"op":"convert","params":{"source":"= T\n\nHi.\n","standalone":false,"secure":true}}`;
        auto response = handleIpcRequest(line);
        assert(response.canFind(`"ok":true`));
        assert(response.canFind(`<h1>`));
        assert(!response.canFind(`<!DOCTYPE`));
    }

    unittest
    {
        auto line = `{"version":1,"op":"convert","params":{"source":"= T\n","fromLine":1,"toLine":5}}`;
        auto response = handleIpcRequest(line);
        assert(response.canFind(`"partial"`));
        assert(response.canFind(`"implemented":false`));
    }
}
