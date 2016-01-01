package features;

import Vscode;

import HaxeContext;
import haxe.HaxeClient;

import Tool;
using Tool;

/*
@:jsRequire("net")
extern class Net { }

@:jsRequire("child_process")
extern class ChildProcess {
  public static var exec(default, null):String->Function->Void;
}
*/

class CompletionServer
{
    public var hxContext(default, null):HaxeContext;
    
    // TODO: disposable, stop server
    //public var host(default, null):String;
    //public var port(default, null):Int;
    //public var proj_dir(default, null):String;
//    public var hxml_file(default, null):String;
    
    public var client(default, null):HaxeClient;
    
    public var isServerAvailable:Bool;
    public var isPatchAvailable:Bool;
    
    public inline function make_client() return new HaxeClient(hxContext.configuration.haxeServerHost, hxContext.configuration.haxeServerPort);
    
    public function new(hxContext:HaxeContext):Void {
        this.hxContext = hxContext;
       
        isServerAvailable = false;
        isPatchAvailable = false;
    
        client = make_client();

        // testing https://github.com/pleclech/haxe/tree/memory-file
        // test to see if patcher is available
        client.isPatchAvailable(function(data) {
            isPatchAvailable = data.isOptionAvailable;
            isServerAvailable = data.isServerAvailable;
        });
        
        //var exec = ChildProcess.exec;
        //Vscode.window.showInformationMessage("Start? port="+port+", "+exec);
        /*
        var restart:Function = null;
        restart = function() {
            Vscode.window.showInformationMessage("Starting haxe completion server...");
            exec("haxe --wait "+port, restart);
        };
        */
        //restart(); // start by hand for now...
    }
    
    static var reI=~/<i n="([^"]+)" k="([^"]+)"( ip="([0-1])")?><t>([^<]*)<\/t><d>([^<]*)<\/d><\/i>/;
    static var reGT = ~/&gt;/g;
    static var reLT = ~/&lt;/g;
    static var reMethod = ~/Void|Unknown/;

    // I hacked this together in JS, Tides will likely replace
    public function parse_items(msg:Message):Array<CompletionItem> {
        var rtn = new Array<CompletionItem>();
        
        //if (decorator != null) decorator(data);
        if (msg.severity==MessageSeverity.Error) {
            hxContext.applyDiagnostics(msg);
            return rtn;
        }
        var datas = msg.stderr;
        if ((datas.length > 2) && (datas[0]=="<list>")) {
            datas.shift();
            datas.pop();
            datas.pop();
            for (data in datas) {
                trace(data);
                if (reI.match(data)) {
                    var n = reI.matched(1);
                    var k = reI.matched(2);
                    var ip = reI.matched(4);
                    var t = reI.matched(5);
                    t = reGT.replace(reLT.replace(t, "<"), ">");
                    var d = reI.matched(6);
                    var ci = new Vscode.CompletionItem(n);
                    ci.documentation = d;
                    ci.detail = t;
                    switch(k) {
                        case "method":
                            var ts = t.split("->");
                            var l = ts.length;
                            if (reMethod.match(ts[l-1])) ci.kind = Vscode.CompletionItemKind.Method;
                            else ci.kind = Vscode.CompletionItemKind.Function;
                        case "var":
                            if (ip=="1") ci.kind = Vscode.CompletionItemKind.Property;
                            else ci.kind = Vscode.CompletionItemKind.Field;
                        default:
                            ci.kind = Vscode.CompletionItemKind.Field;
                    }
                    rtn.push(ci);
                }
            }     
        }
        return rtn;
    }
    
    public function request(file:String,
                            byte_pos:Int,
                            mode:haxe.HaxeCmdLine.DisplayMode,
                            callback:Array<CompletionItem>->Void) {

        var cl = client.cmdLine;
        
        cl
        .cwd(hxContext.projectDir)
        .define("display-details")
        .hxml(hxContext.configuration.haxeDefaultBuildFile)
        .noOutput()
        .display(file, byte_pos, mode);
            
        client.sendAll(function (s, message, err) {
            if (err != null) {
                isServerAvailable = false;
                err.message.displayAsError();
                callback([]);                
            } else {
                isServerAvailable = true;
                callback(parse_items(message));
            }
        });
   }
}
