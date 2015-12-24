package haxe;

import Socket.Error;

typedef OptionAvailable = {isServerAvailable:Bool, isOptionAvailable:Bool};

@:enum abstract MessageSeverity(Int) {
    var Info = 0;
    var Warning = 1;
    var Error = 2;
}

typedef Message = {stdout:Array<String>, stderr:Array<String>, infos:Array<Info>, severity:MessageSeverity};

class RangeInfo {
    public var isLineRange:Bool;
    public var start:Int;
    public var end:Int;
    public function new(s:Int, ?e:Int=-1, ?isLineRange=false) {
        if (e==-1) e=s;
        if (s > e) {
            start=e;
            end=s;
        } else {
            start = s;
            end = e;
        }
        if (!isLineRange && start==end) end++;
        this.isLineRange = isLineRange;
    }
}

class Info {
    static var reWin = ~/^\w+:\\/;
    static var re1 = ~/^((\w+:\\)?([^:]+)):(\d+):\s*([^:]+):(.+)/;
    static var re2 = ~/^((character[s]?)|(line[s]?))\s+(\d+)(\-(\d+))?/;

    public var fileName(default, null):String;
    public var lineNumber:Int;
    public var range:RangeInfo;
    public var message:String;
    public function new(fileName:String, lineNumber:Int, range:RangeInfo, message:String) {
        this.fileName = fileName;
        this.lineNumber = lineNumber;
        this.range = range;
        this.message = message;
    }
    public static function decode(str:String, ?cwd:String="") {
        if (!re1.match(str)) return null;
        if (!re2.match(re1.matched(5))) return null;
        var rs = Std.parseInt(re2.matched(4));
        var re = {
            var tmp = re2.matched(6);
            if (tmp!=null) Std.parseInt(tmp);
            else rs;
        }
        if (re==null) re = rs;
        var isLine = re2.matched(3) != null;
        var fn = re1.matched(1);
        var wd = re1.matched(2);
        if (wd != null) {
            fn = fn.split("/").join("\\");
        } else {
            var ps = "/";
            var dps = "\\";
            if (reWin.match(cwd)) {
                ps = "\\";
                dps = "/";
            }
            if (cwd.charAt(cwd.length-1) != ps) cwd += ps;
            switch(fn.charAt(0)) {
                case "/": {};
                case "\\": {};
                default: fn = cwd + fn;
            }
            fn = fn.split(dps).join(ps);
        }
        var ln = Std.parseInt(re1.matched(4));
        return {info:new Info(fn, ln, new RangeInfo(rs, re, isLine), re1.matched(6)), winDrive:wd};
    }
}

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
        var workingDir = cmdLine.workingDir;
        
        var s = new Socket();
        
        s.connect(host, port, _onConnect, null, null,
            function (s) {
                clear();
                
                if (onClose != null) {
                    var stdout = [];
                    var stderr = [];
                    var infos = [];

                    var hasError = false;
                    var nl = "\n";
    
                    for (line in s.datas.join("").split(nl)) {
                        switch (line.charCodeAt(0)) {
                            case 0x01: stdout.push(line.substr(1).split("\x01").join(nl));
                            case 0x02: hasError = true;
                            default:
                                stderr.push(line);
                                var info = haxe.Info.decode(line, workingDir);
                                if (info != null) infos.push(info.info);
                        }
                    }
                    var severity = hasError?MessageSeverity.Error:MessageSeverity.Warning;
                    onClose(s, {stdout:stdout, stderr:stderr, infos:infos, severity:severity}, s.error);
                }
            }
        );
 
        return s;
    }
    function _onConnect(s:Socket) {
        trace(cmdLine.get_cmds());
        s.write(cmdLine.get_cmds());
        
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
                else isPatchAvailable = message.severity!=MessageSeverity.Error;
                onData({isServerAvailable:isServerAvailable, isOptionAvailable:isPatchAvailable});
            }
        );
    }
}