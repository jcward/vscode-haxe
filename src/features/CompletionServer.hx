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
    
    // I hacked this together in JS, Tides will likely replace
    public function parse_items(data:Message):Array<CompletionItem> {
        var rtn = new Array<CompletionItem>();
        
        //if (decorator != null) decorator(data);
        if (data.severity==MessageSeverity.Error) {
            hxContext.applyDiagnostics(data);
            return rtn;
        }
        
        var data_str = data.stderr.join("\n"); // Don't know why this is stderr
        
        // TODO: xml parsing, for now, a hack
        //Vscode.window.showInformationMessage("Decoding: "+data_str.length);
        //Vscode.window.showInformationMessage("D: "+data_str);
        
        untyped __js__('
                  // Hack hack hack
                  var items = data_str.split("<i n=");
                  for (var i=0; i<items.length; i++) {
                    var item = items[i];
                    if (item.indexOf("\\"")==0) {
                      var name = item.match(/"(.*?)"/)[1];
                      var type = item.match(/<t>(.*?)<\\/t>/)[1];
                      type = type.replace(/&gt;/g, ">");
                      type = type.replace(/&lt;/g, "<");
                      //Vscode.window.showInformationMessage(name+" : "+type);
                      var ci = new Vscode.CompletionItem(name);
                      ci.detail = type;
                      if (type.indexOf("->")>=0) {
                        ci.kind = Vscode.CompletionItemKind.Method;
                      } else {
                        ci.kind = Vscode.CompletionItemKind.Property;
                      }
                      rtn.push(ci);
                    }
                  }
        ');
        
        //Vscode.window.showInformationMessage("Returning: "+rtn.length);
        return rtn;
    }
    
    public function request(file:String,
                            byte_pos:Int,
                            mode:haxe.HaxeCmdLine.DisplayMode,
                            callback:Array<CompletionItem>->Void) {

        var cl = client.cmdLine;
        
        cl
        .cwd(hxContext.projectDir)
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
