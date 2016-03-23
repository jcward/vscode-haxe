package features;

import Vscode;

import HaxeContext;
using HaxeContext;

import Tool;
using Tool;

import haxe.HaxePatcherCmd;
import haxe.HaxePatcherCmd.PatcherUnit;
import haxe.HaxeClient;
import haxe.HaxeClient.MessageSeverity;
import haxe.HaxeClient.Info as HxInfo;

using features.SignatureHandler.FunctionDecoder;

import js.Promise as JSPromise;

class FunctionDecoder {
    public static function asFunctionArgs(data:String) {
        var l = data.length;
        var args = [];
        var i = 0;
        var sp = 0;
        var pc = '';
        var consLevel = 0;
        var parLevel = 0;
        var argName = '';
        var canParseArgName = true;
        while (i < l) {
            var c = data.charAt(i);
            switch (c) {
                case ':':
                    if (canParseArgName) {
                        canParseArgName = false;
                        argName = data.substring(sp, i-1);
                        sp = i + 2;
                    }
                case '(': parLevel++;
                case ')': parLevel--;
                case '<': consLevel++;
                case '>':
                    if (pc=='-') {
                        if ((parLevel==0) && (consLevel==0)) {
                            args.push({name:argName, type:data.substring(sp, i-2)});
                            canParseArgName = true;
                            sp = i+2;
                        }
                    } else {
                        consLevel--;
                    }

            }
            pc = c;
            i++;
        }
        args.push({name:'', type:data.substr(sp)});
        return args;
    }
    static var reFirstId = ~/[_a-zA-Z]/;
    static var reLastId = ~/[0-9_a-zA-Z]/;
    static var reWS = ~/[\r\n\t\s]/;
    public static function findNameAndParameterPlace(data:String, from:Int) {
        var argCount = 0;
        var parLevel = 0;
        var bkLevel = 0;
        var strSep = '"';
        var inStr = false;
        while (from >= 0) {
            var c = data.charAt(from--);
            if (inStr) {
                if (c == strSep) {
                    var slCnt = 0;
                    var i = from;
                    while (i >= 0) {
                        if (data.charAt(i) == "\\") slCnt++;
                        else break;
                        i--;
                    }
                    if ((slCnt & 1) == 0) inStr = false;
                    else from = i;
                }
            } else {
                switch(c) {
                    case '(':
                        parLevel++;
                        if (parLevel == 1) {
                            var pp = from + 1;
                            while (from >= 0) {
                                c = data.charAt(from);
                                if (!reWS.match(c)) break;
                                from --;
                            }
                            if (from < 0) break;
                            if (!reLastId.match(c)) break;
                            from --;
                            while (from >= 0) {
                                c = data.charAt(from);
                                if (!reLastId.match(c)) break;
                                from --;
                            }
                            if (reFirstId.match(data.charAt(from + 1))) {
                                return {start:pp + 1, cnt:argCount};
                            }
                        }
                    case '[':
                        bkLevel++;
                        if (bkLevel != 0) break;
                    case ')':
                        parLevel--;
                    case ']':
                        bkLevel--;
                    case ',' if (bkLevel==0 && parLevel==0):
                        argCount++;
                    case "'" | '"':
                        inStr = true;
                        strSep = c;
                }
            }
        }
        return null;
    }
}

class SignatureHandler implements SignatureHelpProvider
{
  var hxContext:HaxeContext;

  public function new(hxContext:HaxeContext):Void
  {
      this.hxContext = hxContext;

      var context = hxContext.context;

      var disposable = Vscode.languages.registerSignatureHelpProvider(HaxeContext.languageID(), this, '(', ',');
      context.subscriptions.push(disposable);
  }

  static var reType = ~/<type(\s+opar='(\d+)')?(\s+index='(\d+)')?>/;
  static var reGT = ~/&gt;/g;
  static var reLT = ~/&lt;/g;
  static var reFatalError = ~/\s*@fatalError(\s+(.*))?/;
  public function provideSignatureHelp(document:TextDocument,
                                    position:Position,
                                    cancelToken:CancellationToken):Thenable<SignatureHelp>
  {
      var client = hxContext.client;

      var changeDebouncer = hxContext.changeDebouncer;

      var ds = hxContext.getDocumentState(document.uri.fsPath, document);
      var path = ds.path();

      var text = document.getText();
      var char_pos = document.offsetAt(position);
      var text = document.getText();
      var lastChar = text.charAt(char_pos-1);
      var byte_pos = 0;

      var displayMode = haxe.HaxeCmdLine.DisplayMode.Default;

      var activeParameter = 0;

      if (lastChar == ",") {
          text = text.substr(0, char_pos) + "VSCTool.fatalError()." + text.substr(char_pos);
          ds.text = text;
          ds.modified();
          byte_pos = Tool.byte_pos(text, char_pos + 21);
//          displayMode = haxe.HaxeCmdLine.DisplayMode.
      } else {
          byte_pos = Tool.byte_pos(text, char_pos);
      }

      return new Thenable<SignatureHelp>(function(accept, reject) {
          if (cancelToken.isCancellationRequested) {
              reject(null);
          }

          function make_request() {
              var cl = client.cmdLine.save()
              .cwd(hxContext.workingDir)
              .hxml(hxContext.buildFile)
              .noOutput()
              .display(path, byte_pos, displayMode)
              ;
              client
                .setContext({fileName:path, line:(position.line+1), column:char_pos})
                .setCancelToken(cancelToken)
              ;
              hxContext.send(null, true, 1).then(
                  function(m:Message) {
                      hxContext.diagnostics.clear();

                      var datas = m.stderr;
                      var sh = new SignatureHelp();
                      sh.activeParameter = activeParameter;
                      sh.activeSignature = 0;
                      var sigs = [];
                      sh.signatures = sigs;
                      if ((datas.length > 2) && reType.match(datas[0])) {
                          var opar = Std.parseInt(reType.matched(2))|0;
                          var index = Std.parseInt(reType.matched(4))|0;
                          if (index > 0) sh.activeParameter = index;
                          datas.shift();
                          datas.pop();
                          datas.pop();
                          for (data in datas) {
                              data = reGT.replace(data, ">");
                              data = reLT.replace(data, "<");
                              var args = data.asFunctionArgs();
                              var ret = args.pop();
                              var params = args.map(function(v){
                                  return v.name + ":" + v.type;
                              });
                              data = "(" + params.join(", ") + "):" + ret.type;
                              var si = new SignatureInformation(data);
                              sigs.push(si);
                              var pis = args.map(function(v){
                                  return new ParameterInformation(v.name, v.type);
                              });
                              si.parameters = pis;
                          }
                      }
                      accept(sh);
                  },
                  function(m:Message) {
                      if (m.error != null) m.error.message.displayAsError();
                      else {
                          if (lastChar == ",") {
                              hxContext.diagnostics.clear();
                              var fnInfo = null;
                              for (i in m.infos) {
                                  if (reFatalError.match(i.message)) {
                                      fnInfo = text.findNameAndParameterPlace(char_pos - 1);
                                      break;
                                  }
                              }
                              if (fnInfo != null) {
                                  activeParameter = fnInfo.cnt;
                                  byte_pos = Tool.byte_pos(text, fnInfo.start);
                                  make_request();
                                  return;
                              }
                          }
                      }
                      reject(null);
                  }
            );
      }

      var ds = hxContext.getDocumentState(path);
      var isDirty = client.isPatchAvailable ? ds.isDirty() : ds.isDirty() || document.isDirty;

      function doRequest() {
          if (cancelToken.isCancellationRequested) {
              reject(null);
              return;
          }
          var isPatchAvailable = client.isPatchAvailable;
          var isServerAvailable = client.isServerAvailable;
          if (isPatchAvailable) {
#if DO_FULL_PATCH
            if (isDirty) {
                hxContext.patchFullDocument(ds).then(
                    function(ds) {make_request();},
                    function(ds) {reject(null);}
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
                      reject(null);
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
                                  reject(null);
                                  return;
                              }
                              make_request();
                          },
                          function(all){reject(null);}
                      );
                  }
              });
          }
      }
      if (!client.isServerAvailable) {
          hxContext.launchServer().then(
              function(port) {doRequest();},
              function(port) {reject(null);}
          );
      } else doRequest();
    });
  }
}