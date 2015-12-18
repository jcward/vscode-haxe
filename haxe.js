
(function ($hx_exports) { "use strict";
var Main = function() { };
 Main.main = $hx_exports.activate = function(context) {

  // TODO: start haxe server?
  // TODO: externalize configuration
  var HOST = '127.0.0.1';
  var PORT = 6000;

  // Haxe completion server connection
  function haxe_completion_req(byte_pos, callback) {
     
    var NEWLINE = "\n";
     
    var client = new net.Socket();
    client.connect(PORT, HOST, function() {
     
        // Write a message to the socket as soon as the client is connected, the server will receive it as message from the client 
        var proj_dir = '/home/jward/dev/vscode-test-lang/client';
        client.write('--cwd '+proj_dir+NEWLINE);
        client.write(" build.hxml\n--display src/Main.hx@"+byte_pos+NEWLINE);
        client.write("\x00");
     
    });

    // Add a 'data' event handler for the client socket
    // data is what the server sent to this socket
    var data = '';
    client.on('data', function(d) {
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
      return { stdout:stdout, stderr:stderr, hasError:hasError }
    }

    // Add a 'close' event handler for the client socket
    client.on('close', function() {
      callback(decode(data));
    });
  }


  // Test command
	var disposable = Vscode.commands.registerCommand("haxe.hello",function() {
		Vscode.window.showInformationMessage("Hello from haxe!!");
	});
	context.subscriptions.push(disposable);

  // Test hover code
  var disposable = Vscode.languages.registerHoverProvider('haxe', {
		provideHover(document, position, token) {
			return new Vscode.Hover('I am a hover! pos: '+JSON.stringify(position));
		}
	});
	context.subscriptions.push(disposable);

  // Completion item
  var disposable = Vscode.languages.registerCompletionItemProvider(
        'haxe',
        {
        provideCompletionItems:function(document, position, token) {
            //Vscode.window.showInformationMessage("Provide items: "+document.uri);

            // find last . before position
            var line = document.lineAt(position);
            var dot_offset = 0;
            var subline = line.text.substr(0, position.character);
            if (subline.indexOf('.')>=0) {
              dot_offset = subline.lastIndexOf('.') - position.character + 1;
            }
            // So far we don't parse this output from the completion server:
            // <type>key : String -&gt; Bool</type>
            //else if (subline.indexOf('(')>=0) {
            //  dot_offset = subline.lastIndexOf('(') - position.character + 1;
            //}

            var byte_pos = document.offsetAt(position) + dot_offset;
            return new Promise(function(resolve) {

                  // resolve([new Vscode.CompletionItem("Warble"),
									//  				new Vscode.CompletionItem("World"),
									//  				new Vscode.CompletionItem("Wonderful"),
									//  				new Vscode.CompletionItem("Wain"),
									//  				new Vscode.CompletionItem("Wilting"),
									//  				new Vscode.CompletionItem("Wrought")
									//  				]);
                  // return;

              function make_req() {
                // Do something asynchronous
                //Vscode.window.showInformationMessage("resolve... ");

                haxe_completion_req(byte_pos, function(compl) {
                  //Vscode.window.showInformationMessage("C: "+compl.stdout.length+", "+compl.stderr.length+", err="+compl.hasError);
                  //Vscode.window.showInformationMessage(compl.stderr.replace(/\s+/g, ''));

                  // Darn, no DOMParser in nodejs...
                  //var xml = new DOMParser().parseFromString(compl.stderr, "text/xml");
                  //var rtn = [];
                  //for (item in xml.getElementsByTagName('i')) {
                  //  Vscode.window.showInformationMessage("name: "+item.getAttribute('n'));
                  //  var completionItem = new Vscode.CompletionItem(item.getAttribute('n'));
                  //  var type = item.getElementsByTagName('t');
                  //  if (type && type[0]) type = type[0].innerHTML;
                  //  else type = 'Unknown';
                  //  var doc = item.getElementsByTagName('d');
                  //  if (doc && doc[0]) doc = doc[0].innerHTML;
                  //  else doc = '';
                  //  completionItem.detail = type+': '+doc;
                  //  rtn.push(completionItem);
                  //}

                  // Hack hack hack
                  var rtn = [];
                  var items = compl.stderr.split("<i n=");
                  for (var i=0; i<items.length; i++) {
                    var item = items[i];
                    if (item.indexOf('"')==0) {
                      var name = item.match(/"(.*?)"/)[1];
                      var type = item.match(/<t>(.*?)<\/t>/)[1];
                      type = type.replace(/&gt;/g, ">");
                      type = type.replace(/&lt;/g, "<");
                      //Vscode.window.showInformationMessage(name+" : "+type);
                      var ci = new Vscode.CompletionItem(name);
                      ci.detail = type;
                      if (type.indexOf('->')>=0) {
                        ci.kind = Vscode.CompletionItemKind.Method;
                      } else {
                        ci.kind = Vscode.CompletionItemKind.Property;
                      }
                      rtn.push(ci);
                    }
                  }
                  resolve(rtn);
                });
              }

              if (document.isDirty) {
                document.save().then(make_req);
              } else {
                make_req();
              }
            });
			    },
	 		    resolveCompletionItem:function(item) {
            //item.kind = Vscode.CompletionItemKind.Function;
            //Vscode.window.showInformationMessage("resolving...");
            //item.detail = "Yikes";
            //item.documentation = "This is something else";
            return item;
			    },
        }, '.');
	context.subscriptions.push(disposable);

  Vscode.window.showInformationMessage("Hooray, Language: ");

};

var net = require('net');
var sys = require('sys');
var exec = require('child_process').exec;
var Vscode = require("vscode");

})(typeof window != "undefined" ? window : exports);



                // function puts(error, stdout, stderr) {
                //   var val = "Hi"+stdout+stderr+error;
                //   Vscode.window.showInformationMessage(val);
                //   resolve([new Vscode.CompletionItem("Warble"),
                //            new Vscode.CompletionItem("World"),
                //            new Vscode.CompletionItem("Wonderful"),
                //            new Vscode.CompletionItem("Wain"),
                //            new Vscode.CompletionItem("Wilting"),
                //            new Vscode.CompletionItem("Wrought")
                //            ]);
                // }
                // exec("/usr/bin/haxe -version", puts);
