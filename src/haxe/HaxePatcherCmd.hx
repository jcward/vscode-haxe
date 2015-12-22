package haxe;

@:enum
abstract PatcherUnit(String) {
    var Byte="b";
    var Char="c";
}

class HaxePatcherCmd {
    public static inline function name() return "--patch";
    
    public var fileName:String; 
    var actions:Array<String>;
    public function new(fileName:String) {
        this.fileName = fileName;
        actions = [];
    }
    public function reset() {
        actions = [];
        return this;
    }
    public function remove() {
        actions.push("x\x01");
        return this;
    }
    public function delete(pos:Int, len:Int, ?unit:PatcherUnit=null) {
        if (unit == null) unit = PatcherUnit.Byte;
        actions.push('$unit-$pos:$len\x01');
        return this;        
    }
    public function insert(pos:Int, text:String, ?unit:PatcherUnit=null) {
        if (unit == null) unit = PatcherUnit.Byte;
        actions.push('$unit+$pos:$text\x01');
        return this;        
    }
    public function get_cmd() {
        if (actions.length==0) return "";
 
        var tmp =  actions.join("@");
        var cmd = name() + ' $fileName@$tmp\n';
        return cmd;
    }
}