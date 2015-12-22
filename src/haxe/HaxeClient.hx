package haxe;

import Socket.Error;

typedef OptionAvailable = {isServerAvailable:Bool, isOptionAvailable:Bool};

typedef Message = {stdout:Array<String>, stderr:Array<String>, hasError:Bool};

class HaxeClient {
    public var host:String;
    public var port:Int;
    public var cmdLine(default, null):HaxeCmdLine;
 
    public function new(host:String, port:Int) {
        this.host = host;
        this.port = port;
        cmdLine = new HaxeCmdLine();
        clear();
    }
    public function clear() {
        cmdLine.clear();
    }
    public function sendAll(onClose:Null<Socket->Message->Null<Error>->Void>) {
        cmdLine.endPatch();
        
        var s = new Socket();
        
        s.connect(host, port, _onConnect, null, null,
            function (s) {
                clear();

                var stdout = [];
                var stderr = [];
                var hasError = false;
                var nl = "\n";
 
                for (line in s.datas.join("").split(nl)) {
                    switch (line.charCodeAt(0)) {
                        case 0x01: stdout.push(line.substr(1).split("\x01").join(nl));
                        case 0x02: hasError = true;
                        default: stderr.push(line);
                    }
                }
                if (onClose != null) onClose(s, {stdout:stdout, stderr:stderr, hasError:hasError}, s.error);
            }
        );
 
        return s;
    }
    function _onConnect(s:Socket) {
        for (cmd in cmdLine.cmds) {
            s.write(cmd);
        }
 
        s.write("\x00");
    }
    public static function isOptionExists(optionName:String, data:String) {
        var re = new EReg("unknown option '"+optionName+"'", "");
 
        return !re.match(data);
    }
    public function isPatchAvailable(onData:OptionAvailable->Void) {
        cmdLine.save();
        
        cmdLine
            .beginPatch('~.hx')
            .remove();

        sendAll(
            function (s:Socket, message:Message, error:Null<Error>) {
                cmdLine.restore();
                var isServerAvailable = true;
                var isPatchAvailable = false;
                if (error != null) isServerAvailable = false;
                else isPatchAvailable = !message.hasError;
                onData({isServerAvailable:isServerAvailable, isOptionAvailable:isPatchAvailable});
            }
        );
    }
}