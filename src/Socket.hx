#if js
import js.node.net.Socket as Socket_;
typedef Error=js.Error;
#else
import sys.net.Socket as Socket_;
import sys.net.Host;
typedef Error=Dynamic;
#end
class Socket {
    var s:Socket_;
    public var datas:Array<String>;
    public var custom:Dynamic;
    public var isConnected(default, null):Bool;
    public var isClosed(default, null):Bool;
    public var hasError(default, null):Bool;
    public function new() {
        s = new Socket_();
        datas = [];
        isConnected = false;
        isClosed = false;
        hasError = false;
    }
    function onConnect(callback:Socket->Void) {
        if (callback!=null)  callback(this);
    }
    function onError(err, callback:Socket->Error->Void) {
        if (callback!=null) callback(this, err);
    }
    function onData(data:Dynamic, callback:Socket->String->Void) {
#if js
        data = data.toString();        
#end    
        datas.push(data);
        if (callback!=null) callback(this, data);
    }
    function onClose(callback:Socket->Void) {
        isConnected = false;
        isClosed = true;
        if (callback!=null) callback(this);        
    }
    public function connect (host:String, port:Int, onConnect:Socket->Void, onData:Socket->String->Void, onError:Socket->Error->Void, ?onClose:Socket->Void=null) {
 #if js
       s.on('error', function(err) {
          hasError = true;
          this.onError(err, onError);  
       });
       s.on('data', function(data) {
           hasError = false;
          this.onData(data, onData);  
       });
       s.on('close', function() {
          this.onClose(onClose);  
       });       
       s.connect(port, host, function() {
           isConnected = true;
           hasError = false;
           this.onConnect(onConnect);       
       });
 #else
    s.connect(new Host(host), port);
    // todo in a worker
    // to be async
    throw new Error("Not implemented");
 #end
    }
    public function write(text:String) {
        return s.write(text);
    }
    public function readAll() {
        return s.read();
    }
}
