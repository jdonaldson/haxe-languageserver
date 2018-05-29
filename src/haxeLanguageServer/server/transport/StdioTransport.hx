package haxeLanguageServer.server.transport;

import js.node.stream.Readable.ReadableEvent;
import js.node.stream.Readable.IReadable;
import js.node.stream.Writable.IWritable;
import js.node.Buffer;

class StdioTransport implements Transport {
    static final stdinSepBuf = new Buffer([1]);

    var stdin:IWritable;
    var responseHandler:String->Void;
    var buffer:MessageBuffer;
    var nextMessageLength:Int;

    public function new(stdin:IWritable, stderr:IReadable, responseHandler:String->Void) {
        buffer = new MessageBuffer();
        nextMessageLength = -1;
        this.stdin = stdin;
        this.responseHandler = responseHandler;
        stderr.on(ReadableEvent.Data, onData);
    }

    @:access(haxeLanguageServer.server.DisplayRequest)
    public function sendRequest(request:DisplayRequest) {
        var args = request.args.copy();
        if (request.stdin != null) {
            args.push("-D");
            args.push("display-stdin");
        }

        var lenBuf = new Buffer(4);
        var chunks = [lenBuf];
        var length = 0;
        for (arg in args) {
            var buf = new Buffer(arg + "\n");
            chunks.push(buf);
            length += buf.length;
        }

        if (request.stdin != null) {
            chunks.push(stdinSepBuf);
            var buf = new Buffer(request.stdin);
            chunks.push(buf);
            length += buf.length + stdinSepBuf.length;
        }

        lenBuf.writeInt32LE(length, 0);

        stdin.write(Buffer.concat(chunks, length + 4));
    }

    function onData(data:Buffer) {
        buffer.append(data);
        while (true) {
            if (nextMessageLength == -1) {
                var length = buffer.tryReadLength();
                if (length == -1)
                    return;
                nextMessageLength = length;
            }
            var msg = buffer.tryReadContent(nextMessageLength);
            if (msg == null)
                return;
            nextMessageLength = -1;
            responseHandler(msg);
        }
    }
}

class MessageBuffer {
    static inline var DEFAULT_SIZE = 8192;

    var index:Int;
    var buffer:Buffer;

    public function new() {
        index = 0;
        buffer = new Buffer(DEFAULT_SIZE);
    }

    public function append(chunk:Buffer):Void {
        if (buffer.length - index >= chunk.length) {
            chunk.copy(buffer, index, 0, chunk.length);
        } else {
            var newSize = (Math.ceil((index + chunk.length) / DEFAULT_SIZE) + 1) * DEFAULT_SIZE;
            if (index == 0) {
                buffer = new Buffer(newSize);
                chunk.copy(buffer, 0, 0, chunk.length);
            } else {
                buffer = Buffer.concat([buffer.slice(0, index), chunk], newSize);
            }
        }
        index += chunk.length;
    }

    public function tryReadLength():Int {
        if (index < 4)
            return -1;
        var length = buffer.readInt32LE(0);
        buffer = buffer.slice(4);
        index -= 4;
        return length;
    }

    public function tryReadContent(length:Int):String {
        if (index < length)
            return null;
        var result = buffer.toString("utf-8", 0, length);
        var nextStart = length;
        buffer.copy(buffer, 0, nextStart);
        index -= nextStart;
        return result;
    }

    public function getContent():String {
        return buffer.toString("utf-8", 0, index);
    }
}
