package haxe;

@:enum
abstract PatcherEditOP(String) {
    var Insert="+";
    var Delete="-";
}

@:enum
abstract PatcherUnit(String) {
    var Byte="b";
    var Char="c";
}

typedef PendingOP = {unit:PatcherUnit, op:PatcherEditOP, pos:Int, len:Int, ?content:String};

class HaxePatcherCmd {
    public static inline function name() return "--patch";
    
    public var fileName(default, null):String; 
    var actions:Array<String>;
    var pendingOP:Null<PendingOP>;
   
    public function new(fileName:String) {
        this.fileName = fileName;
        actions = [];
    }
    public function reset() {
        actions = [];
        return this;
    }
    public function remove() {
        // if we remove the file no need to do insert/delete on it
        pendingOP = null;
        actions = ["x\x01"];
        return this;
    }
    public static function opToString(pop:PendingOP) return {
        switch(pop.op) {
            case PatcherEditOP.Insert: '${pop.unit}${PatcherEditOP.Insert}${pop.pos}:${pop.content}\x01';
            case PatcherEditOP.Delete: '${pop.unit}${PatcherEditOP.Delete}${pop.pos}:${pop.len}\x01';
        }
    } 
    public function delete(pos:Int, len:Int, ?unit:PatcherUnit=null) {
        if (unit == null) unit = PatcherUnit.Byte;
        var op = PatcherEditOP.Delete;
        if (pendingOP == null) pendingOP = {unit:unit, op:op, pos:pos, len:len};
        else {
            // we try to group successive delete
            if (pendingOP.op==op && pendingOP.unit==unit) {
                if (pendingOP.pos==pos) pendingOP.len += len;
                else if (pendingOP.pos==(pos+len)) {
                    pendingOP.len += len;
                    pendingOP.pos = pos;
                } else {
                    actions.push(opToString(pendingOP));
                    pendingOP = {unit:unit, op:op, pos:pos, len:len};
                }
            } else {
                actions.push(opToString(pendingOP));
                pendingOP = {unit:unit, op:op, pos:pos, len:len};
            }
        }
        return this;        
    }
    public function insert(pos:Int, len:Int, text:String, ?unit:PatcherUnit=null) {
        if (unit == null) unit = PatcherUnit.Byte;
        var op = PatcherEditOP.Insert;
        if (pendingOP == null) pendingOP = {unit:unit, op:op, pos:pos, len:len, content:text};
        else {
            // we try to group successive insert
            if (pendingOP.op==op && pendingOP.unit==unit) {
                if ((pendingOP.pos+pendingOP.len)==pos) {
                    pendingOP.len += len;
                    pendingOP.content += text;
                } else if (pendingOP.pos==pos) {
                    pendingOP.len += len;
                    pendingOP.content = text + pendingOP.content;
                } else {
                    actions.push(opToString(pendingOP));
                    pendingOP = {unit:unit, op:op, pos:pos, len:len, content:text};                    
                }
            }
            else {
                actions.push(opToString(pendingOP));
                pendingOP = {unit:unit, op:op, pos:pos, len:len, content:text};
            }
        }
        return this;        
    }
    public function get_cmd() {
        if (pendingOP != null) {
            actions.push(opToString(pendingOP));
            pendingOP = null;
        }

        if (actions.length==0) return "";
 
        var tmp =  actions.join("@");
        var cmd = name() + ' $fileName@$tmp\n';
        return cmd;
    }
}