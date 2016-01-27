package features;

import Vscode;

import HaxeContext;
import Tool.getTime;

import Tool;
using Tool;

import haxe.HaxePatcherCmd;
import haxe.HaxePatcherCmd.PatcherUnit;
import haxe.HaxeClient;
import haxe.HaxeClient.MessageSeverity;
import haxe.HaxeCmdLine.IdeFlag;

using HaxeContext;

import js.Promise as JSPromise;

class CompletionHandler implements CompletionItemProvider
{
  var hxContext:HaxeContext;

  public function new(hxContext:HaxeContext):Void
  {
      this.hxContext = hxContext;

      var context = hxContext.context;

      var disposable = Vscode.languages.registerCompletionItemProvider(HaxeContext.languageID(), this, '.', ':', '{', ' ');
      context.subscriptions.push(disposable);
  }

  static var reI=~/<i n="([^"]+)" k="([^"]+)"( ip="([0-1])")?( f="(\d+)")?><t>([^<]*)<\/t><d>([^<]*)<\/d><\/i>/;
  static var reGT = ~/&gt;/g;
  static var reLT = ~/&lt;/g;
  static var reMethod = ~/Void|Unknown/;

  public function parse_items(msg:Message):Array<CompletionItem> {
      var rtn = new Array<CompletionItem>();
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
                      case "package":
                        ci.kind = Vscode.CompletionItemKind.Module;
                      case "type":
                        ci.kind = Vscode.CompletionItemKind.Class;
                      default:
                        ci.kind = Vscode.CompletionItemKind.Field;
                  }
                  rtn.push(ci);
              }
          }
      } else {
          rtn.push(null);
      }
      return rtn;
  }

  static var reWord = ~/[a-zA-Z_$]/;
  static var reWS = ~/[\r\n\t\s]/;

  public function provideCompletionItems(document:TextDocument,
                                         position:Position,
                                         cancelToken:CancellationToken):Thenable<Array<CompletionItem>>
  {
    return new Thenable<Array<CompletionItem>>(function(accept, reject) {
        if (cancelToken.isCancellationRequested) {
            reject([]);
            return;
        }

        var changeDebouncer = hxContext.changeDebouncer;

        var client = hxContext.client;
        var text = document.getText();
        var char_pos = document.offsetAt(position);
        var ds = hxContext.getDocumentState(document.uri.fsPath);
        var path = ds.path();

        var makeCall = false;
        var displayMode = haxe.HaxeCmdLine.DisplayMode.Default;

        var lastChar = text.charAt(char_pos-1);
        var isDot =  lastChar == '.';

        var isProbablyMeta = (lastChar == ":");
        var doMetaCompletion = isProbablyMeta && (text.charAt(char_pos-2)=="@");

        var word = "";

        var displayClasses = isProbablyMeta && !doMetaCompletion;

        var isTriggerChar = (isDot || (lastChar == '{') || displayClasses);

        if (!displayClasses && !doMetaCompletion && !isTriggerChar) {
            var j = char_pos - 2;
            if (reWS.match(lastChar)) {
                while(j >= 0) {
                    if (!reWS.match(text.charAt(j))) break;
                    j--;
                }
                char_pos = j + 1;
            }
            while (j >= 0) {
                if (!reWord.match(text.charAt(j))) break;
                j--;
            }
            var word = text.substr(j+1, char_pos-1-j);
            switch(word) {
                case "import" if (reWS.match(lastChar)):
                    isTriggerChar = true;
                    displayClasses = true;
                case "package" if (reWS.match(lastChar)):
                    var tmp = hxContext.getPackageFromDS(ds);
                    if (tmp != null) {
                        var ci = new Vscode.CompletionItem(tmp.pack+";");
                        ci.kind = Vscode.CompletionItemKind.File;
                        accept([ci]);
                        return;
                    }
                default:
                    while (j>=0) {
                        if (!reWS.match(text.charAt(j))) break;
                        j--;
                    }
                    lastChar = text.charAt(j);
                    isDot = lastChar == '.';
                    isTriggerChar = (isDot || (lastChar == '{'));
                    if (isTriggerChar) char_pos = j + 1;
            }
        }

        makeCall = isTriggerChar;

        if (makeCall && reWS.match(lastChar)) {
            if ((getTime()-ds.lastModification) < 250) {
                reject([]);
                return;
            }
        }

        if (!makeCall) {
            var items = [];
            // metadata completion
            if (doMetaCompletion) {
                for (data in hxContext.client.metas) {
                    var ci = new Vscode.CompletionItem(data.name);
                    ci.documentation = data.doc;
                    items.push(ci);
                }
            }
            return accept(items);
        }

        var byte_pos = Tool.byte_pos(text, char_pos);

        function make_request() {
            if (cancelToken.isCancellationRequested) {
                reject([]);
                return;
            }

            var cl = client.cmdLine.save()
            .cwd(hxContext.workingDir)
            .define("display-details")
            .hxml(hxContext.buildFile)
            .noOutput();

            if (displayClasses) cl.classes();
            else cl.display(path, byte_pos, displayMode);

            client
            .setContext({fileName:path, line:(position.line+1), column:char_pos})
            .setCancelToken(cancelToken)
            ;

            hxContext.send("completion@2", true, 1, 10).then(
              function(m) {
                  if (cancelToken.isCancellationRequested) reject([]);
                  else {
                      var ret = parse_items(m);
                      if (ret.length==1 && ret[0]==null) {
                          ret = [];
                          hxContext.diagnoseIfAllowed();
                      }
                      accept(ret);
                  }
              },
              function(m:Message) {
                  if (!cancelToken.isCancellationRequested) {
                      if (m.severity==MessageSeverity.Error) {
                          hxContext.applyDiagnostics(m);
                      }
                  }
                  reject([]);
              }
          );
      }

      var ds = hxContext.getDocumentState(path);
      var isDirty = client.isPatchAvailable ? ds.isDirty() : ds.isDirty() || document.isDirty;

      function doRequest() {
          if (cancelToken.isCancellationRequested) {
              reject([]);
              return;
          }
          var isPatchAvailable = client.isPatchAvailable;
          var isServerAvailable = client.isServerAvailable;
          if (isPatchAvailable) {
#if DO_FULL_PATCH
            if (isDirty) {
                hxContext.patchFullDocument(ds).then(
                    function(ds) {make_request();},
                    function(ds) {reject([]);}
                );
            } else {
                make_request();
            }
#else
            changeDebouncer.whenDone(function(){make_request();});
#end
          } else {
              changeDebouncer.whenDone(function() {
                  if (cancelToken.isCancellationRequested) {
                      reject([]);
                      return;
                  }
                  var ps = [];
                  for (ds in hxContext.getDirtyDocuments()) {
                      ds.diagnoseOnSave = false;
                      ps.push(hxContext.saveDocument(ds));
                  }
                  if (ps.length == 0) make_request();
                  else {
                      JSPromise.all(ps).then(
                          function(all) {
                              if (cancelToken.isCancellationRequested) {
                                  reject([]);
                                  return;
                              }
                              make_request();
                          },
                          function(all){reject([]);}
                      );
                  }
              });
          }
      }
      if (!client.isServerAvailable) {
          hxContext.launchServer().then(
              function(port) {doRequest();},
              function(port) {reject([]);}
          );
      } else doRequest();
    });
  }
  public function resolveCompletionItem(item:CompletionItem,
                                        cancelToken:CancellationToken):CompletionItem {
    return item;
  }
}