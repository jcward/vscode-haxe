import Socket.Error;
import Patcher.PatcherUnit;

typedef OptionAvailable = {isServerAvailable:Bool, isOptionAvailable:Bool};

enum DisplayMode {
    Default();
    Position();
    Usage();
    Type();
    TopLevel();
    Resolve(v:String);
}

class HaxeClient {
    public var host:String;
    public var port:Int;
    var cmds:Array<String>;
    var patcher(default, null):Patcher;

    public function new(host:String, port:Int) {
        this.host = host;
        this.port = port;
        reset();
    }
    public function reset() {
        cmds = [];
        patcher = null;
    }
    public function cwd(dir) {
        cmds.push('--cwd $dir\n');
        return this;        
    }
    public function version() {
        cmds.push("-version\n");
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
    public function sendAll(onData:Socket->String->Void, onError:Socket->Error->Void, ?onClose:Socket->Void=null) {
        endPatch();
        var s = new Socket();
        s.connect(host, port, _onConnect, onData, function(s, err) {
            reset();
            if (onError != null) onError(s, err);  
        }, onClose);
        return s;
    }
    function _onConnect(s:Socket) {
        for (cmd in cmds) {
            s.write(cmd);
        }
        s.write("\x00");
        reset();
    }
    public static function isOptionExists(optionName:String, data:String) {
        var re = new EReg("unknown option '"+optionName+"'", "");
        return !re.match(data);
    }
    public function isPatchAvailable(onData:OptionAvailable->Void) {
        var oldCmds = cmds;
        var oldPatcher = patcher;
        inline function restore() {
            cmds = oldCmds;
            patcher = oldPatcher;
        }
        reset();
        beginPatch('~.hx').remove();
        version();
        sendAll(
            function(s:Socket, data:String) {
                restore();
                var b = isOptionExists("--patch", data);
                onData({isServerAvailable:true, isOptionAvailable:b});
            },
            function (s:Socket, err:Socket.Error) {
                restore();
                onData({isServerAvailable:false, isOptionAvailable:false});
            }
        );
    }
}