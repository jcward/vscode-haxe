import Vscode;
import haxe.HaxeClient.Message;
import haxe.HaxeClient.MessageSeverity;

import features.CompletionServer;
import features.CompletionHandler;

using haxe.HaxeConfiguration;
import haxe.HaxeConfiguration.HaxeConfigurationObject;

import Tool;
using Tool;

class HaxeContext  {
    public var context(default, null):ExtensionContext;
    public var diagnostics(default, null):DiagnosticCollection;
    public var server(default, null):CompletionServer;
    public var handler(default, null):CompletionHandler;
    public var configuration:HaxeConfigurationObject;

//    public var decoration(default, null):decorator.HaxeDecoration
    public function new(context:ExtensionContext) {
        this.context = context;
        
        platform.Platform.init(js.Node.process.platform);

        configuration = cast Vscode.workspace.getConfiguration('haxe');
        configuration.update(platform.Platform.instance);

        // decoration = new decorator.HaxeDecoration();

        diagnostics =  Vscode.languages.createDiagnosticCollection('haxe');
        context.subscriptions.push(cast diagnostics);

        server = new CompletionServer(this, Vscode.workspace.rootPath);
        handler = new CompletionHandler(this);

        // TODO: server implements Disposable
        context.subscriptions.push(cast this);
    }
    
    function dispose():Dynamic {
        Vscode.window.showInformationMessage("Got dispose!");

        if (server.isServerAvailable && server.isPatchAvailable) {
            var client= server.client;
            client.clear();
            var cl = client.cmdLine;
            for (editor in Vscode.window.visibleTextEditors) {
                cl.beginPatch(editor.document.uri.fsPath).remove();
            }
            client.sendAll(null);
        }
        //TODO: server.kill();
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
}