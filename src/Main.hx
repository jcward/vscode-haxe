import Vscode;
import haxe.ds.Either;
import haxe.Constraints.Function;

import haxe.HaxePatcherCmd;
import haxe.HaxePatcherCmd.PatcherUnit;
import haxe.HaxeClient;
import haxe.HaxeClient.Message;
import haxe.HaxeClient.MessageSeverity;
using Tool;

/*
 compile with -DDO_FULL_PATCH if you want to sent the whole file at completion
 instead of incremental change
*/

class Main {
    static var decoration:decorator.HaxeDecoration;

	@:expose("activate")
	static function main(context:ExtensionContext) {

        decoration = new decorator.HaxeDecoration();
        
        var diagnostic =  Vscode.languages.createDiagnosticCollection('haxe');
        context.subscriptions.push(untyped diagnostic);

        test_register_command(context);

        //test_register_hover(context);
        //test_register_hover_thenable(context);

        function applyCurrentDecorations(message:haxe.Message) {
            diagnostic.clear();

            var all = new Map<String, Null<Array<Diagnostic>>>();            
            for (info in message.infos) {
                var diags = all.get(info.fileName);
                if (diags == null) {
                    diags = [];
                    all.set(info.fileName, diags);
                }
                var diag = new Diagnostic(info.toVSCRange(), info.message, message.severity.toVSCSeverity());
                diags.push(diag);
            }
            var entries:Array<Dynamic> = [];
            for (fileName in all.keys()) {
                var diags = all.get(fileName);
                var url = Uri.file(fileName);
                if (diags==null) {
                    diagnostic.set(url, []);
                    continue;
                }
                diagnostic.set(url, diags);
            }
            //applyDecorations(Vscode.window.activeTextEditor, message.infos, message.severity == haxe.HaxeClient.MessageSeverity.Error);
        }

        var server = new CompletionServer(Vscode.workspace.rootPath, diagnostic, applyCurrentDecorations);
        var handler = new CompletionHandler(server, context, diagnostic, applyCurrentDecorations);

        function dispose(){
 //               Vscode.window.showInformationMessage("Got dispose!");
            if (server.isServerAvailable && server.isPatchAvailable) {
                var client= server.client;
                client.clear();
                var cl = client.cmdLine;
                for (editor in Vscode.window.visibleTextEditors) {
                    cl.beginPatch(editor.document.uri.fsPath).remove();
                }
                client.sendAll(null);
            }
                //TODO: server.kill();            
        }

        // TODO: server implements Disposable
        context.subscriptions.push( untyped {
            dispose:dispose
        });

		//Vscode.window.showInformationMessage("Haxe language support loaded!");
	}
  
    static function applyDecorations(editor, infos:Array<haxe.Info>, isError:Bool) {
        if (editor==null) return;
        var document = editor.document;
        var path = document.uri.fsPath;
        var lineErrors = [];
        var charErrors = [];
        for (info in infos) {
            if (info.fileName == path) {
                var re = info.toVSCRange();
                var r = info.range;
                if (r.isLineRange) {
                    if (isError) lineErrors.push({hoverMessage:info.message, range:re});
                } else {
                    if (isError) charErrors.push({hoverMessage:info.message, range:re});
                }
            }
        }
        editor.setDecorations(decoration.errorLineDecoration, lineErrors);
        editor.setDecorations(decoration.errorCharDecoration, charErrors);
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
  
  var decorator:Null<Message->Void>;
  
#if DO_FULL_PATCH
#else
  var changeDebouncer:Tool.Debouncer<TextDocumentChangeEvent>;
#end
  
  public function new(server:CompletionServer,
                      context:ExtensionContext,
                      diagnostic:DiagnosticCollection,
                      ?decorator:Null<Message->Void>=null
                      ):Void
  {
    this.server = server;
    this.decorator = decorator;
     
    // Test hover code
	var disposable = Vscode.languages.registerCompletionItemProvider('haxe', this, '.');
    context.subscriptions.push(disposable);

#if DO_FULL_PATCH
#else  
    changeDebouncer = new Tool.Debouncer<TextDocumentChangeEvent>(100, changePatchs);
#end

    function removePatch(document) {
       if (server.isPatchAvailable) {
          var path:String = document.uri.fsPath;
          var client = server.make_client();
          client.cmdLine.beginPatch(path).remove();
          client.sendAll(null);
          var activeEditor = Vscode.window.activeTextEditor;
          if (activeEditor.document==document) {
              decorator({stdout:[], stderr:[], infos:[], severity:MessageSeverity.Error});
          }
        }     
   }
 
    // remove the patch if the document is opened, saved, or closed  
    context.subscriptions.push(Vscode.workspace.onDidOpenTextDocument(removePatch));    
    context.subscriptions.push(Vscode.workspace.onDidSaveTextDocument(removePatch));
    context.subscriptions.push(Vscode.workspace.onDidCloseTextDocument(removePatch));

#if DO_FULL_PATCH
#else
    context.subscriptions.push(Vscode.workspace.onDidChangeTextDocument(changePatch));
#end    
  }

#if DO_FULL_PATCH
#else
    function changePatchs(events:Array<TextDocumentChangeEvent>) {
        var client = server.make_client();
        
        var cl = client.cmdLine;
            cl
                .cwd(server.proj_dir)
                .hxml(server.hxml_file);

        var done = new Map<String, Bool>();
        var changed = false;        
        for (event in events) {
            var changes = event.contentChanges;
            if (changes.length == 0) continue;
            
            var editor = Vscode.window.activeTextEditor;

            var document = event.document;
            var path = document.uri.fsPath;
            var len = path.length;
            
            if (document.languageId != "haxe") continue;
            
            var text = document.getText();
            
            var patcher = cl.beginPatch(path);
                            
            if (!server.isServerAvailable) {
                if (done.get(path)) continue;
                done.set(path, true);

                if (document.isDirty) patcher.delete(0, -1).insert(0, text);
                else patcher.remove();
                
                cl.display(path, text.byteLength(), haxe.HaxeCmdLine.DisplayMode.Position);
                
                changed = true;
            } else if (server.isPatchAvailable) {
                for (change in changes) {
                    var rl = change.rangeLength;
                    var range = change.range;
                    var rs = document.offsetAt(range.start);
                    if (rl > 0) patcher.delete(rs, rl, PatcherUnit.Char);
                    var text = change.text;
                    if (text != "") patcher.insert(rs, text, PatcherUnit.Char);
                }
                
                var pos =0;
                if (editor != null) {
                    if (editor.document == document) pos = Tool.byte_pos(text, document.offsetAt(editor.selection.active));
                    else pos = text.byteLength();
                } else {
                    pos = text.byteLength();                
                }
                cl.display(path, pos, haxe.HaxeCmdLine.DisplayMode.Position);
                changed = true;
            } 
        }
        
        if (changed)
            client.sendAll(function (s, message, error) {
                if (error==null) decorator(message);        
            });
    }
    function changePatch(event:TextDocumentChangeEvent) {
        if (event.contentChanges.length==0) return;
        changeDebouncer.debounce(event);
    }
#end


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

    var byte_pos = Tool.byte_pos(document.getText(), document.offsetAt(position) + dot_offset);

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
            changeDebouncer.whenDone(make_request);
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
                    if (message.severity==MessageSeverity.Error)
                        isPatchAvailable = HaxeClient.isOptionExists(HaxePatcherCmd.name(), message.stderr[0]);
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
  public var hxml_file(default, null):String;
  
  public var client(default, null):HaxeClient;
  
  public var isServerAvailable:Bool;
  public var isPatchAvailable:Bool;
  
  public inline function make_client() return new HaxeClient(host, port);
  
  public var decorator:Null<Message->Void>;
  
  public function new(proj_dir:String, diagnostic:DiagnosticCollection, ?decorator:Null<Message->Void>=null):Void
  {
    this.proj_dir = proj_dir;
    
    hxml_file = "build.hxml"; // TODO: externalize
     
    host = "127.0.0.1";
    
    port = 6000; //INST_PORT++;

    isServerAvailable = false;
    isPatchAvailable = false;
    
    this.decorator = decorator;
    
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
    
    if (decorator != null) decorator(data);
    if (data.severity==MessageSeverity.Error) return rtn;
    
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
 
    var cl = client.cmdLine;
    cl
        .cwd(proj_dir)
        .hxml(hxml_file)
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
