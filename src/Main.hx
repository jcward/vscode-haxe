import Vscode;
import haxe.ds.Either;
import haxe.Constraints.Function;

import haxe.HaxePatcherCmd;
import haxe.HaxePatcherCmd.PatcherUnit;
import haxe.HaxeClient;
import haxe.HaxeClient.Message;
using Tool;

/*
 compile with -DDO_FULL_PATCH if you want to sent the whole file at completion
 instead of incremental change
*/

class Main {

	@:expose("activate")
	static function main(context:ExtensionContext) {

    test_register_command(context);

    //test_register_hover(context);
    //test_register_hover_thenable(context);

    var server = new CompletionServer(Vscode.workspace.rootPath);
    var handler = new CompletionHandler(server, context);

    // TODO: server implements Disposable
    context.subscriptions.push(untyped {
      dispose:function() {
        Vscode.window.showInformationMessage("Got dispose!");
        //TODO: server.kill();
      }
    });

		//Vscode.window.showInformationMessage("Haxe language support loaded!");
	}

  static function test_register_command(context:ExtensionContext):Void
  {
    // Testing a command, access with F1 haxe...
		var disposable = Vscode.commands.registerCommand("haxe.hello", function() {
			Vscode.window.showInformationMessage("Hello from haxe!");
		});
		context.subscriptions.push(disposable);
  }


  static function test_register_hover(context:ExtensionContext):Void
  {
    // Test hover code
		var disposable = Vscode.languages.registerHoverProvider('haxe', {
			provideHover:function(document:TextDocument,
														position:Position,
														cancelToken:CancellationToken):Hover
			{
				return new Hover('I am a hover! pos: '+untyped(JSON).stringify(position));
			}
		});

    context.subscriptions.push(disposable);
  }

  static function test_register_hover_thenable(context:ExtensionContext):Void
  {
    // Test hover code
		var disposable = Vscode.languages.registerHoverProvider('haxe', {
			provideHover:function(document:TextDocument,
														position:Position,
														cancelToken:CancellationToken):Thenable<Hover>
			{
        var s = untyped JSON.stringify(position);
				return new Thenable<Hover>( function(resolve:Hover->Void) {
          var h = new Hover('I am a thenable hover! pos: '+s);
          resolve(h);
				});
			}
		});

    context.subscriptions.push(disposable);
  }
}

class CompletionHandler implements CompletionItemProvider
{
  var server:CompletionServer;
  
  public function new(server:CompletionServer,
                      context:ExtensionContext):Void
  {
    this.server = server;
        
    // Test hover code
	var disposable = Vscode.languages.registerCompletionItemProvider('haxe', this, '.');
    context.subscriptions.push(disposable);
    
    function removePatch(document) {
       if (server.isPatchAvailable) {
          var path:String = document.uri.fsPath;
          var client = server.client;
          client.cmdLine.beginPatch(path).remove();
          client.sendAll(null);         
        }     
   }
 
    // remove the patch if the document is opened, saved, or closed  
    context.subscriptions.push(Vscode.workspace.onDidOpenTextDocument(removePatch));    
    context.subscriptions.push(Vscode.workspace.onDidSaveTextDocument(removePatch));
    context.subscriptions.push(Vscode.workspace.onDidCloseTextDocument(removePatch));
    
#if DO_FULL_PATCH
#else
    function changePatch(event:TextDocumentChangeEvent) {
        if (!server.isServerAvailable) {
            var changes = event.contentChanges;
            if (changes.length > 0) {
                var document = event.document;
                var client = server.client;
                var patcher = client.cmdLine.beginPatch(document.uri.fsPath);
                if (document.isDirty) patcher.delete(0, -1).insert(0, document.getText());
                else patcher.remove();
                client.sendAll(null);
            }
        } else if (server.isPatchAvailable) {
            var changes = event.contentChanges;
            if (changes.length > 0) {
                var document = event.document;
                var client = server.client;
                var patcher = client.cmdLine.beginPatch(document.uri.fsPath);
                for (change in changes) {
                    var rl = change.rangeLength;
                    var range = change.range;
                    var rs = document.offsetAt(range.start);
                    if (change.rangeLength > 0) {
                        patcher.delete(rs, rl, PatcherUnit.Char);
                    }
                    var text = change.text;
                    if (text != "") {
                        patcher.insert(rs, text, PatcherUnit.Char);
                    }
                }
                client.sendAll(null); 
            }
        }
    }
    context.subscriptions.push(Vscode.workspace.onDidChangeTextDocument(changePatch));
#end
  }

  public function provideCompletionItems(document:TextDocument,
                                         position:Position,
                                         cancelToken:CancellationToken):Thenable<Array<CompletionItem>>
  {
    // find last . before current position
    var line = document.lineAt(position);
    var dot_offset = 0;

//    var subline = line.text.substr(0, position.character);
//    if (subline.indexOf('.')>=0) {
//      dot_offset = subline.lastIndexOf('.') - position.character + 1;
//    }

    // So far we don't parse this output from the completion server:
    // <type>key : String -&gt; Bool</type>
    //else if (subline.indexOf('(')>=0) {
    //  dot_offset = subline.lastIndexOf('(') - position.character + 1;
    //}

    var byte_pos = document.offsetAt(position) + dot_offset;
    byte_pos = document.getText().substr(0, byte_pos).byteLength();
    var path:String = document.uri.fsPath;

		//Vscode.window.showInformationMessage("C: "+byte_pos);
		//Vscode.window.showInformationMessage("F: "+path);

    return new Thenable<Array<CompletionItem>>( function(resolve:Array<CompletionItem>->Void) {
      function make_request() {
        server.request(path,
                       byte_pos,
                       function(items:Array<CompletionItem>) {
                         resolve(items);
                       });
      }

      // TODO: haxe completion server requires save before compute...
      //       try temporary -cp?
      //       See: https://github.com/HaxeFoundation/haxe/issues/4651
      
      var isDirty = document.isDirty;
      var client = server.client;

      function doRequest() {
        if (server.isPatchAvailable) {
#if DO_FULL_PATCH
            if (isDirty) {
                var client = server.client;
                client.beginPatch(path).delete(0,-1).insert(0, document.getText());
                make_request();
            } else {
                make_request();
            }
#else
            make_request();
#end
        } else {
            if (isDirty && server.isServerAvailable) {
                document.save().then(make_request);
            } else {
                make_request();
            }
        }          
      }
      
      if (!server.isServerAvailable) {
          var hs = server.make_client();
          var cl = hs.cmdLine;
          var patcher = cl.beginPatch(path);

          if (isDirty) {
#if DO_FULL_PATCH
#else
              patcher.delete(0, -1).insert(0, document.getText());
#end
          } else {
              patcher.remove();
          }
          
          server.isPatchAvailable = false;
          
          cl.version();
          
          hs.sendAll(
            function (s:Socket, message, err) {
                var isPatchAvailable = false;
                var isServerAvailable = true;
                if (err != null) isServerAvailable = false;
                else {
                    server.isServerAvailable = true;
                    if (message.hasError) isPatchAvailable = HaxeClient.isOptionExists(HaxePatcherCmd.name(), message.stderr[0]);
                    else isPatchAvailable = true;
                }
                server.isServerAvailable = err==null;
                server.isPatchAvailable=isPatchAvailable;
                doRequest();
            }             
          );
      } else doRequest();
    });
  }
	
  public function resolveCompletionItem(item:CompletionItem,
                                        cancelToken:CancellationToken):CompletionItem {
    return item;
  }
}

@:jsRequire("net")
extern class Net { }

@:jsRequire("child_process")
extern class ChildProcess {
  public static var exec(default, null):String->Function->Void;
}

// TODO: this class will basically be replaced with snowkit/Tides
//       when it becomes availble. This is a hackish placeholder.
class CompletionServer
{
  // TODO: disposable, stop server
  public var host(default, null):String;
  public var port(default, null):Int;
  public var proj_dir(default, null):String;
  
  public var client(default, null):HaxeClient;
  
  public var isServerAvailable:Bool;
  public var isPatchAvailable:Bool;
  
  public inline function make_client() return new HaxeClient(host, port);
  
  public function new(proj_dir:String):Void
  {
    this.proj_dir = proj_dir;
    
    host = "127.0.0.1";
    
    port = 6000; //INST_PORT++;

    isServerAvailable = false;
    isPatchAvailable = false;
    
    client = make_client();

    // testing https://github.com/pleclech/haxe/tree/memory-file
    // test to see if patcher is available
    client.isPatchAvailable(function(data) {
        isPatchAvailable = data.isOptionAvailable;
        isServerAvailable = data.isServerAvailable;            
    });

    var exec = ChildProcess.exec;
    //Vscode.window.showInformationMessage("Start? port="+port+", "+exec);
    var restart:Function = null;
    restart = function() {
			Vscode.window.showInformationMessage("Starting haxe completion server...");
      exec("haxe --wait "+port, restart);
    };
    //restart(); // start by hand for now...
  }

  // I hacked this together in JS, Tides will likely replace
  public function parse_items(data:Message):Array<CompletionItem>
  {
    var rtn = new Array<CompletionItem>();
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
                          callback:Array<CompletionItem>->Void) {
 
 
    var hxml_file = "build.hxml"; // TODO: externalize
    var dir = this.proj_dir;

    var cl = client.cmdLine;
    cl
        .cwd(dir)
        .custom(' $hxml_file')
        .display(file, byte_pos, haxe.HaxeCmdLine.DisplayMode.Default);

    client.sendAll(
        function (s, message, err) {
            if (err != null) {
                isServerAvailable = false;
                err.message.displayAsError();
                callback([]);                
            } else {
                isServerAvailable = true;
                callback(parse_items(message));
            }
        }
    );
  }

}
