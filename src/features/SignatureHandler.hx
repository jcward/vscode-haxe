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

  public function provideSignatureHelp(document:TextDocument,
                                    position:Position,
                                    cancelToken:CancellationToken):Thenable<SignatureHelp>
  {
      var client = hxContext.client;

      var changeDebouncer = hxContext.changeDebouncer;

      var documentState = hxContext.getDocumentState(document.uri.fsPath);
      var path = documentState.path();

      var text = document.getText();
      var char_pos = document.offsetAt(position);
      var text = document.getText();
      var byte_pos = Tool.byte_pos(text, char_pos);

      var displayMode = haxe.HaxeCmdLine.DisplayMode.Default;

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
                      var datas = m.stderr;
                      var sh = new SignatureHelp();
                      sh.activeParameter = 0;
                      sh.activeSignature = 0;
                      var sigs = [];
                      sh.signatures = sigs;
                      if ((datas.length > 2) && reType.match(datas[0])) {
                          var opar = Std.parseInt(reType.matched(2))|0;
                          var index = Std.parseInt(reType.matched(4))|0;
                          if (index >= 0) sh.activeParameter = index;
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