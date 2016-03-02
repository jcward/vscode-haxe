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

import js.Promise as JSPromise;
import js.node.Path;

class DefinitionHandler implements DefinitionProvider
{
  var hxContext:HaxeContext;

  public function new(hxContext:HaxeContext):Void
  {
      this.hxContext = hxContext;

      var context = hxContext.context;

      var disposable = Vscode.languages.registerDefinitionProvider(HaxeContext.languageID(), this);
      context.subscriptions.push(disposable);
  }

  static var rePos = ~/[^<]*<pos>(.+)<\/pos>.*/;

  public function provideDefinition(document:TextDocument,
                                    position:Position,
                                    cancelToken:CancellationToken):Thenable<Definition>
  {
      var changeDebouncer = hxContext.changeDebouncer;

      var client = hxContext.client;

      var documentState = hxContext.getDocumentState(document.uri.fsPath);
      var path = documentState.path();
      var displayMode = haxe.HaxeCmdLine.DisplayMode.Position;

      var text = document.getText();
      var range = document.getWordRangeAtPosition(position);
      position = range.end;

      var char_pos = document.offsetAt(position) + 1;
      var byte_pos = Tool.byte_pos(text, char_pos);

      return new Thenable<Definition>(function(accept, reject) {
          if (cancelToken.isCancellationRequested) {
              reject(null);
          }

          var trying = 1;
          function make_request() {
            var cl = client.cmdLine.save()
                .cwd(hxContext.workingDir)
                .hxml(hxContext.buildFile)
                .noOutput()
                .display(path, byte_pos, displayMode)
                ;

            //var step = 1;

            function parse(m:Message) {
                if (cancelToken.isCancellationRequested) return reject(null);

                var datas = m.stderr;
                var defs = [];
                if ((datas.length >= 2) && datas[0]=="<list>") {
                    datas.shift();
                    datas.pop();
                    /*
                    if ((datas.length==0) && (step == 0)) {
                        step ++;
                        cl
                        .cwd(hxContext.projectDir)
                        .hxml(hxContext.configuration.haxeDefaultBuildFile)
                        .noOutput()
                        .display(path, byte_pos, haxe.HaxeCmdLine.DisplayMode.accept(document.getText(range)))
                        ;
                        client.sendAll(parse);
                    } else {
                    */
                        for (data in datas) {
                            if (!rePos.match(data)) continue;
                            data = rePos.matched(1);
                            var i = HxInfo.decode(data, hxContext.projectDir);
                            if (i == null) continue;
                            var info = i.info;
                            var fileName = hxContext.tmpToReal(hxContext.insensitiveToSensitive(info.fileName));
                            defs.push(new Location(Vscode.Uri.file(fileName), info.toVSCRange()));
                        }
                    //}
                }
                return accept(cast defs);
            }
            client
                .setContext({fileName:path, line:(position.line+1), column:char_pos})
                .setCancelToken(cancelToken)
            ;
            hxContext.send(null, true, 1).then(
                parse,
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