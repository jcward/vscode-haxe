package features;

import Vscode;

import HaxeContext;

import Tool;
using Tool;

import haxe.HaxePatcherCmd;
import haxe.HaxePatcherCmd.PatcherUnit;
import haxe.HaxeClient;
import haxe.HaxeClient.MessageSeverity;
import haxe.HaxeCmdLine.IdeFlag;


class CompletionHandler implements CompletionItemProvider
{
  var hxContext:HaxeContext;
  
  public function new(hxContext:HaxeContext):Void
  {
      this.hxContext = hxContext;
      
      var context = hxContext.context;
            
      var disposable = Vscode.languages.registerCompletionItemProvider(HaxeContext.languageID(), this, '.', ':', '{');
      context.subscriptions.push(disposable);
  }
  
  static var reI=~/<i n="([^"]+)" k="([^"]+)"( ip="([0-1])")?( f="(\d+)")?><t>([^<]*)<\/t><d>([^<]*)<\/d><\/i>/;
  static var reGT = ~/&gt;/g;
  static var reLT = ~/&lt;/g;
  static var reMethod = ~/Void|Unknown/;
  
  public function parse_items(msg:Message):Array<CompletionItem> {
      var rtn = new Array<CompletionItem>();
      
      if (msg.severity==MessageSeverity.Error) {
          hxContext.applyDiagnostics(msg);
          return rtn;
      }
      var datas = msg.stderr;
      if ((datas.length > 2) && (datas[0]=="<list>")) {
          datas.shift();
          datas.pop();
          datas.pop();
          var len = datas.length;
          var i = 0;
          while (i<len) {
              var tmp = datas[i++];
              var data = "";
              if (tmp.substr(0, 2)=="<i") {
                  while (i<len) {
                      data += tmp;
                      if (tmp.substr(tmp.length-2, 2) == "i>") break;
                      tmp = datas[i++];
                  }
                  if (i==len) data+=tmp;
              }
              if (reI.match(data)) {
                  var n = reI.matched(1);
                  var k = reI.matched(2);
                  var ip = reI.matched(4);
                  var f:IdeFlag = Std.parseInt(reI.matched(6))|0;
                  var t = reI.matched(7);
                  t = reGT.replace(reLT.replace(t, "<"), ">");
                  var d = reI.matched(8);
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
                        else if ((f & IdeFlag.Property) != 0) ci.kind = Vscode.CompletionItemKind.Property;
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

  public function provideCompletionItems(document:TextDocument,
                                         position:Position,
                                         cancelToken:CancellationToken):Thenable<Array<CompletionItem>>
  {
    // So far we don't parse this output from the completion server:
    // <type>key : String -&gt; Bool</type>
    //else if (subline.indexOf('(')>=0) {
    //  dot_offset = subline.lastIndexOf('(') - position.character + 1;
    //}
    
    var changeDebouncer = hxContext.changeDebouncer;
    var client = hxContext.client;

    var text = document.getText();
    var char_pos = document.offsetAt(position);
    var path:String = document.uri.fsPath;

    var documentState = hxContext.getDocumentState(path);
    var lm = documentState.lastModification;

    var delta = hxContext.getTime() - lm;
    
    var makeCall = false;
    var displayMode = haxe.HaxeCmdLine.DisplayMode.Default;
  
    var lastChar = text.charAt(char_pos-1);
    var isDot =  lastChar == '.';
       
    makeCall = isDot || (lastChar == '{');
    
    var positionMode = !makeCall;

    if (isDot) {
        if (delta > 150) makeCall = true;
    }
    
    if (!makeCall) {
        var items = [];
        // metadata completion
        if ((lastChar == ':') && (text.charAt(char_pos-2)=="@")) {
            for (data in hxContext.client.metas) {
                var ci = new Vscode.CompletionItem(data.name);
                ci.documentation = data.doc;
                items.push(ci);
            }
            hxContext.cancelDiagnostic();
        }
        return new Thenable<Array<CompletionItem>>(function(resolve) {resolve(items);});
    }
 
    if (positionMode) displayMode = haxe.HaxeCmdLine.DisplayMode.Position;

    var byte_pos = Tool.byte_pos(text, char_pos);
    
    hxContext.cancelDiagnostic();

    return new Thenable<Array<CompletionItem>>(function(resolve) {
      var trying = 1;

      function make_request() {
          hxContext.cancelDiagnostic();

          var cl = client.cmdLine.save()
          .cwd(hxContext.projectDir)
          .define("display-details")
          .hxml(hxContext.configuration.haxeDefaultBuildFile)
          .noOutput()
          .display(path, byte_pos, displayMode);
          
          client.sendAll(
              function (s, message, err) {
                if (err != null) {
                    if (trying <= 0) {
                        err.message.displayAsError();
                        resolve([]);
                    } else {
                        trying--;
                        hxContext.launchServer().then(function(port) {
                           make_request(); 
                        });
                    }                
                } else {
                    resolve(parse_items(message));
                }
             },
             true,
             "completion"
          );
      }

      // TODO: haxe completion server requires save before compute...
      //       try temporary -cp?
      //       See: https://github.com/HaxeFoundation/haxe/issues/4651
      
      var isDirty = document.isDirty;

      function doRequest() {
        var isPatchAvailable = client.isPatchAvailable;
        var isServerAvailable = client.isServerAvailable;
        if (isPatchAvailable) {
#if DO_FULL_PATCH
            if (isDirty) {
                client.beginPatch(path).delete(0,-1).insert(0, document.getText());
                make_request();
            } else {
                make_request();
            }
#else
            changeDebouncer.whenDone(function(){make_request();});
#end
        } else {
            if (isDirty && isServerAvailable) {
                document.save().then(function (saved) {
                    if (saved) make_request(); 
                    else resolve([]);
                });
            } else {
                make_request();
            }
        }          
      }
      
      if (!client.isServerAvailable) {
          var cl = client.cmdLine.save().version();
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
                    
          client.sendAll(
            function (s:Socket, message, err) {
                var isPatchAvailable = false;
                if (client.isServerAvailable) {
                    if (message.severity==MessageSeverity.Error) {
                        if (message.stderr.length > 1) isPatchAvailable = HaxeClient.isOptionExists(HaxePatcherCmd.name(), message.stderr[1]);
                    }
                    else isPatchAvailable = true;
                }
                client.isPatchAvailable = isPatchAvailable;
                doRequest();
            },
            true             
          );
      } else doRequest();
    });
  }
	
  public function resolveCompletionItem(item:CompletionItem,
                                        cancelToken:CancellationToken):CompletionItem {
    return item;
  }
}