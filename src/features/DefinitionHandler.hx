package features;

import Vscode;

import HaxeContext;

import Tool;
using Tool;

import haxe.HaxePatcherCmd;
import haxe.HaxePatcherCmd.PatcherUnit;
import haxe.HaxeClient;
import haxe.HaxeClient.MessageSeverity;
import haxe.HaxeClient.Info as HxInfo;

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
      var path:String = document.uri.fsPath;
      
      var lastModifications = hxContext.lastModifications;   
      var lm = lastModifications.get(path);
      lastModifications.set(path, null);
      
      var makeCall = false;
      
      var displayMode = haxe.HaxeCmdLine.DisplayMode.Position;
      
      if (lm==null) makeCall = true;
      else {
        var ct = Date.now().getTime();
        var dlt = ct - lm;
        if (dlt > 200) {
            makeCall = true;
        }
      }
      
      if (!makeCall)
        return new Thenable<Definition>( function(resolve) {resolve(null);});

      var text = document.getText();
      var range = document.getWordRangeAtPosition(position);
      position = range.end;
      var char_pos = document.offsetAt(position) + 1;
      var byte_pos = Tool.byte_pos(text, char_pos);
 
      return new Thenable<Definition>( function(resolve:Definition->Void) {
          var trying = 1;
          function make_request() {
            var cl = client.cmdLine.save()
            .cwd(hxContext.projectDir)
            .hxml(hxContext.configuration.haxeDefaultBuildFile)
            .noOutput()
            .display(path, byte_pos, displayMode)
            ;
            var step = 1;
            function parse(s, message, err:js.Error) {
                if (err!=null) {
                    if (trying <= 0) {
                        err.message.displayAsError();
                        resolve(null);
                    } else {
                        trying--;
                        hxContext.launchServer().then(function(port){
                            make_request();
                        });
                    }
                } else {
                    if (message.severity==MessageSeverity.Error) {
                        hxContext.applyDiagnostics(message);
                        resolve(null);
                    }
                    else {
                        var datas = message.stderr;
                        var defs = [];
                        if ((datas.length >= 2) && datas[0]=="<list>") {
                           datas.shift();
                           datas.pop();
                           if ((datas.length==0) && (step == 0)) {
                               step ++;
                               cl
                               .cwd(hxContext.projectDir)
                               .hxml(hxContext.configuration.haxeDefaultBuildFile)
                               .noOutput()
                               .display(path, byte_pos, haxe.HaxeCmdLine.DisplayMode.Resolve(document.getText(range)))
                               ;
                               client.sendAll(parse);
                           } else                        
                            for (data in datas) {
                                if (!rePos.match(data)) continue;
                                data = rePos.matched(1);
                                var i = HxInfo.decode(data, hxContext.projectDir);
                                if (i == null) continue;
                                var info = i.info;
                                defs.push(new Location(Vscode.Uri.file(info.fileName), info.toVSCRange()));
                            } 
                        }
                        resolve(cast defs);
                    }
                }
            }
            client.sendAll(parse, true);
          }

          var isDirty = document.isDirty;

      function doRequest() {
        var isPatchAvailable = client.isPatchAvailable;
        var isServerAvailable = client.isServerAvailable;

        if (isPatchAvailable) {
#if DO_FULL_PATCH
            if (isDirty) {
                client.cmdLine.beginPatch(path).delete(0,-1).insert(0, document.getText());
                make_request();
            } else {
                make_request();
            }
#else
            changeDebouncer.whenDone(make_request);
#end
        } else {
            if (isDirty && isServerAvailable) {
                document.save().then(function(saved) {
                    if (saved) make_request();
                    else resolve(null);
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
                client.isPatchAvailable=isPatchAvailable;
                doRequest();
            },
            true             
          );
      } else doRequest();
    });
  }
}