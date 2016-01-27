package haxe;

import Socket.Error;

@:enum abstract MessageSeverity(Int) {
    var Info = 0;
    var Warning = 1;
    var Error = 2;
    var Cancel = 3;
}

typedef Message = {stdout:Array<String>, stderr:Array<String>, infos:Array<Info>, severity:MessageSeverity, socket:Socket, error:Error};

typedef WithName = {name:String};
typedef WithNameDoc = {>WithName, doc:String};
typedef Keyword = WithName;
typedef Klass = WithName;
typedef Define = WithNameDoc;
typedef Meta = {>WithNameDoc, prefix:String};
typedef Option = {>Meta, param:String};

typedef CancelToken = {isCancellationRequested:Bool, onCancellationRequested:Null<(Dynamic->Void)->Void>}
typedef Job = {run:Job->Void, id:String, group:Int, priority:Int, cancelToken:CancelToken, cancel:Bool};

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
    public var keywords:Array<Keyword>;

    var queue:Array<Job>;
    var working:Bool;

    static var jobId:Int = 0;

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
        keywords = [];
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
    function clear() {
        cmdLine.clear();
    }
    var sourceContext:{fileName:String, line:Int, column:Int};
    public function setContext(ctx) {
        sourceContext = ctx;
        return this;
    }
    var cancelToken:CancelToken;
    public function setCancelToken(ct:CancelToken) {
        cancelToken = ct;
        return this;
    }

    var currentJob:Job = null;

    public function sendAll(onClose:Message->Void, ?restoreCmdLine=false, ?id:String=null, ?priority=0, ?clearCmdAfterExec = true) {
        var ctx = sourceContext;
        var ct = cancelToken;

        sourceContext = null;
        cancelToken = null;

        var cmds = cmdLine.toString();

        inline function restore() {
            if (restoreCmdLine) cmdLine.restore();
            restoreCmdLine = false;
        }

        inline function closeWithCancel() {
            restore();
            if (onClose != null) onClose({stdout:null, stderr:null, infos:null, socket:null, error:null, severity:MessageSeverity.Cancel});
            onClose = null;
            working = false;
            currentJob = null;
        }

        if (cmds=="") {
            closeWithCancel();
            runQueue();
            return null;
        }

        cmdLine.clearPatch();
        var workingDir = cmdLine.workingDir;

        restore();

        function run(job:Job) {
            currentJob = job;

            var s:Socket = null;
            inline function cancel() {
                if (s !=null ) s.close();
                closeWithCancel();
            }
            var ct = job.cancelToken;

            inline function isCancelled() return (job.cancel || (ct != null && ct.isCancellationRequested));

            if (isCancelled()) {
                cancel();
                runQueue();
                return;
            }

            working = true;

            s = new Socket();
            s.connect(host, port,
                function(s) {
                    if (isCancelled()) {
                        cancel();
                        runQueue();
                        return;
                    }
                    s.write(cmds);
                    s.write("\x00");
                },
                function(s, d) {
                    if (isCancelled()) {
                        cancel();
                        runQueue();
                        return;
                    }
                },
                null,
                function (s) {
                    working = false;
                    isServerAvailable = (s.error == null);
                    if (clearCmdAfterExec) clear();

                    if (isCancelled()) {
                        cancel();
                        runQueue();
                        return;
                    }

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
                                    if ((info == null) && (ctx != null) && (line != "")) {
                                        var msg = [ctx.fileName, Std.string(ctx.line),' character ${ctx.column} ', line].join(":");
                                        info = haxe.Info.decode(msg, workingDir);
                                    }
                                    if (info != null) infos.push(info.info);
                            }
                        }
                        var severity = hasError?MessageSeverity.Error:MessageSeverity.Warning;
                        onClose({stdout:stdout, stderr:stderr, infos:infos, severity:severity, socket:s, error:s.error});
                    }
                    runQueue();
                }
            );
        }

        if (id=="") id = null;

        var group = 0;

        if (id != null) {
            var tmp = id.split("@");
            id = tmp[0];
            if (id == "") id = null;
            if (tmp.length > 1) group = Std.parseInt(tmp[1]);
        }

        jobId++;

        var sId = "-" + Std.string(jobId);
        if (id == null) id = sId;
        else id += sId;

        var job:Job = {run:run, id:id, group:group, priority:priority, cancelToken:ct, cancel:false};

        if (queue.length == 0) queue.push(job);
        else {
            var oq = queue;
            queue = [];
            if (group != 0 && currentJob != null && group >= currentJob.group) {
                currentJob.cancel = true;
            }
            var jobPushed = false;
            while (oq.length > 0) {
                var j = oq.shift();
                if (j.priority < priority) {
                    jobPushed = true;
                    queue.push(job);
                    queue.push(j);
                    break;
                } else {
                    queue.push(j);
                }
            }
            queue = queue.concat(oq);
            if (!jobPushed) queue.push(job);
        }
        if (!working) runQueue();
        return job;
    }

    function runQueue() {
        if (queue.length==0) return;
        var job = queue.shift();
        var group = job.group;
        if (group != 0) {
            var oq = queue;
            queue = [];
            while(oq.length > 0) {
                var nj = oq.shift();
                if (nj.group >= group) {
                    if (nj.priority != job.priority) {
                        nj.cancel = true;
                        nj.run(nj);
                    } else {
                        job.cancel = true;
                        job.run(job);
                        job = nj;
                    }
                }
                else queue.push(nj);
            }
        }
        if (job != null) {
            job.run(job);
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

    static var reKeywords = ~/n=\\"([^\\]+?)\\"/g;

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
                case 3:
                    cmdLine.keywords();
            }
            sendAll(
                function(message) {
                    var s = message.socket;
                    var error = message.error;
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
                           case 3:
                                var datas = message.stderr;
                                abort = (datas.length <= 0);
                                if (!abort) {
                                    reKeywords.map(datas[0], function(r) {
                                        var match = r.matched(1);
                                        keywords.push({name:match});
                                        return match;
                                    });
                                }
                        }
                    }
                    if (abort) {
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
}