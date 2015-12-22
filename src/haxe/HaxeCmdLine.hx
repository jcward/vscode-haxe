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

typedef CmdLineStackItem = {cmds:Array<String>, patcher:Null<Patcher>}

class HaxeCmdLine {
    public var cmds(default, null):Array<String>;
    var patcher(default, null):Null<Patcher>;
    var stack:Array<CmdLineStackItem>;

    public function new() {
        reset();
    }
    public function clear() {
        cmds = [];
        patcher = null;
    }
    public function reset() {
        stack = [];
        clear();
    }
    public function cwd(dir) {
        cmds.push('--cwd $dir\n');
        return this;        
    }
    public function verbose() {
        cmds.push("-v\n");
        return this;       
    }
    public function version() {
        cmds.push("-version\n");
        return this;
    }
    public function wait(port:Int) {
        cmds.push('--wait $port\n');
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
        cmds.push('--display $fileName@${pos}$dm\n');
        return this;
    }
    public function custom(data:String) {
        cmds.push(data+"\n");
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
        stack.push({cmds:cmds, patcher:patcher});
        clear();
    }
    public function restore() {
        var i = stack.pop();
        cmds = i.cmds;
        patcher = i.patcher;
    }
}