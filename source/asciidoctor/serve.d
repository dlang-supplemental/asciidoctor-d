module asciidoctor.serve;

import asciidoctor.ipc;
import std.algorithm : splitter, startsWith;
import std.range : empty, front;
import std.uni : toLower;
import std.conv : to;
import std.format : format;
import std.array : split;
import std.json : JSONType, JSONValue, parseJSON;
import std.socket : InternetAddress, Socket, TcpSocket;
import std.stdio;
import std.string : indexOf, strip;

/// Read NDJSON requests from stdin; write one JSON line per response.
int runServeStdio()
{
    foreach (line; stdin.byLine())
    {
        auto trimmed = line.strip;
        if (!trimmed.length)
            continue;
        auto response = handleIpcRequest(trimmed.idup);
        writeln(response);
        stdout.flush();
        try
        {
            auto root = parseJSON(response);
            if ("shutdown" in root && root["shutdown"].type == JSONType.true_)
                return 0;
        }
        catch (Exception)
        {
        }
    }
    return 0;
}

/// Minimal HTTP server for local orchestrators (antora-solidstart dev compiler).
int runServeHttp(string bindHost, ushort port)
{
    auto address = new InternetAddress(bindHost, port);
    auto listener = new TcpSocket();
    listener.bind(address);
    listener.listen(8);
    stderr.writeln(format("asciidoctor-d serve http://%s:%s/v1/convert (GET /v1/health)", bindHost, port));

    for (;;)
    {
        Socket client = listener.accept();
        scope (exit)
            client.close();
        try
            handleHttpClient(client);
        catch (Exception e)
            stderr.writeln("HTTP client error: ", e.msg);
    }
}

private void handleHttpClient(Socket client)
{
    ubyte[8192] buf;
    size_t total = 0;
    while (total < buf.length)
    {
        auto n = client.receive(buf[total .. $]);
        if (n <= 0)
            return;
        total += n;
        if (indexOf(cast(string) buf[0 .. total], "\r\n\r\n") >= 0)
            break;
    }

    auto headerBlock = cast(string) buf[0 .. total];
    auto headerEnd = headerBlock.indexOf("\r\n\r\n");
    if (headerEnd < 0)
        return;

    auto headers = headerBlock[0 .. headerEnd];
    string body;
    size_t contentLength;
    foreach (line; headers.splitter("\r\n"))
    {
        if (line.toLower.startsWith("content-length:"))
        {
            auto val = line[line.indexOf(":") + 1 .. $].strip;
            contentLength = to!size_t(val);
        }
    }

    body = headerBlock[headerEnd + 4 .. $];
    while (body.length < contentLength && total < buf.length)
    {
        auto n = client.receive(buf[total .. $]);
        if (n <= 0)
            break;
        total += n;
        body = cast(string) buf[0 .. total];
        body = body[headerEnd + 4 .. $];
    }
    if (contentLength && body.length > contentLength)
        body = body[0 .. contentLength];

    string requestLine = headers.splitter("\r\n").empty ? "" : headers.splitter("\r\n").front;
    auto parts = requestLine.split(" ");
    if (parts.length < 2)
        return;

    auto method = parts[0];
    auto target = parts[1];

    string jsonBody;
    int status = 200;
    string statusText = "OK";
    if (method == "GET" && target == "/v1/health")
    {
        JSONValue health = JSONValue.emptyObject;
        health["ok"] = JSONValue(true);
        health["version"] = JSONValue(ipcProtocolVersion);
        health["engine"] = JSONValue("asciidoctor-d");
        jsonBody = health.toString;
    }
    else if (method == "POST" && target == "/v1/convert")
    {
        jsonBody = handleIpcRequest(body);
        try
        {
            auto root = parseJSON(jsonBody);
            if ("ok" in root && root["ok"].type == JSONType.false_)
            {
                status = 400;
                statusText = "Bad Request";
            }
        }
        catch (Exception)
        {
            status = 500;
            statusText = "Internal Server Error";
        }
    }
    else
    {
        status = 404;
        statusText = "Not Found";
        jsonBody = `{"ok":false,"error":{"code":"not_found","message":"Use GET /v1/health or POST /v1/convert"}}`;
    }

    auto response = format(
        "HTTP/1.1 %s %s\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: %s\r\nConnection: close\r\n\r\n%s",
        status,
        statusText,
        jsonBody.length,
        jsonBody,
    );
    client.send(response);
}
