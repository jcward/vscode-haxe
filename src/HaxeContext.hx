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
import Tool.getTime;
using Tool;

import haxe.HaxePatcherCmd.PatcherUnit;

import js.Promise;
import js.node.ChildProcess;
import js.node.Path;
import js.node.Fs;

import haxe.Timer;

using HaxeContext;

typedef DocumentState = {saveStartAt:Float, lastSave:Float, lastModification:Float, realPath:String, document:TextDocument, diagnoseOnSave:Bool, tmpPath:String};

typedef PendingFile = {ds:DocumentState, accept:DocumentState->Void, reject:DocumentState->Void, lastModification:Float};

class HaxeContext  {
    public static inline function languageID() return "haxe";
    
    public var context(default, null):ExtensionContext;
    public var diagnostics(default, null):DiagnosticCollection;
    public var client(default, null):HaxeClient;
    public var completionHandler(default, null):CompletionHandler;
    public var definitionHandler(default, null):DefinitionHandler;    
    public var signatureHandler(default, null):SignatureHandler;    
    public var configuration(default, null):HaxeConfigurationObject;
    public var projectDir(default, null):String;

    public var useTmpDir:Bool;
    public var tmpDir(default, null):String;
    public var tmpProjectDir(default, null):String;
    
    public var tmpToRealMap:Map<String, String>;
    public var insensitiveToSensitiveMap:Map<String, String>;
    
    public var realWorkingDir(get, null):String;
    public inline function get_realWorkingDir() return projectDir;
    
    public var workingDir(get, null):String;
    public function get_workingDir() return {
        if (useTmpDir && configuration.haxeUseTmpAsWorkingDirectory) tmpProjectDir;
        else realWorkingDir;
    }
    public var realBuildFile(get, null):String;
    inline function get_realBuildFile() return configuration.haxeDefaultBuildFile;

    public var internalBuildFile(get, null):String;
    inline function get_internalBuildFile() return configuration.haxeVSCodeBuildFile;
  
    public var buildFile(get, null):String;
    function get_buildFile() return {
        if (useInternalBuildFile) internalBuildFile;
        else realBuildFile;
    }
        
    public var buildFileWithPath(get, null):String;
    public function  get_buildFileWithPath() return Path.join(workingDir, buildFile);

    public var realBuildFileWithPath(get, null):String;
    public function  get_realBuildFileWithPath() return Path.join(realWorkingDir, realBuildFile);

    public var internalBuildFileWithPath(get, null):String;
    public function  get_internalBuildFileWithPath() return Path.join(workingDir, internalBuildFile);
 
    public var useInternalBuildFile:Bool;
   
    public var classPaths(default, null):Array<String>;
   
    var haxeProcess:Null<js.node.child_process.ChildProcess>;

    var checkTimer:Timer;
    var lastDiagnostic:Float;
    var lastModification:Float;
    var checkForDiagnostic:Bool;

    var pendingSaves:Map<String, PendingFile>;

//#if DO_FULL_PATCH
//#else
    public var changeDebouncer(default, null):Tool.Debouncer<TextDocumentChangeEvent>;
//#end

    public var documentsState(default, null):Map<String, DocumentState>;
    
    
    public static inline function isDirty(ds:DocumentState) return (ds.document != null) && (ds.lastModification > ds.lastSave);
    public static inline function isSaving(ds:DocumentState) return (ds.lastSave < ds.saveStartAt); 
    public static inline function saved(ds:DocumentState) ds.lastSave = getTime();
    public static inline function dirty(ds:DocumentState) ds.lastSave = ds.lastModification - 1;
    public static inline function modified(ds:DocumentState) ds.lastModification = getTime();
    public static inline function isHaxeDocument(document:TextDocument) return (document.languageId == languageID());    
    public static inline function path(ds:DocumentState) return if (ds.tmpPath == null) ds.realPath; else ds.tmpPath;

    public function canRunDiagnostic(ds:DocumentState) return (ds.diagnoseOnSave && (ds.lastSave >= lastDiagnostic));
    
    public function tmpToReal(fileName:String) {
        var nfile = fileName.normalize();
        var tmp = tmpToRealMap.get(nfile);
        if (tmp != null) return tmp;
        if (platform.Platform.instance.isWin) {
            tmp = insensitiveToSensitiveMap.get(nfile);
            if (tmp != null) return tmp;
        }
        return fileName;
    }
    public function insensitiveToSensitive(file:String) {
        if (!platform.Platform.instance.isWin) return file;
        var nfile = file.normalize();
        var tmp = insensitiveToSensitiveMap.get(nfile);
        if (tmp != null) return tmp;
        var paths = nfile.split(Path.sep);
        var fileName = paths.pop();
        var path = paths.join(Path.sep);
        var paths = [];
        try {
            paths = Fs.readdirSync(path);
        } catch (e:Dynamic) {
            if (configuration.haxeUseTmpAsWorkingDirectory) {
                paths = path.split(workingDir);
                paths.shift();
                paths = [realWorkingDir, ".."].concat(paths);
                path = paths.join(Path.sep);
                paths = Fs.readdirSync(path);
            }
        }
        for (p in paths) {
            if (p.toLowerCase()==fileName) {
                file = Path.join(path, p);
                insensitiveToSensitiveMap.set(nfile, file);
                break;
            }
        }
        return file; 
    }
    public function new(context:ExtensionContext) {
        this.context = context;
  
        haxeProcess = null;
        
        configuration = cast Vscode.workspace.getConfiguration(languageID());
        platform.Platform.init(js.Node.process.platform);
        configuration.update(platform.Platform.instance);
        
        classPaths = [];
        useInternalBuildFile = false;
        useTmpDir = false;
        projectDir = Vscode.workspace.rootPath;
        tmpToRealMap = new Map();
        insensitiveToSensitiveMap = new Map();
        initTmpDir();
        
        diagnostics =  Vscode.languages.createDiagnosticCollection(languageID());
        context.subscriptions.push(cast diagnostics);

        documentsState = new Map<String, DocumentState>();
        pendingSaves = new Map<String, PendingFile>();


        lastModification = 0;
        lastDiagnostic = 0;
        checkForDiagnostic = false;
        
        checkTimer = new Timer(50);
        checkTimer.run = check;
        
        context.subscriptions.push(cast this);        
    }
    public function cancelDiagnostic() {
        checkForDiagnostic = false;
        lastDiagnostic = getTime();
    }
    public function getDirtyDocuments() {
        var dd = [];
        for (ds in documentsState.iterator()) if (ds.isDirty()) dd.push(ds);
        return dd;
    }
    public function createTmpFile(ds:DocumentState) {
        if (useTmpDir && ds.document != null && ds.tmpPath == null) {
            var path = Path.normalize(ds.realPath);
            var npath = path.toLowerCase();
            var file = null;
            var pack = "";
            for (cp in classPaths) {
                var tmp = npath.split(cp);
                if (tmp.length > 1) {
                    tmp.shift();
                    pack = cp;
                    file = path.substr(cp.length);
                    break;
                }
            }
            if (pack != "") {
                var tmpFile = Path.join(tmpProjectDir, file);
                var dirs = file.split(Path.sep);
                dirs.pop();
                if (dirs.length > 0) {
                    dirs = [tmpProjectDir].concat(dirs);
                    try {
                        dirs.mkDirsSync();
                    } catch(e:Dynamic) {
                        'Can\'t create tmp directory $tmpFile'.displayAsError();
                    }
                }
                try {
                    Fs.writeFileSync(tmpFile, ds.document.getText(), "utf8");
                    ds.tmpPath = tmpFile;
                    tmpToRealMap.set(tmpFile.normalize(), path);
                } catch(e:Dynamic) {
                    'Can\'t save temporary file $tmpFile'.displayAsError();
                }
            }

        }
    }
    public function addClassPath(cp:String) {
        if (!Path.isAbsolute(cp)) cp = Path.join(realWorkingDir, cp);
        cp = (cp + Path.sep).normalize();
        classPaths.push(cp);
        classPaths.sort(function(a, b) {
            return b.length-a.length;
        });
        return cp;
    }
    
    public function clearClassPaths() {
        classPaths = [];
        addClassPath(".");
    }
    
    public function resetDirtyDocuments() {
        var dd = [];
        for (ds in documentsState.iterator()) {
            if (ds.document == null) continue;
            if (ds.document.isDirty) {
                ds.lastSave = ds.lastModification - 1;
                dd.push(ds);
            }
        }
        return dd;
    }
    public function resetSavedDocuments() {
        var t = getTime();
        for (ds in documentsState.iterator()) {
            if (ds.document == null) continue;
            ds.lastSave = t;
        }        
    }
    public function send(?categorie:Null<String>=null, ?restoreCommandLine=false, ?retry=1, ?priority=0) {
        return new Promise<Message>(function(accept, reject) {
            var trying = retry;
            var needResetSave = false;
            inline function restore() {
                if (restoreCommandLine) client.cmdLine.restore();
            }
            function onData(m) {
                if (needResetSave) {
                    resetSavedDocuments();
                    needResetSave = false;
                }
                if (m.severity == MessageSeverity.Cancel) {
                    restore();
                    reject(m);
                    return;
                }
                var e = m.error;
                if ((e == null) && (m.severity!=MessageSeverity.Error)) {
                    restore();
                    accept(m);
                } else {
                    if (e != null) {
                        trying --;
                        if (trying < 0) {
                            restore();
                            reject(m);
                        } else {
                            launchServer().then(
                                function(port) {
                                    client.sendAll(onData, false, categorie, 10000, false);
                                },
                                function(port) {
                                    restore();
                                    reject(m);
                                }
                            );
                        }
                    } else {
                        restore();
                        reject(m);
                    }
                }
            }
            client.sendAll(onData, false, categorie, 0, false);
        });
    }
    public function saveDocument(ds:DocumentState){
#if DO_FULL_PATCH
        return saveFullDocument(ds);
#else
        if (client.isPatchAvailable) return Promise.resolve(ds);
        else return saveFullDocument(ds);
#end
    }
    function saveFullDocument(ds:DocumentState) {
        if (client.isPatchAvailable) {
            return new Promise<DocumentState>(function(accept, reject) {
                if (!ds.isDirty()) accept(ds);
                else patchFullDocument(ds).then(
                    function(ds) {accept(ds);},
                    function(ds) {reject(ds);}
                );
            });          
        } else {
            return new Promise<DocumentState>(function(accept, reject) {  
                var document = ds.document;
                if (document == null) reject(ds);
                if (useTmpDir && ds.tmpPath != null) {
                    try {
                        Fs.writeFile(ds.tmpPath, document.getText(), "utf8", function(e) {
                            if (e != null) reject(ds);
                            else {
//                                var t = Date.now();
//                                Fs.utimesSync(ds.realPath, t, t);
                                onSaveDocument(ds.document);
                                accept(ds);
                            } 
                        });
                    } catch (e:Dynamic) {}
                    return;
                }              
                else {
                    if (document.isDirty) {
                        var path = ds.path();
                        var pf = pendingSaves.get(path);
                        var npf = {ds:ds, reject:reject, accept:accept, lastModification:ds.lastModification};
                        if (pf != null) {
                            pf.reject(pf.ds);
                            pendingSaves.set(path, npf);
                        } else {
                            pendingSaves.set(path, npf);
                            function doSave(ds:DocumentState) {
                                ds.saveStartAt = getTime();
                                ds.document.save().then(function (saved) {
                                    var path = ds.path();
                                    var pf = pendingSaves.get(path);
                                    if (pf != null) {
                                        ds = pf.ds;
                                        if (ds.lastModification > pf.lastModification) {
                                            pf.lastModification = ds.lastModification;
                                            doSave(pf.ds);
                                            return;
                                        } else {
                                            pendingSaves.remove(path);
                                        }
                                    }
                                    if (saved) {
                                        ds.saved();
                                        pf.accept(ds);
                                    } else {
                                        ds.saveStartAt = 0;
                                        pf.reject(ds);
                                    }
                                });
                            }
                            doSave(ds);
                        }
                    } else {
                        ds.saved();
                        accept(ds);
                    }
                }
            });
        }
    }
    function check() {
        var time = getTime();
        if (checkForDiagnostic && configuration.haxeDiagnoseOnSave) {
            var dlt = time - lastDiagnostic;
            if (dlt >= configuration.haxeDiagnosticDelay) {
                checkForDiagnostic = false;
                if (client.isPatchAvailable) {
#if DO_FULL_PATCH
                    var dd = getDirtyDocuments();
                    var cnt = dd.length;
                    var doDiagnostic = false;
                    for (i in 0...dd.length) {
                        var ds = dd[i];
                        var document = ds.document;
                        cnt --;
                        doDiagnostic = doDiagnostic || canRunDiagnostic(ds);
                        diagnostics.delete(untyped document.uri);
                        patchFullDocument(ds).then(function(ds) {
                            if (cnt==0 && doDiagnostic) diagnose(1); 
                        });
                    }
#else
                    diagnose(1);
#end
                } else {
                    var dd = getDirtyDocuments();
                    var cnt = dd.length;
                    if (cnt==0) return;
                    for (i in 0...cnt) {
                        var ds = dd[i];
                        ds.diagnoseOnSave = (i == (cnt-1));
                        if (ds.isSaving()) continue;
                        saveFullDocument(ds);
                    }
                }
            }
        }
    }
    
    public function init() {    
        var host = configuration.haxeServerHost;
        var port = configuration.haxeServerPort;
        client = new HaxeClient(host, port);
        
        context.subscriptions.push(Vscode.workspace.onDidChangeTextDocument(changePatch));

        changeDebouncer = new Debouncer<TextDocumentChangeEvent>(300, changePatchs);

        // remove the patch if the document is opened, saved, or closed
        context.subscriptions.push(Vscode.workspace.onDidOpenTextDocument(onOpenDocument));    
        context.subscriptions.push(Vscode.workspace.onDidSaveTextDocument(onSaveDocument));
        context.subscriptions.push(Vscode.workspace.onDidCloseTextDocument(onCloseDocument));

        completionHandler = new CompletionHandler(this);
        definitionHandler = new DefinitionHandler(this);
        signatureHandler = new SignatureHandler(this);     
        
        return launchServer();
    }
    function initTmpDir() {
        if (configuration.haxeTmpDirectory != "") {
            tmpDir = configuration.haxeTmpDirectory.addTrailingSep(platform.Platform.instance);
            var hash = haxe.crypto.Sha1.encode(realWorkingDir);
            tmpProjectDir = Path.join(tmpDir, hash).normalize();
            try {
                tmpProjectDir.mkDirSync();
                useTmpDir = true;
            } catch (e:Dynamic) {
                unuseTmpDir();
                'Can\'t create temporary directory $tmpProjectDir'.displayAsError();
            }
        } else unuseTmpDir();
    }
    function unuseTmpDir() {
        useTmpDir = false;
        tmpProjectDir = null;
    }
    public function launchServer() {
        var host = configuration.haxeServerHost;
        var port = configuration.haxeServerPort;

        client.host = host;
        client.port = port;
        
        return new Promise<Int>(function (resolve, reject){
            var incPort = 0;
            function onData(data) {
                if (data.isHaxeServer) {
                    configuration.haxeServerPort = port;
                    client.port = port;

                    'Using ${ client.isPatchAvailable ? "--patch" : "non-patching" } completion server at ${configuration.haxeServerHost} on port $port'.displayAsInfo();
                    
                    if (data.isPatchAvailable) {
                        var cl = client.cmdLine.save();
                        var dd = resetDirtyDocuments();
                        if (dd.length > 0) {
                            for (ds in dd) {
                                cl.beginPatch(ds.path()).replace(ds.document.getText());
                            }
                            client.sendAll(
                                function(m) {
                                    resolve(port);
                                },
                                true,
                                null,
                                30000
                            );
                            return;
                        }
                    }

                    return resolve(port);
                } else {
                    if (haxeProcess!=null) haxeProcess.kill("SIGKILL");
                    port += incPort;
                    incPort = 1;
                    haxeProcess = ChildProcess.spawn(configuration.haxeExec, ["--wait", '$port']);
                    if (haxeProcess.pid > 0)  {
                        client.port = port;
                        client.infos(onData);
                    }
                    haxeProcess.on("error", function(err){
                        haxeProcess = null;
                        'Can\'t spawn ${configuration.haxeExec} process\n${err.message}'.displayAsError(); 
                        reject(err);
                    });
                }
            }
            client.infos(onData);
        });
    }
    function dispose():Dynamic {
        Vscode.window.showInformationMessage("Got dispose!");
        if (checkTimer!=null) {
            checkTimer.stop();
            checkTimer = null;
        }
        if (client.isServerAvailable && client.isPatchAvailable) {
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
        if (message.severity == MessageSeverity.Cancel) return;
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
        //var ps = platform.Platform.instance.pathSeparator;
        for (fileName in all.keys()) {
            var diags = all.get(fileName);
//            var tmp = fileName.split(ps);
//            var paths = [];
//            for (s in tmp) {
//                switch(s) {
//                    case ".": continue;
//                    case "..": paths.pop();
//                    default: paths.push(s);
//                }
//            }
//            fileName = paths.join(ps);
            fileName = tmpToReal(fileName);
            var url = Uri.file(fileName);
            if (diags==null) {
                diagnostics.set(url, []);
                continue;
            }
            diagnostics.set(url, diags);
        }
        lastDiagnostic = getTime();
    }
    public function getDocumentState(path:String, ?document:Null<TextDocument>=null) {
        var npath = path.normalize();
        var ds = documentsState.get(npath);
        if (ds != null) {
            if (document != null) ds.document = document;
            if (useTmpDir && ds.tmpPath==null) createTmpFile(ds);
        } else {
            // var t = getTime();
            ds = {realPath:path, saveStartAt:0, lastSave:0, lastModification:0, document:document, diagnoseOnSave:true, tmpPath:null};
            documentsState.set(path, ds);
            documentsState.set(npath, ds);
            createTmpFile(ds);
        }
        return ds;
    }
    public function onCloseDocument(document) {
        var path:String = document.uri.fsPath;
        var ds = getDocumentState(path);
        ds.document = null;
        ds.realPath = null;
        ds.tmpPath = null;
        documentsState.remove(path);
        documentsState.remove(path.normalize());
        if (client.isPatchAvailable) {
            client.cmdLine.save().beginPatch(path).remove();
            client.sendAll(null, true);
        }
        diagnostics.delete(untyped document.uri);
    }
    function onOpenDocument(document:TextDocument) {
        var path:String = document.uri.fsPath;
        var ds = getDocumentState(path, document);
        removeAndDiagnoseDocument(document);
    }
    
    public function patchFullDocument(ds:DocumentState) {
        return new Promise<DocumentState>(function (accept, reject) {
            var document = ds.document;
            if (document == null) return reject(ds);
            client.cmdLine.save().beginPatch(ds.path()).replace(document.getText());
            send(null, true, 1).then(
                function(m){
                    ds.saved();
                    accept(ds);
                },
                function(m){reject(ds);}
            );
        });
    }
    function onSaveDocument(document:TextDocument) {
        var path:String = document.uri.fsPath;
        var ds = getDocumentState(path, document);
        ds.saved();
        if (configuration.haxeDiagnoseOnSave) {
            if (ds.diagnoseOnSave) {
                checkForDiagnostic = true;
                removeAndDiagnoseDocument(document);                    
            } else ds.diagnoseOnSave = true;
        }
    }
    public function diagnoseIfAllowed() {
        if (configuration.haxeDiagnoseOnSave) diagnose(1);        
    }
    function diagnose(retry) {
        var cl = client.cmdLine.save()
        .cwd(workingDir)
        .hxml(buildFile)
        .noOutput()
        ;
        send("diagnostic@1", true, retry).then(
            function(m:Message){applyDiagnostics(m);},
            function(m:Message){
                if (m.error != null) m.error.message.displayAsError();
                applyDiagnostics(m);
            }
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
    function changePatch(event:TextDocumentChangeEvent) {        
        var document = event.document;
        
        if ((event.contentChanges.length==0) || !document.isHaxeDocument()) return;
        
        checkForDiagnostic = false;

        var path:String = document.uri.fsPath;
        var ds = getDocumentState(path, document);
                
        ds.document = document;
        ds.modified();
        
        lastModification = ds.lastModification;
        
        changeDebouncer.debounce(event);
    }
    function changePatchs(events:Array<TextDocumentChangeEvent>) {
        checkForDiagnostic = true;
    }
#else
    function changePatchs(events:Array<TextDocumentChangeEvent>) { 
        var cl = client.cmdLine.save()
            .cwd(workingDir)
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
            
            if (!document.isHaxeDocument()) continue;
            
            var editor = Vscode.window.activeTextEditor;

            var path = document.uri.fsPath;
            var len = path.length;
            
            var text = document.getText();
            
            var patcher = cl.beginPatch(path);
                            
            if (!client.isServerAvailable) {
                if (done.get(path)) continue;
                done.set(path, true);

                if (document.isDirty) patcher.replace(text);
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
                /*
                var pos =0;
                if (editor != null) {
                    if (editor.document == document) pos = Tool.byte_pos(text, document.offsetAt(editor.selection.active));
                    else pos = text.byteLength();
                } else {
                    pos = text.byteLength();                
                }
                */
                changed = true;
            }
        }
        
        diagnostics.delete(untyped document.uri);

        if (changed) {
            client.sendAll(
                function (s, message, error) {
                    if (error==null) applyDiagnostics(message);
                    projectDirty = true;
                },
                true
            );
        } else checkDiagnostic = true;
    }
    function changePatch(event:TextDocumentChangeEvent) {
        var document = event.document;
        var path:String = document.uri.fsPath;
        var ds = getDocumentState(path, document);
        if (event.contentChanges.length==0) return;
        ds.dirty();
        changeDebouncer.debounce(event);
    }
#end
}