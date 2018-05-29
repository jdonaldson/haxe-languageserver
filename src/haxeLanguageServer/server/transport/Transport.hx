package haxeLanguageServer.server.transport;

interface Transport {
    function sendRequest(request:DisplayRequest):Void;
}
