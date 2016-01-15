package;

import Vscode;
import haxe.HaxeClient;
import haxe.HaxeClient.Message;
import haxe.HaxeClient.MessageSeverity;

import features.CompletionHandler;
import features.DefinitionHandler;
import features.SignatureHandler;

using haxe.HaxeConfiguration;
import haxe.HaxeConfiguration.HaxeConfigurationObject;

import Tool;
using Tool;

import haxe.HaxePatcherCmd.PatcherUnit;

import js.Promise;
import js.node.ChildProcess;

import haxe.Timer;

typedef DocumentState = {isDirty:Bool, lastModification:Float, lastDiagnostic:Float, path:String, document:TextDocument};

class HaxeContext  {
    public static inline function languageID() return "haxe";
    
    public var context(default, null):ExtensionContext;
    public var diagnostics(default, null):DiagnosticCollection;
    public var client(default, null):HaxeClient;
    public var completionHandler(default, null):CompletionHandler;
    public var definitionHandler(default, null):DefinitionHandler;    
    public var signatureHandler(default, null):SignatureHandler;    
    public var configuration:HaxeConfigurationObject;
    public var projectDir(default, null):String;
    var haxeProcess:Null<js.node.child_process.ChildProcess>;

    var checkTimer:Timer;
    var maxLastDiagnoseTime:Float;
    var checkDiagnostic:Bool;

#if DO_FULL_PATCH
#else
    public var changeDebouncer(default, null):Tool.Debouncer<TextDocumentChangeEvent>;
#end

    public var documentsState(default, null):Map<String, DocumentState>;

//    public var decoration(default, null):decorator.HaxeDecoration
    public function new(context:ExtensionContext) {
        this.context = context;
        haxeProcess = null;
        
        configuration = cast Vscode.workspace.getConfiguration(languageID());
        platform.Platform.init(js.Node.process.platform);
        configuration.update(platform.Platform.instance);
        
        diagnostics =  Vscode.languages.createDiagnosticCollection(languageID());
        context.subscriptions.push(cast diagnostics);
        
        documentsState = new Map<String, DocumentState>();

        maxLastDiagnoseTime = 0;
        checkDiagnostic = false;
        
        checkTimer = new Timer(50);
        checkTimer.run = check;
        
        context.subscriptions.push(cast this);
    }
    function check() {
        var time = getTime();
        if (checkDiagnostic) {
            var dlt = time - maxLastDiagnoseTime;
            if (dlt >= configuration.haxeDiagnosticDelay) {
                checkDiagnostic = false;
                if (client.isPatchAvailable) diagnose(1);
                else {
                    var isDirty = false;
                    for (k in documentsState.keys()) {
                        var ds = documentsState.get(k);
                        var document = ds.document;
                        if (ds.isDirty) {
                            isDirty = true;
                            if (document != null) document.save();
                        }
                    }
                    if (!isDirty) diagnose(1);
                }
            }
        }
    }
    public function init() {
        var host = configuration.haxeServerHost;
        var port = configuration.haxeServerPort;
        client = new HaxeClient(host, port);
        
        projectDir = Vscode.workspace.rootPath;

#if DO_FULL_PATCH
#else
        changeDebouncer = new Debouncer<TextDocumentChangeEvent>(250, changePatchs);
        context.subscriptions.push(Vscode.workspace.onDidChangeTextDocument(changePatch));
#end
        // remove the patch if the document is opened, saved, or closed
        context.subscriptions.push(Vscode.workspace.onDidOpenTextDocument(onOpenDocument));    
        context.subscriptions.push(Vscode.workspace.onDidSaveTextDocument(onSaveDocument));
        context.subscriptions.push(Vscode.workspace.onDidCloseTextDocument(onCloseDocument));

        completionHandler = new CompletionHandler(this);
        definitionHandler = new DefinitionHandler(this);
        signatureHandler = new SignatureHandler(this);     
        
        return launchServer();
    }
    public function launchServer() {
        var host = configuration.haxeServerHost;
        var port = configuration.haxeServerPort;

        client.host = host;
        client.port = port;
        
        return new Promise<Int>(function (resolve, reject){
            function onData(data) {
                if (data.isHaxeServer) {
                    configuration.haxeServerPort = port;
                    client.port = port;

                    'Using ${ client.isPatchAvailable ? "--patch" : "non-patching" } completion server at ${configuration.haxeServerHost} on port $port'.displayAsInfo();

                    return resolve(port);
                }
                if (data.isServerAvailable) {
                    port ++;
                    client.patchAvailable(onData);
                } else {
                    if (haxeProcess!=null) haxeProcess.kill("SIGKILL");
                    haxeProcess = ChildProcess.spawn(configuration.haxeExec, ["--wait", '$port']);
                    if (haxeProcess.pid > 0)  {
                        client.patchAvailable(onData);
                    }
                    haxeProcess.on("error", function(err){
                        haxeProcess = null;
                        'Can\'t spawn ${configuration.haxeExec} process\n${err.message}'.displayAsError(); 
                        reject(err);
                    });
                }
            }

            client.patchAvailable(onData);            
        });
    }
    function dispose():Dynamic {
        Vscode.window.showInformationMessage("Got dispose!");
        if (checkTimer!=null) {
            checkTimer.stop();
            checkTimer = null;
        }
        if (client.isServerAvailable && client.isPatchAvailable) {
            client.clear();
            var cl = client.cmdLine;
            for (editor in Vscode.window.visibleTextEditors) {
                var path = editor.document.uri.fsPath;
                documentsState.remove(path);
                cl.beginPatch(path).remove();
            }
            client.sendAll(null);
        }

        if (haxeProcess!=null) {
            haxeProcess.kill("SIGKILL");
            haxeProcess = null;
        }
        
        client = null;

        return null;
    }
   
    public function applyDiagnostics(message:Message) {
        checkDiagnostic = false;
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
            var ds = getDocumentState(url.fsPath);
            ds.lastDiagnostic = getTime();
            if (ds.lastDiagnostic > maxLastDiagnoseTime) maxLastDiagnoseTime = ds.lastDiagnostic;
        }
    }
    inline public function getTime() return Date.now().getTime();    
    public function getDocumentState(path) {
        var ds = documentsState.get(path);
        if (ds != null) return ds;
        var t = getTime();
        ds = {path:path, isDirty:false, lastModification:t, lastDiagnostic:t, document:null};
        documentsState.set(path, ds);
        return ds;
    }
    public function onCloseDocument(document) {
        var path:String = document.uri.fsPath;
        documentsState.remove(path);
        if (client.isPatchAvailable) {
            client.cmdLine.save().beginPatch(path).remove();
            client.sendAll(null, true);
            diagnostics.delete(untyped document.uri);
        }      
    }
    function onOpenDocument(document:TextDocument) {
        var path:String = document.uri.fsPath;
        var ds = getDocumentState(path);
        ds.document = document;
        removeAndDiagnoseDocument(document);
    }
    function onSaveDocument(document) {
        var path:String = document.uri.fsPath;
        var ds = getDocumentState(path);
        ds.isDirty = false;
        ds.lastModification = getTime();
        removeAndDiagnoseDocument(document);        
    }
    function diagnose(trying) {
        var cl = client.cmdLine.save()
        .cwd(projectDir)
        .hxml(configuration.haxeDefaultBuildFile)
        .noOutput()
        ;
        client.sendAll(
            function(s, message, err){
                if (err!=null) {
                    if (trying <= 0) err.message.displayAsError();
                    else {
                        launchServer().then(function (port){
                            diagnose(trying-1);
                        });
                    }
                }
                else applyDiagnostics(message);
            },
            true
        );
    }
    public function removeAndDiagnoseDocument(document) {
        diagnostics.delete(untyped document.uri);
        var path:String = document.uri.fsPath;

        if (client.isPatchAvailable) {
            client.cmdLine.beginPatch(path).remove();
        }
        diagnose(1);
    }   
#if DO_FULL_PATCH
#else
    function changePatchs(events:Array<TextDocumentChangeEvent>) {        
        var cl = client.cmdLine.save()
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
            
            if (document.languageId != languageID()) continue;
            
            var text = document.getText();
            
            var patcher = cl.beginPatch(path);
                            
            if (!client.isServerAvailable) {
                if (done.get(path)) continue;
                done.set(path, true);
                
                var bl = text.byteLength();

                if (document.isDirty) patcher.delete(0, -1).insert(0, bl, text);
                else patcher.remove();
                
                //cl.display(path, bl, haxe.HaxeCmdLine.DisplayMode.Position);
                changed = true;
            } else if (client.isPatchAvailable) {
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
            client.sendAll(
                function (s, message, error) {
                    if (error==null) applyDiagnostics(message);
                    checkDiagnostic = true;
                },
                true
            );
        } else checkDiagnostic = true;
    }
    function changePatch(event:TextDocumentChangeEvent) {
        var document = event.document;
        var path:String = document.uri.fsPath;
        var ds = getDocumentState(path);
        if (event.contentChanges.length==0) {
            ds.isDirty = false;
            return;
        }
        ds.isDirty = true;
        ds.lastModification = getTime();
        ds.document = document;
        changeDebouncer.debounce(event);
    }
#end
}