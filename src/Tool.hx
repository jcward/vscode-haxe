import haxe.Timer;
import Vscode;
import haxe.HaxeClient.MessageSeverity;
import haxe.HaxeClient.Info;
#if js
import js.node.Buffer;
import js.node.Fs;
import js.node.Path;
using Tool;
#end

class Tool {
    public static inline function displayAsInfo(s:String) Vscode.window.showInformationMessage(s);
    public static inline function displayAsError(s:String) Vscode.window.showErrorMessage(s);
    public static inline function displayAsWarning(s:String) Vscode.window.showWarningMessage(s);
    inline public static function getTime() return Date.now().getTime();
#if js
    public static function mkDirSync(path:String) {
        try {
            Fs.mkdirSync(path);
        } catch(e:Dynamic) {
            if ( e.code != 'EEXIST' ) throw e;
        }
    }
    public static function mkDirsSync(dirs:Array<String>) {
        var path = "";
        for (dir in dirs) {
            path = Path.join(path, dir);
            mkDirSync(path);
        }
    }
    public static function normalize(path:String) {
        path = Path.normalize(path);
        if (platform.Platform.instance.isWin) path = path.toLowerCase();
        return path;
    }
    public static inline function byteLength(str:String) return
    #if (haxe_ver >= 3.3)
        Buffer.byteLength(str);
    #else
        Buffer._byteLength(str);
    #end
    public static inline function byte_pos(text:String, char_pos:Int) return {
        if (char_pos==text.length) text.byteLength();
        else text.substr(0, char_pos).byteLength();
    }
    public static function toVSCSeverity(s:MessageSeverity) return {
        switch(s) {
            case Info: DiagnosticSeverity.Hint;
            case Warning: DiagnosticSeverity.Warning;
            case Error: DiagnosticSeverity.Error;
            default:  DiagnosticSeverity.Hint;
        }
    }
    public static function toVSCRange(info:Info) return {
        var r = info.range;
        if (r.isLineRange) new Range(new Position(r.start - 1, 0), new Position(r.end - 1, 0));
        else new Range(new Position(info.lineNumber-1, r.start), new Position(info.lineNumber-1, r.end));
    }
#end
}

class Debouncer<T> {
    var last:Float;
    var delay:Float;
    var timer:Timer;
    var queue:Array<T>;
    var fn:Array<T>->Void;
    var onDone:Array<Void->Void>;
    public function new(delay_ms:Int, fn:Array<T>->Void) {
        last = 0;
        queue = [];
        onDone = [];
        delay = delay_ms;
        this.fn = fn;
        last = 0;
        timer = new Timer(50);
        timer.run = apply;
    }
    function apply() {
        var dlt = Date.now().getTime() - last;
        var q = queue;
        if ((dlt < delay) || (q.length==0)) return;
        var od = onDone;
        queue = [];
        onDone = [];
        fn(q);
        for (f in od) {
            f();
        }
    }
    public function debounce(e:T) {
        queue.push(e);
        last = Date.now().getTime();
    }
    public function whenDone(f:Void->Void) {
        if (queue.length == 0) f();
        else onDone.push(f);
    }
    function dispose() {
        if (timer!=null) {
            timer.stop();
            timer = null;
        }
    }
}
