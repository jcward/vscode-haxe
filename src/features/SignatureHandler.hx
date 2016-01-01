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
      var changeDebouncer = hxContext.changeDebouncer;
      var server = hxContext.server;
      var path:String = document.uri.fsPath;
      
      var lastModifications = hxContext.lastModifications;
      var lm = lastModifications.get(path);
      lastModifications.set(path, null);
      
      var text = document.getText();
      var char_pos = document.offsetAt(position);      
      var lastChar = text.charAt(char_pos-1);
      var makeCall = (lastChar == "(") || (lastChar==",");

      if (!makeCall)
        return new Thenable<SignatureHelp>(function(resolve) {resolve(null);});

      var displayMode = haxe.HaxeCmdLine.DisplayMode.Default; 

      var text = document.getText();
      var byte_pos = Tool.byte_pos(text, char_pos);

      return new Thenable<SignatureHelp>(function(resolve) {
          function make_request() {
            var client = server.make_client();
            var cl = client.cmdLine
            .cwd(hxContext.projectDir)
            .hxml(hxContext.configuration.haxeDefaultBuildFile)
            .noOutput()
            .display(path, byte_pos, displayMode)
            ;
            client.sendAll(function(s, message, err){
                if (err!=null) {
                    err.message.displayAsError();
                    resolve(null);
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
            });
          }
          
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
                document.save().then(function(saved) {
                    if (saved) make_request();
                    else resolve(null);
                });
            } else {
                make_request();
            }
        }          
      }
      
      if (!server.isServerAvailable) {
          var hs = server.make_client();
          var cl = hs.cmdLine.version();
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
          
          hs.sendAll(
            function (s:Socket, message, err) {
                var isPatchAvailable = false;
                var isServerAvailable = true;
                if (err != null) isServerAvailable = false;
                else {
                    server.isServerAvailable = true;
                    if (message.severity==MessageSeverity.Error) {
                        if (message.stderr.length > 1) isPatchAvailable = HaxeClient.isOptionExists(HaxePatcherCmd.name(), message.stderr[1]);
                    }
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
}