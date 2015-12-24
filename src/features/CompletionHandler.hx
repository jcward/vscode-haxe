package features;

import Vscode;

import HaxeContext;

import Tool;
using Tool;

import haxe.HaxePatcherCmd;
import haxe.HaxePatcherCmd.PatcherUnit;
import haxe.HaxeClient;
import haxe.HaxeClient.MessageSeverity;

class CompletionHandler implements CompletionItemProvider
{
  var hxContext:HaxeContext;
  
#if DO_FULL_PATCH
#else
  var changeDebouncer:Tool.Debouncer<TextDocumentChangeEvent>;
#end
  
  var lastModifications:Map<String, Float>;
  
  public function new(hxContext:HaxeContext):Void
  {
      this.hxContext = hxContext;
      
      var context = hxContext.context;
      
      lastModifications = new Map<String, Float>();
      
      var disposable = Vscode.languages.registerCompletionItemProvider('haxe', this, '.');
      context.subscriptions.push(disposable);

#if DO_FULL_PATCH
#else
      changeDebouncer = new Debouncer<TextDocumentChangeEvent>(250, changePatchs);
#end
      // remove the patch if the document is opened, saved, or closed
      context.subscriptions.push(Vscode.workspace.onDidOpenTextDocument(removePatch));    
      context.subscriptions.push(Vscode.workspace.onDidSaveTextDocument(removePatch));
      context.subscriptions.push(Vscode.workspace.onDidCloseTextDocument(removePatch));

#if DO_FULL_PATCH
#else
      context.subscriptions.push(Vscode.workspace.onDidChangeTextDocument(changePatch));
#end    
  }
  
  public function removePatch(document) {
      var server = hxContext.server;
      var path:String = document.uri.fsPath;
      lastModifications.remove(path);
      if (server.isPatchAvailable) {
          var client = server.make_client();
          client.cmdLine.beginPatch(path).remove();
          client.sendAll(null);
          hxContext.diagnostics.delete(untyped document.uri);
      }    
   }
   
#if DO_FULL_PATCH
#else
    function changePatchs(events:Array<TextDocumentChangeEvent>) {
        var server = hxContext.server;

        var client = server.make_client();
        
        var cl = client.cmdLine
            .cwd(server.proj_dir)
            //.hxml(server.hxml_file)
            //.version()
        ;

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
                
                var bl = text.byteLength();

                if (document.isDirty) patcher.delete(0, -1).insert(0, bl, text);
                else patcher.remove();
                
                //cl.display(path, bl, haxe.HaxeCmdLine.DisplayMode.Position);
                changed = true;
            } else if (server.isPatchAvailable) {
                for (change in changes) {
                    var rl = change.rangeLength;
                    var range = change.range;
                    var rs = document.offsetAt(range.start);
                    if (rl > 0) patcher.delete(rs, rl, PatcherUnit.Char);
                    var text = change.text;
                    if (text != "") patcher.insert(rs, text.length, text, PatcherUnit.Char);
                }
                
                var pos =0;
                if (editor != null) {
                    if (editor.document == document) pos = Tool.byte_pos(text, document.offsetAt(editor.selection.active));
                    else pos = text.byteLength();
                } else {
                    pos = text.byteLength();                
                }

                //cl.display(path, pos, haxe.HaxeCmdLine.DisplayMode.Position);
                changed = true;
            } 
        }
        
        if (changed)
            client.sendAll(function (s, message, error) {
                if (error==null) hxContext.applyDiagnostics(message);        
            });
    }
    function changePatch(event:TextDocumentChangeEvent) {
        var document = event.document;
        var path:String = document.uri.fsPath;
        if (event.contentChanges.length==0) {
            lastModifications.remove(path);
            return;
        }
        lastModifications.set(path, Date.now().getTime());
        changeDebouncer.debounce(event);
    }
#end

  public function provideCompletionItems(document:TextDocument,
                                         position:Position,
                                         cancelToken:CancellationToken):Thenable<Array<CompletionItem>>
  {
      var server = hxContext.server;

    // find last . before current position
    var line = document.lineAt(position);
    var dot_offset = 0;
trace(document);
trace(position);
trace(line);
trace(cancelToken);

//    var subline = line.text.substr(0, position.character);
//    if (subline.indexOf('.')>=0) {
//      dot_offset = subline.lastIndexOf('.') - position.character + 1;
//    }

    // So far we don't parse this output from the completion server:
    // <type>key : String -&gt; Bool</type>
    //else if (subline.indexOf('(')>=0) {
    //  dot_offset = subline.lastIndexOf('(') - position.character + 1;
    //}
    var text = document.getText();
    var char_pos = document.offsetAt(position) + dot_offset;
    var path:String = document.uri.fsPath;

    var lm = lastModifications.get(path);
    lastModifications.set(path, null);
    var makeCall = false;
    var displayMode = haxe.HaxeCmdLine.DisplayMode.Default;
    if (lm==null) makeCall = true;
    else {
        var ct = Date.now().getTime();
        var dlt = ct - lm;
        trace(dlt);
        if (dlt < 200) {
            makeCall = text.charAt(char_pos-1) == '.';
        } else {
            makeCall = true;
        }
    }
    
    //Vscode.window.showInformationMessage("C: "+byte_pos);
    //Vscode.window.showInformationMessage("F: "+path);
    
    if (!makeCall)
        return new Thenable<Array<CompletionItem>>( function(resolve:Array<CompletionItem>->Void) {resolve([]);});

    var isDot = text.charAt(char_pos-1) == '.';
    if (!isDot) displayMode = haxe.HaxeCmdLine.DisplayMode.Position;

    var byte_pos = Tool.byte_pos(text, char_pos);

    return new Thenable<Array<CompletionItem>>( function(resolve:Array<CompletionItem>->Void) {
      function make_request() {
        server.request(path,
                       byte_pos,
                       displayMode,
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
              var text = document.getText();
              patcher.delete(0, -1).insert(0, text.byteLength(), text);
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