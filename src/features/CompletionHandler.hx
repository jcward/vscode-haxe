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
  
  public function new(hxContext:HaxeContext):Void
  {
      this.hxContext = hxContext;
      
      var context = hxContext.context;
            
      var disposable = Vscode.languages.registerCompletionItemProvider(HaxeContext.languageID(), this, '.');
      context.subscriptions.push(disposable);
  }
  public function provideCompletionItems(document:TextDocument,
                                         position:Position,
                                         cancelToken:CancellationToken):Thenable<Array<CompletionItem>>
  {
      var changeDebouncer = hxContext.changeDebouncer;
      var server = hxContext.server;

    // find last . before current position
    var line = document.lineAt(position);

    // So far we don't parse this output from the completion server:
    // <type>key : String -&gt; Bool</type>
    //else if (subline.indexOf('(')>=0) {
    //  dot_offset = subline.lastIndexOf('(') - position.character + 1;
    //}
    
    var text = document.getText();
    var char_pos = document.offsetAt(position);
    var path:String = document.uri.fsPath;

    var lastModifications = hxContext.lastModifications;
    var lm = lastModifications.get(path);
    lastModifications.set(path, null);

    var makeCall = false;
    var displayMode = haxe.HaxeCmdLine.DisplayMode.Default;
    if (lm==null) makeCall = true;
    else {
        var ct = Date.now().getTime();
        var dlt = ct - lm;
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