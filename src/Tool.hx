import haxe.Timer;
import Vscode;
import haxe.HaxeClient.MessageSeverity;
import haxe.HaxeClient.Info;
#if js
import js.node.Buffer;
using Tool;
#end

class Tool {
    public static inline function displayAsInfo(s:String) Vscode.window.showInformationMessage(s);
    public static inline function displayAsError(s:String) Vscode.window.showErrorMessage(s);
    public static inline function displayAsWarning(s:String) Vscode.window.showWarningMessage(s);
#if js
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
    var last:Int;
    var delay:Int;
    var timer:Timer;
    var queue:Array<T>;
    var fn:Array<T>->Void;
    var onDone:Array<Void->Void>;
    public function new(delay_ms:Int, fn:Array<T>->Void) {
        last = 0;
        queue = [];
        onDone = [];
        timer = null;
        delay = delay_ms;
        this.fn = fn;
    }
    function apply() {
        if (timer!=null) timer.stop();
        timer = null;
        var q = queue;
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
        if (timer!=null) timer.stop();
        timer = Timer.delay(apply, delay);
    }
    public function whenDone(f:Void->Void) {
        if (queue.length == 0) f();
        else onDone.push(f);
    }
}
