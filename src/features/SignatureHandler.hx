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

using features.SignatureHandler.FunctionDecoder;

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
#if DO_FULL_PATCH
#else
      var changeDebouncer = hxContext.changeDebouncer;
#end      
      var path:String = document.uri.fsPath;
      
      var text = document.getText();
      var char_pos = document.offsetAt(position);          
      var text = document.getText();
      var byte_pos = Tool.byte_pos(text, char_pos);

      var displayMode = haxe.HaxeCmdLine.DisplayMode.Default; 

      return new Thenable<SignatureHelp>(function(resolve) {
          var trying = 1;
          function make_request() {
            var cl = client.cmdLine.save()
            .cwd(hxContext.projectDir)
            .hxml(hxContext.configuration.haxeDefaultBuildFile)
            .noOutput()
            .display(path, byte_pos, displayMode)
            ;
            client.sendAll(
                function(s, message, err){
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
                                var si = new SignatureInformation(data);
                                sigs.push(si);
                                var pis = args.map(function (v){
                                    return new ParameterInformation(v.name, v.type);         
                                });
                                si.parameters = pis;
                            } 
                            }
                            resolve(sh);
                        }
                    }
                },
                true
            );
          }
          
          var ds = hxContext.getDocumentState(path);
          var isDirty = document.isDirty || ds.isDirty;

      function doRequest() {
        var isServerAvailable = client.isServerAvailable;
        var isPatchAvailable = client.isPatchAvailable;

        if (isPatchAvailable) {
#if DO_FULL_PATCH
            if (isDirty) {
                hxContext.patchFullDocument(ds);
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