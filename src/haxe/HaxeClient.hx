package haxe;

import Socket.Error;

@:enum abstract MessageSeverity(Int) {
    var Info = 0;
    var Warning = 1;
    var Error = 2;
}

typedef Message = {stdout:Array<String>, stderr:Array<String>, infos:Array<Info>, severity:MessageSeverity};

typedef Meta = {prefix:String, name:String, doc:String};
typedef Define = {name:String, doc:String};
typedef Option = {>Meta, param:String};

typedef Job = {run:Void->Void, id:String};

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
    static var re1 = ~/^((\w+:\\)?([^:]+)):(\d+):\s*([^:]+)(:(.+))?/;
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
        return {info:new Info(fn, ln, new RangeInfo(rs, re, isLine), re1.matched(7)), winDrive:wd};
    }
}

class HaxeClient {
    public var host:String;
    public var port:Int;
    public var cmdLine(default, null):HaxeCmdLine;
    public var isServerAvailable:Bool;
    public var isPatchAvailable:Bool;
    public var isHaxeServer:Bool;
    public var version:String;
    public var options:Array<Option>;
    public var optionsByName:Map<String, Option>;
    public var defines:Array<Define>;
    public var definesByName:Map<String, Define>;
    public var metas:Array<Meta>;

    var queue:Array<Job>;
    var working:Bool;
    
    public function new(host:String, port:Int) {
        this.host = host;
        this.port = port;
        cmdLine = new HaxeCmdLine();
        queue = [];
        working = false;
        resetInfos();
    }
    function resetInfos() {
        options = [];
        defines = [];
        metas = [];
        optionsByName = new Map<String, Option>();
        definesByName = new Map<String, Define>();
        isHaxeServer = false;
        isPatchAvailable = false;
        isServerAvailable = false;        
    }
    /*
    public function clone() {
        var tmp = new HaxeClient(host, port);
        return tmp.updateStatus(this);
    }
    public function udpateStatus(client:HaxeCLient) {
        isHaxeServer = client.isHaxeServer;
        isServerAvailable = client.isServerAvailable;
        isPatchAvailable = client.isPatchAvailable;
        return this;
    }
    */
    public function clear() {
        cmdLine.clear();
    }
    public function sendAll(onClose:Null<Socket->Message->Null<Error>->Void>, ?restoreCmdLine=false, ?id:String=null) {
        var cmds = cmdLine.get_cmds();
        cmdLine.clearPatch();
        var workingDir = cmdLine.workingDir;
        
        if (restoreCmdLine) cmdLine.restore();
        
        function run() {
            working = true;
    
            var s = new Socket();
            s.connect(host, port,
                function(s) {
                    s.write(cmds);
                    s.write("\x00");
                }, 
                null, null,
                function (s) {
                    working = false;
                    isServerAvailable = (s.error == null);

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
                    runQueue();
                }
            );
        }
        var job = {run:run, id:id};
        queue.push(job);
        if (!working) runQueue();
    }
    function runQueue() {
        if (queue.length==0) return;
        var job:Job=queue.shift();
        var id = job.id;
        if (id!=null) {
            var oq = queue;
            queue = [];
            while(oq.length > 0) {
                var nj = oq.shift();
                if (nj.id==id) job = nj;
                else queue.push(nj);               
            }
        }
        if (job != null) {
            //trace('running ${id} ${Date.now()}');
            job.run();
        }
    }
    public static function isOptionExists(optionName:String, data:String) {
        var re = new EReg("unknown option '"+optionName+"'", "");
 
        return !re.match(data);
    }
    static var reVersion = ~/^Haxe\s+(.+?)(\d+).(\d+).(\d+)(.+)?/;
#if js
    static var reCheckOption = ~/^\s*(-(-)?)(.+?) : ([\s\S]+)/;
    static var reCheckDefine = ~/^\s*([^\s]+)\s+: ([\s\S]+)/;
    static var reCheckMeta = ~/^\s*(@:)([^\s]+)\s+: ([\s\S]+)/;
#else
    static var reCheckOption = ~/^\s*(-(-)?)(.+?) : (.+)/s;
    static var reCheckDefine = ~/^\s*([^\s]+)\s+: (.+)/s;
    static var reCheckMeta = ~/^\s*(@:)([^\s]+)\s+: (.+)/s;
#end
    static var reCheckOptionName = ~/([^\s]+)(\s+(.+))?/;
    public function setStatus(message:Message, error:Null<Error>) {
        isServerAvailable = (error == null);
        isPatchAvailable = false;
        isHaxeServer = false;
        if (isServerAvailable) {
            isPatchAvailable = message.severity!=MessageSeverity.Error;
            if (message.stderr.length>0)
                isHaxeServer = reVersion.match(message.stderr[0]);
        }
        return this;
    }
    inline function unformatDoc(s:String) return s;
    public function infos(onData:Null<HaxeClient->Void>) {
        resetInfos();

        var step = 0;
        function next() {
            cmdLine.save();
            switch(step) {
                case 0:
                    cmdLine.help();
                case 1:
                    cmdLine.helpDefines();
                case 2:
                    cmdLine.helpMetas();
            }
            sendAll(
                function(s, message, error) {
                    var abort = true;
                    isServerAvailable = (error == null);
                    if (isServerAvailable) {
                        switch(step) {
                            case 0:
                                var datas = message.stderr;
                                if (datas.length > 0) {
                                    version = datas.shift();
                                    isHaxeServer = reVersion.match(version);
                                    abort = !isHaxeServer;
                                    if (isHaxeServer) {
                                        for (data in datas) {
                                            if (reCheckOption.match(data)) {
                                                if (reCheckOptionName.match(reCheckOption.matched(3))) {
                                                    var name = reCheckOptionName.matched(1);
                                                    isPatchAvailable = isPatchAvailable || (name=="patch");
                                                    var option = {prefix:reCheckOption.matched(1), name:name, doc:unformatDoc(reCheckOption.matched(4)), param:reCheckOptionName.matched(3)};
                                                    options.push(option);
                                                    optionsByName.set(name, option);
                                                }
                                            }
                                        }
                                    }
                                }
                            case 1:
                                var datas = message.stdout;
                                abort = (datas.length <= 0);
                                for (data in datas) {
                                    if (reCheckDefine.match(data)) {
                                        var define = {name:reCheckDefine.matched(1), doc:unformatDoc(reCheckDefine.matched(2))};
                                        defines.push(define);
                                        definesByName.set(define.name, define);
                                    }
                                }
                            case 2:
                                var datas = message.stdout;
                                abort = (datas.length <= 0);
                                for (data in datas) {
                                    if (reCheckMeta.match(data)) {
                                        metas.push({prefix:reCheckMeta.matched(1), name:reCheckMeta.matched(2), doc:unformatDoc(reCheckMeta.matched(3))});
                                    }
                                }
                        }
                    }
                    if (abort) {
                        //trace(options);
                        //trace(defines);
                        //trace(metas);
                        if (onData!=null) onData(this);
                    } else {
                        step++;
                        next();
                    }
                },
                true
            );
        }
        next();
    }
    public function patchAvailable(onData:Null<HaxeClient->Void>) {
        cmdLine.save()
        .version()
        .beginPatch('~.hx')
        .remove()
        ;

        sendAll(
            function (s:Socket, message:Message, error:Null<Error>) {
                setStatus(message, error);
                if (onData!=null) onData(this);
            },
            true
        );
    }
}