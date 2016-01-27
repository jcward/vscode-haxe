package haxe;

import haxe.HaxePatcherCmd as Patcher;
import haxe.HaxePatcherCmd.PatcherUnit;

enum DisplayMode {
    Default();
    Position();
    Usage();
    Type();
    TopLevel();
    Resolve(v:String);
}

@:enum abstract IdeFlag(Int) from Int to Int {
    var None = 0;
    var Property = 1;
    var NotReadable = 2;
    var NotWritable = 4;
}

typedef CmdLineStackItem = {cmds:Array<String>, unique:Map<String, String>, workingDir:String}

class HaxeCmdLine {
    var cmds(default, null):Array<String>;
    var unique(default, null):Map<String, String>;
    var stack(default, null):Array<CmdLineStackItem>;
    var patchers(default, null):Map<String, Patcher>;
    public var workingDir(default, null):String;

    public function new() {
        reset();
    }
    public function clear(?haveToClearPatch=false) {
        cmds = [];
        unique = new Map<String, String>();
        workingDir = "";
        if (haveToClearPatch) clearPatch();
    }
    public function reset() {
        stack = [];
        clear(true);
    }
    public function define(name:String, ?value:String=null):HaxeCmdLine {
        if (name != "") {
            var str = '-D $name';
            if (value!=null) str+='=$value';
            cmds.push(str);
        }
        return this;
    }
    public function hxml(fileName:String):HaxeCmdLine {
        unique.set(" ", fileName);
        return this;
    }
    public function cwd(dir):HaxeCmdLine {
        unique.set("--cwd", '$dir');
        workingDir = dir;
        return this;
    }
    public function verbose():HaxeCmdLine {
        unique.set("-v", "");
        return this;
    }
    public function version():HaxeCmdLine {
        unique.set("-version", "");
        return this;
    }
    public function wait(port:Int):HaxeCmdLine {
        unique.set("--wait", '$port');
        return this;
    }
    public function noOutput():HaxeCmdLine {
        unique.set("--no-output", "");
        return this;
    }
    public function keywords(){
        unique.set("--display", "keywords");
    }
    public function classes(){
        unique.set("--display", "classes");
    }
    public function display(fileName:String, pos:Int, mode:DisplayMode):HaxeCmdLine {
        var dm = switch (mode) {
            case Default: "";
            case Position: "@position";
            case Usage: "@usage";
            case Type: "@position";
            case TopLevel: "@toplevel";
            case Resolve(v): '@resolve@$v';
        }
        unique.set("--display", '$fileName@${pos}$dm');
        return this;
    }
    public function help():HaxeCmdLine {
        unique.set("--help", "");
        return this;
    }
    public function helpDefines():HaxeCmdLine {
        unique.set("--help-defines", "");
        return this;
    }
    public function helpMetas():HaxeCmdLine {
        unique.set("--help-metas", "");
        return this;
    }
    public function custom(argName:String, data:String, ?is_unique=true):HaxeCmdLine {
        if (is_unique) unique.set(argName, data);
        else cmds.push('$argName $data');
        return this;
    }
    public function beginPatch(fileName:String):Patcher {
        var tmp = patchers.get(fileName);
        if (tmp == null) tmp = new Patcher(fileName);
        patchers.set(fileName, tmp);
        return tmp;
    }
    public function clearPatch() {
        patchers = new Map<String, Patcher>();
        return this;
    }
    public function save() {
        var wd = workingDir;
        var pt = patchers;
        // don't save patch as they must be applied in the order they appeared
        stack.push({cmds:cmds, unique:unique, workingDir:wd});
        clear();
        patchers = pt;
        if (wd!="") {
            cwd(wd);
        }
        return this;
    }
    public function restore() {
        var i = stack.pop();
        cmds = i.cmds;
        unique = i.unique;
        workingDir = i.workingDir;
        return this;
    }
    public function clone() {
        var cl = new HaxeCmdLine();
        cl.cmds = cmds.concat([]);
        var clu = cl.unique;
        for (key in unique.keys()) clu.set(key, unique.get(key));
        cl.workingDir = workingDir;
        return cl;
    }
    public function toString():String {
        var cmds = cmds.concat([]);
        for (key in unique.keys()) {
            cmds.push(key+" " +unique.get(key));
        }
        for (key in patchers.keys()) {
            cmds.push(patchers.get(key).toString());
        }
        return cmds.join("\n");
    }
}