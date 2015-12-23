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

typedef CmdLineStackItem = {cmds:Array<String>, patcher:Null<Patcher>, unique:Map<String, String>}

class HaxeCmdLine {
    var cmds(default, null):Array<String>;
    var unique(default, null):Map<String, String>;
    var patcher(default, null):Null<Patcher>;
    var stack:Array<CmdLineStackItem>;
    
    public var workingDir(default, null):String;
     
    public function new() {
        reset();
    }
    public function clear() {
        cmds = [];
        unique = new Map<String, String>();
        workingDir = "";
        patcher = null;
    }
    public function reset() {
        stack = [];
        clear();
    }
    public function hxml(fileName:String) {
        unique.set(" ", fileName);
        return this;
    }
    public function cwd(dir) {
        unique.set("--cwd", '$dir');
        workingDir = dir;
        return this;        
    }
    public function verbose() {
        unique.set("-v", "");
        return this;       
    }
    public function version() {
        unique.set("-version", "");
        return this;
    }
    public function wait(port:Int) {
        unique.set("--wait", '$port');
        return this;       
    }
    public function display(fileName:String, pos:Int, mode:DisplayMode) {
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
    public function custom(argName:String, data:String, ?is_unique=true) {
        if (is_unique) unique.set(argName, data);
        else cmds.push('$argName $data');
        return this;
    }
    public function beginPatch(fileName:String) {
        endPatch();
        patcher = new Patcher(fileName);
        return patcher; 
    }
    public function endPatch() {
        if (patcher != null) {
            cmds.push(patcher.get_cmd());
            patcher = null;
        }
    }
    public function save() {
        stack.push({cmds:cmds, patcher:patcher, unique:unique});
        clear();
    }
    public function restore() {
        var i = stack.pop();
        cmds = i.cmds;
        patcher = i.patcher;
        unique = i.unique;
    }
    public function get_cmds() {
        var cmds = cmds.concat([]);
        for (key in unique.keys()) {
            cmds.push(key+" " +unique.get(key));
        }
        return cmds.join("\n");
    }
}