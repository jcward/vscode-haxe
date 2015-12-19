import Vscode;
import haxe.ds.Either;
import haxe.Constraints.Function;

class Main {

	@:expose("activate")
	static function main(context:ExtensionContext) {

    test_register_command(context);

    //test_register_hover(context);
    //test_register_hover_thenable(context);

    var server = new CompletionServer(Vscode.workspace.rootPath);
    var handler = new CompletionHandler(server, context);

    // TODO: server implements Disposable
		context.subscriptions.push(untyped {
      dispose:function() {
        Vscode.window.showInformationMessage("Got dispose!");
        //TODO: server.kill();
      }
    });

		//Vscode.window.showInformationMessage("Haxe language support loaded!");
	}

  static function test_register_command(context:ExtensionContext):Void
  {
    // Testing a command, access with F1 haxe...
		var disposable = Vscode.commands.registerCommand("haxe.hello", function() {
			Vscode.window.showInformationMessage("Hello from haxe!");
		});
		context.subscriptions.push(disposable);
  }


  static function test_register_hover(context:ExtensionContext):Void
  {
    // Test hover code
		var disposable = Vscode.languages.registerHoverProvider('haxe', {
			provideHover:function(document:TextDocument,
														position:Position,
														cancelToken:CancellationToken):Hover
			{
				return new Hover('I am a hover! pos: '+untyped(JSON).stringify(position));
			}
		});

    context.subscriptions.push(disposable);
  }

  static function test_register_hover_thenable(context:ExtensionContext):Void
  {
    // Test hover code
		var disposable = Vscode.languages.registerHoverProvider('haxe', {
			provideHover:function(document:TextDocument,
														position:Position,
														cancelToken:CancellationToken):Thenable<Hover>
			{
        var s = untyped JSON.stringify(position);
				return new Thenable<Hover>( function(resolve:Hover->Void) {
          var h = new Hover('I am a thenable hover! pos: '+s);
          resolve(h);
				});
			}
		});

    context.subscriptions.push(disposable);
  }
}

class CompletionHandler implements CompletionItemProvider
{
  var server:CompletionServer;

  public function new(server:CompletionServer,
                      context:ExtensionContext):Void
  {
    this.server = server;

    // Test hover code
		var disposable = Vscode.languages.registerCompletionItemProvider('haxe', this, '.');
    context.subscriptions.push(disposable);
  }

  public function provideCompletionItems(document:TextDocument,
                                         position:Position,
                                         cancelToken:CancellationToken):Thenable<Array<CompletionItem>>
  {
    // find last . before current position
    var line = document.lineAt(position);
    var dot_offset = 0;
    var subline = line.text.substr(0, Std.int(position.character));
    if (subline.indexOf('.')>=0) {
      dot_offset = subline.lastIndexOf('.') - Std.int(position.character) + 1;
    }
    // So far we don't parse this output from the completion server:
    // <type>key : String -&gt; Bool</type>
    //else if (subline.indexOf('(')>=0) {
    //  dot_offset = subline.lastIndexOf('(') - position.character + 1;
    //}

    var byte_pos = Std.int( document.offsetAt(position) + dot_offset );
    var path:String = document.uri.path;
    var win:Int = path.indexOf(":/"); // Windows hack: /c:/...
    if (win>=0 && win<4) {
      path = path.substr(win-1, path.length);
    }

		//Vscode.window.showInformationMessage("C: "+byte_pos);
		//Vscode.window.showInformationMessage("F: "+path);

    return new Thenable<Array<CompletionItem>>( function(resolve:Array<CompletionItem>->Void) {
      function make_request() {
        server.request(path,
                       byte_pos,
                       function(items:Array<CompletionItem>) {
                         resolve(items);
                       });
      }

      // TODO: haxe completion server requires save before compute...
      //       try temporary -cp?
      //       See: https://github.com/HaxeFoundation/haxe/issues/4651
      if (document.isDirty) {
        document.save().then(make_request);
      } else {
        make_request();
      }

    });
  }
	
  public function resolveCompletionItem(item:CompletionItem,
                                        cancelToken:CancellationToken):CompletionItem {
    return item;
  }
}

// extern because it's created in JS below
extern class CompletionServerData {
  public var stdout:String;
  public var stderr:String;
  public var hasError:Bool;
}

@:jsRequire("net")
extern class Net { }

@:jsRequire("child_process")
extern class ChildProcess {
  public static var exec(default, null):String->Function->Void;
}

// TODO: this class will basically be replaced with snowkit/Tides
//       when it becomes availble. This is a hackish placeholder.
class CompletionServer
{
  // TODO: disposable, stop server
  var port:Int;
  var proj_dir:String;

  public function new(proj_dir:String):Void
  {
    this.proj_dir = proj_dir;
    port = 6000; //INST_PORT++;

    var exec = ChildProcess.exec;
    //Vscode.window.showInformationMessage("Start? port="+port+", "+exec);
    var restart:Function = null;
    restart = function() {
			Vscode.window.showInformationMessage("Starting haxe completion server...");
      exec("haxe --wait "+port, restart);
    };
    //restart(); // start by hand for now...
  }

  // I hacked this together in JS, Tides will likely replace
  public function parse_items(data:CompletionServerData):Array<CompletionItem>
  {
    var rtn = new Array<CompletionItem>();
    var data_str = data.stderr; // Don't know why this is stderr

    // TODO: xml parsing, for now, a hack
    //Vscode.window.showInformationMessage("Decoding: "+data_str.length);
    //Vscode.window.showInformationMessage("D: "+data_str);

    untyped __js__('
                  // Hack hack hack
                  var items = data_str.split("<i n=");
                  for (var i=0; i<items.length; i++) {
                    var item = items[i];
                    if (item.indexOf("\\"")==0) {
                      var name = item.match(/"(.*?)"/)[1];
                      var type = item.match(/<t>(.*?)<\\/t>/)[1];
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
     ');
    //Vscode.window.showInformationMessage("Returning: "+rtn.length);
    return rtn;
  }

  public function request(file:String,
                          byte_pos:Int,
                          callback:Array<CompletionItem>->Void) {
    var net = Net;
    var hxml_file = "build.hxml"; // TODO: externalize
    var dir = this.proj_dir;

    // I prototyped this in JS, and since snowkit/Tides will provide
    // this functionality, I'll skip porting it to Haxe here.

    var parse:Function = parse_items;

    untyped __js__('
    var NEWLINE = "\\n";

    var client = new net.Socket();
    client.connect(this.port, "127.0.0.1", function() {

        // Write a message to the socket as soon as the client is connected, the server will receive it as message from the client 
        client.write("--cwd "+dir+NEWLINE);
        client.write(" "+hxml_file+"\\n--display "+file+"@"+byte_pos+NEWLINE);
        client.write("\\x00");
     
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
      var data = data.split("\\n");
      while(i < data.length) {
      	var line = data[i];
      	++i;
      	switch(line.charCodeAt(0)) {
      	case 1:
      		stdout += line.substr(1).split("\\x01").join("\\n");
      		break;
      	case 2:
      		hasError = true;
      		break;
      	default:
      		stderr += line + "\\n";
      	}
      }

      //Vscode.window.showInformationMessage("decoded: "+(stdout.length+stderr.length)+" bytes");

      return { stdout:stdout, stderr:stderr, hasError:hasError }
    }

    // Add a close event handler for the client socket
    client.on("close", function() {
      callback(parse(decode(data)));
    });
');
  }

}
