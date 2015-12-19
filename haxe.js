(function ($hx_exports) { "use strict";
var HxOverrides = function() { };
HxOverrides.substr = function(s,pos,len) {
	if(pos != null && pos != 0 && len != null && len < 0) return "";
	if(len == null) len = s.length;
	if(pos < 0) {
		pos = s.length + pos;
		if(pos < 0) pos = 0;
	} else if(len < 0) len = s.length + len - pos;
	return s.substr(pos,len);
};
var Main = function() { };
Main.main = $hx_exports.activate = function(context) {
	Main.test_register_command(context);
	var server = new CompletionServer(Vscode.workspace.rootPath);
	var handler = new CompletionHandler(server,context);
	context.subscriptions.push({ dispose : function() {
		Vscode.window.showInformationMessage("Got dispose!");
	}});
};
Main.test_register_command = function(context) {
	var disposable = Vscode.commands.registerCommand("haxe.hello",function() {
		Vscode.window.showInformationMessage("Hello from haxe!");
	});
	context.subscriptions.push(disposable);
};
Main.test_register_hover = function(context) {
	var disposable = Vscode.languages.registerHoverProvider("haxe",{ provideHover : function(document,position,cancelToken) {
		return new Vscode.Hover("I am a hover! pos: " + JSON.stringify(position));
	}});
	context.subscriptions.push(disposable);
};
Main.test_register_hover_thenable = function(context) {
	var disposable = Vscode.languages.registerHoverProvider("haxe",{ provideHover : function(document,position,cancelToken) {
		var s = JSON.stringify(position);
		return new Promise(function(resolve) {
			var h = new Vscode.Hover("I am a thenable hover! pos: " + s);
			resolve(h);
		});
	}});
	context.subscriptions.push(disposable);
};
var CompletionItemProvider = function() { };
var CompletionHandler = function(server,context) {
	this.server = server;
	var disposable = Vscode.languages.registerCompletionItemProvider("haxe",this,".");
	context.subscriptions.push(disposable);
};
CompletionHandler.__interfaces__ = [CompletionItemProvider];
CompletionHandler.prototype = {
	provideCompletionItems: function(document,position,cancelToken) {
		var _g = this;
		var line = document.lineAt(position);
		var dot_offset = 0;
		var subline = HxOverrides.substr(line.text,0,position.character | 0);
		if(subline.indexOf(".") >= 0) dot_offset = subline.lastIndexOf(".") - (position.character | 0) + 1;
		var byte_pos = Std["int"](document.offsetAt(position) + dot_offset);
		return new Promise(function(resolve) {
			var make_request = function() {
				_g.server.request(document.uri.path,byte_pos,function(items) {
					resolve(items);
				});
			};
			if(document.isDirty) document.save().then(make_request); else make_request();
		});
	}
	,resolveCompletionItem: function(item,cancelToken) {
		return item;
	}
};
var Net = require("net");
var ChildProcess = require("child_process");
var CompletionServer = function(proj_dir) {
	var _g = this;
	this.proj_dir = proj_dir;
	this.port = 6000;
	var exec = ChildProcess.exec;
	var restart = null;
	restart = function() {
		Vscode.window.showInformationMessage("Starting haxe completion server...");
		exec("haxe --wait " + _g.port,restart);
	};
};
CompletionServer.prototype = {
	parse_items: function(data) {
		var rtn = [];
		var data_str = data.stderr;
		
                  // Hack hack hack
                  var items = data_str.split("<i n=");
                  for (var i=0; i<items.length; i++) {
                    var item = items[i];
                    if (item.indexOf("\"")==0) {
                      var name = item.match(/"(.*?)"/)[1];
                      var type = item.match(/<t>(.*?)<\/t>/)[1];
                      type = type.replace(/&gt;/g, ">");
                      type = type.replace(/&lt;/g, "<");
                      //Vscode.window.showInformationMessage(name+" : "+type);
                      var ci = new Vscode.CompletionItem(name);
                      ci.detail = type;
                      if (type.indexOf("->")>=0) {
                        ci.kind = Vscode.CompletionItemKind.Method;
                      } else {
                        ci.kind = Vscode.CompletionItemKind.Property;
                      }
                      rtn.push(ci);
                    }
                  }
     ;
		return rtn;
	}
	,request: function(file,byte_pos,callback) {
		var net = Net;
		var hxml_file = "build.hxml";
		var dir = this.proj_dir;
		var parse = $bind(this,this.parse_items);
		
    var NEWLINE = "\n";

    var client = new net.Socket();
    client.connect(this.port, "127.0.0.1", function() {

        // Write a message to the socket as soon as the client is connected, the server will receive it as message from the client 
        client.write("--cwd "+dir+NEWLINE);
        client.write(" "+hxml_file+"\n--display "+file+"@"+byte_pos+NEWLINE);
        client.write("\x00");
     
    });

    // Add a data event handler for the client socket
    // data is what the server sent to this socket
    var data = "";
    client.on("data", function(d) {
      data += d;
    });

    function decode(data) {
      var stdout = "";
      var stderr = "";
      var hasError = false;
      var i = 0;
      var data = data.split("\n");
      while(i < data.length) {
      	var line = data[i];
      	++i;
      	switch(line.charCodeAt(0)) {
      	case 1:
      		stdout += line.substr(1).split("\x01").join("\n");
      		break;
      	case 2:
      		hasError = true;
      		break;
      	default:
      		stderr += line + "\n";
      	}
      }

      //Vscode.window.showInformationMessage("decoded: "+(stdout.length+stderr.length)+" bytes");

      return { stdout:stdout, stderr:stderr, hasError:hasError }
    }

    // Add a close event handler for the client socket
    client.on("close", function() {
      callback(parse(decode(data)));
    });
;
	}
};
var Std = function() { };
Std["int"] = function(x) {
	return x | 0;
};
var Vscode = require("vscode");
var $_, $fid = 0;
function $bind(o,m) { if( m == null ) return null; if( m.__id__ == null ) m.__id__ = $fid++; var f; if( o.hx__closures__ == null ) o.hx__closures__ = {}; else f = o.hx__closures__[m.__id__]; if( f == null ) { f = function(){ return f.method.apply(f.scope, arguments); }; f.scope = o; f.method = m; o.hx__closures__[m.__id__] = f; } return f; }
})(typeof window != "undefined" ? window : exports);
