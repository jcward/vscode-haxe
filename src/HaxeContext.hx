package;

import Vscode;
import haxe.HaxeClient;
import haxe.HaxeClient.Message;
import haxe.HaxeClient.MessageSeverity;

import features.CompletionServer;
import features.CompletionHandler;
import features.DefinitionHandler;

using haxe.HaxeConfiguration;
import haxe.HaxeConfiguration.HaxeConfigurationObject;

import Tool;
using Tool;

import haxe.HaxePatcherCmd.PatcherUnit;

import js.Promise;
import js.node.ChildProcess;

class HaxeContext  {
    public static inline function languageID() return "haxe";
    
    public var context(default, null):ExtensionContext;
    public var diagnostics(default, null):DiagnosticCollection;
    public var server(default, null):CompletionServer;
    public var completionHandler(default, null):CompletionHandler;
    public var definitionHandler(default, null):DefinitionHandler;    
    public var configuration:HaxeConfigurationObject;
    public var projectDir(default, null):String;
    var haxeProcess:Null<js.node.child_process.ChildProcess>;

#if DO_FULL_PATCH
#else
    public var changeDebouncer(default, null):Tool.Debouncer<TextDocumentChangeEvent>;
#end

    public var lastModifications(default, null):Map<String, Float>;


//    public var decoration(default, null):decorator.HaxeDecoration
    public function new(context:ExtensionContext) {
        this.context = context;
        haxeProcess = null;
        
        configuration = cast Vscode.workspace.getConfiguration(languageID());
        platform.Platform.init(js.Node.process.platform);
        configuration.update(platform.Platform.instance);
        
        diagnostics =  Vscode.languages.createDiagnosticCollection(languageID());
        context.subscriptions.push(cast diagnostics);
        
        lastModifications = new Map<String, Float>();

        context.subscriptions.push(cast this);
    }
    public function init() {
        return launchServer().then(function (port) {
            configuration.haxeServerPort = port;
             // decoration = new decorator.HaxeDecoration();

            projectDir = Vscode.workspace.rootPath;

#if DO_FULL_PATCH
#else
            changeDebouncer = new Debouncer<TextDocumentChangeEvent>(250, changePatchs);
            context.subscriptions.push(Vscode.workspace.onDidChangeTextDocument(changePatch));
#end

            // remove the patch if the document is opened, saved, or closed
            context.subscriptions.push(Vscode.workspace.onDidOpenTextDocument(removeAndDiagnoseDocument));    
            context.subscriptions.push(Vscode.workspace.onDidSaveTextDocument(removeAndDiagnoseDocument));
            context.subscriptions.push(Vscode.workspace.onDidCloseTextDocument(onCloseDocument));

            server = new CompletionServer(this);
            completionHandler = new CompletionHandler(this);
            definitionHandler = new DefinitionHandler(this);     
            
            'Using ${ server.isPatchAvailable ? "--patch" : "non-patching" } completion server at ${configuration.haxeServerHost} on port $port'.displayAsInfo();

            return port;     
      });
    }
    function launchServer() {
        var host = configuration.haxeServerHost;
        var port = configuration.haxeServerPort;
        var client = new HaxeClient(host, port);
        return new Promise<Int>(function (resolve, reject){
            function onData(data) {
                if (data.isHaxeServer) return resolve(port);
                if (data.isServerAvailable) {
                    port ++;
                    client.isPatchAvailable(onData);
                } else {
                    if (haxeProcess!=null) haxeProcess.kill("SIGKILL");
                    haxeProcess = ChildProcess.spawn(configuration.haxeExec, ["--wait", '$port']);
                    if (haxeProcess.pid > 0)  {
                        configuration.haxeServerPort = port;
                        client.isPatchAvailable(onData);
                    }
                    haxeProcess.on("error", function(err){
                        haxeProcess = null;
                        'Can\'t spawn ${configuration.haxeExec} process'.displayAsError(); 
                        reject(err);
                    });
                }
            }

            client.isPatchAvailable(onData);            
        });
    }
    function dispose():Dynamic {
        Vscode.window.showInformationMessage("Got dispose!");

        if (server.isServerAvailable && server.isPatchAvailable) {
            var client= server.client;
            client.clear();
            var cl = client.cmdLine;
            for (editor in Vscode.window.visibleTextEditors) {
                var path = editor.document.uri.fsPath;
                lastModifications.remove(path);
                cl.beginPatch(editor.document.uri.fsPath).remove();
            }
            client.sendAll(null);
        }
        if (haxeProcess!=null) {
            haxeProcess.kill("SIGKILL");
            haxeProcess = null;
        }
        return null;
    }
   
    public function applyDiagnostics(message:Message) {
        //diagnostic.clear();
        
        var all = new Map<String, Null<Array<Diagnostic>>>();            
        for (info in message.infos) {
            var diags = all.get(info.fileName);
            if (diags == null) {
                diags = [];
                all.set(info.fileName, diags);
            }
            var diag = new Diagnostic(info.toVSCRange(), info.message, message.severity.toVSCSeverity());
            diags.push(diag);
        }
        var ps = platform.Platform.instance.pathSeparator;
        var entries:Array<Dynamic> = [];
        for (fileName in all.keys()) {
            var diags = all.get(fileName);
            var tmp = fileName.split(ps);
            var paths = [];
            for (s in tmp) {
                switch(s) {
                    case ".": continue;
                    case "..": paths.pop();
                    default: paths.push(s);
                }
            }
            fileName = paths.join(ps);
            var url = Uri.file(fileName);
            if (diags==null) {
                diagnostics.set(url, []);
                continue;
            }
            diagnostics.set(url, diags);
        }
    }
/*
    static function applyDecorations(editor, infos:Array<haxe.Info>, isError:Bool) {
        if (editor==null) return;
        var document = editor.document;
        var path = document.uri.fsPath;
        var lineErrors = [];
        var charErrors = [];
        for (info in infos) {
            if (info.fileName == path) {
                var re = info.toVSCRange();
                var r = info.range;
                if (r.isLineRange) {
                    if (isError) lineErrors.push({hoverMessage:info.message, range:re});
                } else {
                    if (isError) charErrors.push({hoverMessage:info.message, range:re});
                }
            }
        }
        editor.setDecorations(decoration.errorLineDecoration, lineErrors);
        editor.setDecorations(decoration.errorCharDecoration, charErrors);
    }
*/
//    function applyDecorations(message:Message) {
//        applyDecorations(Vscode.window.activeTextEditor, message.infos, message.severity == Error);
//    }

  public function onCloseDocument(document) {
      var path:String = document.uri.fsPath;
      lastModifications.remove(path);
      if (server.isPatchAvailable) {
          var client = server.make_client();
          client.cmdLine.beginPatch(path).remove();
          client.sendAll(null);
          diagnostics.delete(untyped document.uri);
      }      
  }
  public function removeAndDiagnoseDocument(document) {
      diagnostics.delete(untyped document.uri);
      var path:String = document.uri.fsPath;
      lastModifications.remove(path);
      var client = server.make_client();
      var cl = client.cmdLine
        .cwd(projectDir)
        .hxml(configuration.haxeDefaultBuildFile)
        .noOutput()
      ;
      if (server.isPatchAvailable) {
          cl.beginPatch(path).remove();
      }
      client.sendAll(function(s, message, err){
          if (err!=null) err.message.displayAsError();
          else applyDiagnostics(message);
      });
  }   
#if DO_FULL_PATCH
#else
    function changePatchs(events:Array<TextDocumentChangeEvent>) {
        var client = server.make_client();
        
        var cl = client.cmdLine
            .cwd(projectDir)
            // patch should only patch no validate document
            // so disable args that can trigger the validation
            //.hxml(hxContext.configuration.haxeDefaultBuildFile)
            //.noOutput()
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
        
        if (changed) {
            client.sendAll(function (s, message, error) {
                if (error==null) applyDiagnostics(message);        
            });
        }
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
}