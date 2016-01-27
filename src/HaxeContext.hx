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
import js.node.Path;

import haxe.Timer;

using HaxeContext;

typedef DocumentState = {lastModification:Float, lastSave:Float, saveStart:Float, lastDiagnostic:Float, path:String, document:TextDocument, diagnoseOnSave:Bool};

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
    var diagnosticStartTime:Float;
    var diagnoseOnSave:Bool = true;

    var diagnosticRunning(get, null):Bool;
    inline function get_diagnosticRunning() return diagnosticStartTime > maxLastDiagnoseTime;

    public static inline function isDirty(ds:DocumentState) return ds.lastModification > ds.lastSave;
    public static inline function isSaving(ds:DocumentState) return ds.saveStart > ds.lastSave;
    public static inline function needDiagnostic(ds:DocumentState) return ds.lastSave > ds.lastDiagnostic;

#if DO_FULL_PATCH
#else
    public var changeDebouncer(default, null):Tool.Debouncer<TextDocumentChangeEvent>;
#end

    public var documentsState(default, null):Map<String, DocumentState>;

    public function new(context:ExtensionContext) {
        this.context = context;
        haxeProcess = null;

        configuration = cast Vscode.workspace.getConfiguration(languageID());
        platform.Platform.init(js.Node.process.platform);
        configuration.update(platform.Platform.instance);

        diagnostics =  Vscode.languages.createDiagnosticCollection(languageID());
        context.subscriptions.push(cast diagnostics);

        documentsState = new Map<String, DocumentState>();

        diagnosticStartTime = 0;
        maxLastDiagnoseTime = 1;
        checkDiagnostic = false;

        checkTimer = new Timer(50);
        checkTimer.run = check;

        context.subscriptions.push(cast this);
    }
    function check() {
        var time = getTime();
        if (checkDiagnostic && !diagnosticRunning) {
            var dlt = time - maxLastDiagnoseTime;
            if (dlt >= configuration.haxeDiagnosticDelay) {
                if (client.isPatchAvailable) {
                    checkDiagnostic = false;
                    diagnose(1);
                } else {
                    var isDirty = false;
                    var needDiagnose = false;
                    for (ds in documentsState.iterator()) {
                        var document = ds.document;
                        if (document == null) continue;
                        if (ds.isDirty()) {
                            if (!ds.isSaving()) {
                                isDirty = true;
                                ds.saveStart = getTime();
                                ds.diagnoseOnSave = false;
                                document.save();
                            }
                        } else {
                            needDiagnose = needDiagnose || ds.needDiagnostic();
                        }
                    }
                    if (!isDirty) {
                        checkDiagnostic = false;
                        if (needDiagnose) diagnose(1);
                    }
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
        for (ds in documentsState.iterator()) {
            if (ds.document == null) continue;
            diagnostics.delete(ds.document.uri);
        }

        var all = new Map<String, Null<Array<Diagnostic>>>();

        var t = getTime();

        for (info in message.infos) {
            var diags = all.get(info.fileName);
            if (diags == null) {
                diags = [];
                all.set(info.fileName, diags);
            }
            var diag = new Diagnostic(info.toVSCRange(), info.message, message.severity.toVSCSeverity());
            diags.push(diag);
        }

        var entries:Array<Dynamic> = [];
        for (fileName in all.keys()) {
            var diags = all.get(fileName);
            fileName = Path.normalize(fileName);
            var url = Uri.file(fileName);
            if (diags==null) {
                diagnostics.set(url, []);
                continue;
            }
            diagnostics.set(url, diags);
            var ds = getDocumentState(url.fsPath);
            ds.lastDiagnostic = t;
        }
        if (t > maxLastDiagnoseTime) maxLastDiagnoseTime = t;
    }

    inline public function getTime() return Date.now().getTime();
    public function getDocumentState(path) {
        var ds = documentsState.get(path);
        if (ds != null) return ds;
        var t = getTime();
        ds = {path:path, lastModification:0, lastSave:t, saveStart:0, lastDiagnostic:0, document:null, diagnoseOnSave:diagnoseOnSave};
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
        ds.saveStart = ds.lastDiagnostic = 0;
        ds.lastSave = ds.lastModification = getTime();
        removeAndDiagnoseDocument(document);
    }
    function onSaveDocument(document) {
        var path:String = document.uri.fsPath;
        var ds = getDocumentState(path);
        ds.lastSave = getTime();
        if (ds.diagnoseOnSave) removeAndDiagnoseDocument(document);
        else ds.diagnoseOnSave = diagnoseOnSave;
    }
    function diagnose(trying) {
        diagnosticStartTime = getTime();

        var cl = client.cmdLine.save()
        .cwd(projectDir)
        .hxml(configuration.haxeDefaultBuildFile)
        .noOutput()
        ;

        client.sendAll(
            function(s, message, err){
                if (err!=null) {
                    if (trying <= 0) {
                        err.message.displayAsError();
                        maxLastDiagnoseTime = getTime();
                    }
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
    static var reWS = ~/[\s\t\r\n]/;
#if DO_FULL_PATCH
#else
    function changePatchs(events:Array<TextDocumentChangeEvent>) {
        if (events.length == 0) return;

        var editor = Vscode.window.activeTextEditor;

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

                var pos = 0;
                if (editor != null) {
                    if (editor.document == document) pos = Tool.byte_pos(text, document.offsetAt(editor.selection.active));
                    else pos = text.byteLength();
                } else {
                    pos = text.byteLength();
                }

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
        } else {
            var document = editor.document;
            if (document.languageId != languageID()) return;

            var lastEvent = events[events.length -1];
            var changes = lastEvent.contentChanges;
            if (changes.length == 0) return;
            var lastChange = changes[changes.length - 1];

            var cursor = editor.selection.active;
            var line = document.lineAt(cursor);

            var text = line.text;
            var char_pos = cursor.character - 1;
            var len = text.length;

            var insertText = lastChange.text;
            var lastLen = insertText.length;
            if (lastLen > 0) {
                if (reWS.match(insertText.charAt(lastLen-1))) {
                    var ei = char_pos + 1;
                    while (ei < len) {
                        if (!reWS.match(text.charAt(ei))) break;
                        ei++;
                    }
                    checkDiagnostic = (ei < len);
                } else {
                    checkDiagnostic = true;
                }
                return;
            }
            if (lastChange.rangeLength > 0) {
                var ei = char_pos;
                while (ei < len) {
                        if (!reWS.match(text.charAt(ei))) break;
                        ei++;
                }
                checkDiagnostic = (ei < len);
                return;
            }
        }
    }
    function changePatch(event:TextDocumentChangeEvent) {
        var document = event.document;
        if (document.languageId != languageID()) return;


        var path:String = document.uri.fsPath;
        var ds = getDocumentState(path);
        if (event.contentChanges.length == 0) {
            return;
        }

        checkDiagnostic = false;

        ds.lastModification = getTime();
        ds.document = document;
        changeDebouncer.debounce(event);
    }
#end
}