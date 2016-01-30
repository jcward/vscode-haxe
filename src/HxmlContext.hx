import Vscode;

import HaxeContext;
import haxe.HaxeClient;

import js.node.Path;
import js.node.Fs;
import js.node.Fs.FsOpenFlag;
import js.node.Fs.FsMode;
import js.node.ChildProcess;
import js.Error;

using Tool;
using StringTools;

class HxmlContext {
    public inline static function languageID() return "hxml";

    public static inline function isHxmlDocument(document:TextDocument) return (document.languageId == languageID());

    public var hxContext(default, null):HaxeContext;

    var haxelibCache:Map<String, Array<String>>;

    public var context(get, null):ExtensionContext;
    inline function get_context() return hxContext.context;

    public var client(get, null):HaxeClient;
    inline function get_client() return hxContext.client;

    var internalBuildLines:Array<String>;

    var buildWatcher:Vscode.FileSystemWatcher;

    public function new(hxContext:HaxeContext) {
        this.hxContext = hxContext;
        var disposable = Vscode.languages.registerHoverProvider(languageID(), {provideHover:onHover});
        context.subscriptions.push(disposable);

        haxelibCache = new Map();

        buildWatcher = Vscode.workspace.createFileSystemWatcher(hxContext.realBuildFileWithPath, true, false, true);
        buildWatcher.onDidChange(onBuildChange);
        makeInternalBuild();

        new features.hxml.CompletionHandler(this);
        context.subscriptions.push(cast this);
    }
    function onBuildChange(e:Event<Uri>) {
        haxelibCache = new Map();
        makeInternalBuild();
    }
    public function dispose() {
        buildWatcher.dispose();
        Fs.unlinkSync(hxContext.internalBuildFileWithPath);
    }
    function makeInternalBuild() {
        hxContext.clearClassPaths();
        var lines = read(hxContext.realBuildFileWithPath);
        var newLines = parseLines(lines);
        if (newLines != null) lines = newLines;
        hxContext.useInternalBuildFile = true;
        Fs.writeFileSync(hxContext.internalBuildFileWithPath, newLines.join("\n"), "utf8");
    }
    function read(fileName:String) {
        try {
            var txt = Fs.readFileSync(fileName, "utf8");
            var lines = txt.split("\n");
            return lines;
        } catch(e:Dynamic) {
            'Can\'t read file $fileName'.displayAsError();
            return [];
        }
    }

    function parseLines(lines:Array<String>) {
        var newLines = ['#automatically generated do not edit', '#@date ${Date.now()}'];
        newLines = _parseLines(lines, newLines);
        if (hxContext.useTmpDir && newLines != null) {
            var hasEach = false;
            var hasNext = false;
            lines = [];
            for (line in newLines) {
                if (reEach.match(line)) {
                    hasEach = true;
                    lines.push('-cp ${hxContext.tmpProjectDir}');
                    lines.push(line);
                } else if (!hasNext && reNext.match(line)) {
                    hasNext = true;
                    if (!hasEach) {
                        lines.push('-cp ${hxContext.tmpProjectDir}');
                        lines.push("--each");
                    }
                    lines.push("");
                    lines.push(line);
                } else {
                    lines.push(line);
                }
            }
            if (!hasEach && !hasNext) lines.push('-cp ${hxContext.tmpProjectDir}');
        }
        return lines;
    }
    function _parseLines(lines:Array<String>, ?acc:Null<Array<String>>=null, ?isLib=false) {
        if (acc == null) acc = [];

        for (line in lines) {
            line = line.trim();
            if (line == "") {
                acc.push("\n");
                continue;
            }
            if (hxContext.configuration.haxeCacheHaxelib && reLibOption.match(line)) {
                acc.push('#@begin-cache $line');
                var ret = cacheLibData(reLibOption.matched(1), acc);
                if (ret == null) return null;
                if (ret[ret.length-1]=="\n") ret.pop();
                acc = ret;
                acc.push('#@end-cache');
            } else {
                if (reCpOption.match(line)) {
                    var cp = hxContext.addClassPath(reCpOption.matched(1));
                    acc.push('-cp $cp');
                } else
                    if (!isLib) acc.push(line);
                    else
                        switch(line.charAt(0)) {
                            case "-" | "#":
                                acc.push(line);
                            default:
                                var cp = hxContext.addClassPath(line);
                                acc.push('-cp $cp');
                        }
            }
        }

        return acc;
    }
    function cacheLibData(libName, datas:Array<String>) {
        var d = haxelibCache.get(libName);
        if (d!=null) return datas.concat(d);

        haxelibCache.set(libName, []);

        var exec = hxContext.configuration.haxelibExec;
        var out = ChildProcess.spawnSync(
            exec,
            ["path", libName],
            {encoding:"utf8"});

        if (out.pid==0) {
            'Cant find $exec'.displayAsError();
            return null;
        }

        if (out.status == 1) {
            out.stdout.displayAsError();
            return null;
        }

        var lines:Array<String> = (cast out.stdout).split("\n");
        lines = _parseLines(lines, datas, true);
        haxelibCache.set(libName, lines);
        return lines;
    }

    static var reComment = ~/\s*#(.+)/;
    static var reCheckOption = ~/^\s*(-(-)?)([^\s]+)(\s+(.*))?/;
    static var reDefineParam = ~/([^=]+)(=(.+))?/;
    static var reMain = ~/\s*(.+)/;
    static var reLibOption = ~/^\s*-lib\s+([^\s]+)(.*)/;
    static var reCpOption = ~/^\s*-cp\s+([^#]+)(.*)/;
    static var reEach = ~/^\s*--each(.*)/;
    static var reNext = ~/^\s*--next(.*)/;

    function onHover(document:TextDocument, position:Position, cancelToken:CancellationToken):Hover {
        var sHover = "";
        var client = hxContext.client;
        if (client != null) {
            var text = document.lineAt(position).text;
            if (reCheckOption.match(text)) {
                var prefix = reCheckOption.matched(1);
                var name = reCheckOption.matched(3);
                var param = reCheckOption.matched(5);
                if (prefix=="-" && name=="D") {
                    if (reDefineParam.match(param)) {
                        var defineName = reDefineParam.matched(1);
                        var define = client.definesByName.get(defineName);
                        if (define!=null) {
                            sHover = define.doc;
                        }
                    }
                } else {
                    var option = client.optionsByName.get(name);
                    if (option!=null) {
                        sHover = option.doc;
                    }
                }
            } else if (reMain.match(text)) {
                sHover = "Main file : "+reMain.matched(1);
            }
        }
        return new Hover(sHover);
    }
}