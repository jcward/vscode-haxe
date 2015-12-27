import Vscode;
import haxe.ds.Either;
import haxe.Constraints.Function;

import HaxeContext;
import haxe.HaxeClient;
import haxe.HaxeClient.Message;
using Tool;

/*
 compile with -DDO_FULL_PATCH if you want to sent the whole file at completion
 instead of incremental change
*/

class Main {
	@:expose("activate")
	static function main(context:ExtensionContext) {
        var hc = new HaxeContext(context);
        hc.init();
        
        // test_register_command(context);

        //test_register_hover(context);
        //test_register_hover_thenable(context);

		//Vscode.window.showInformationMessage("Haxe language support loaded!");
	}
    
    static function test_register_command(context:ExtensionContext):Void {
        // Testing a command, access with F1 haxe...
        var disposable = Vscode.commands.registerCommand("haxe.hello", function() {
            Vscode.window.showInformationMessage("Hello from haxe!");
		});
		context.subscriptions.push(disposable);
    }
    
    static function test_register_hover(context:ExtensionContext):Void {
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
    
    static function test_register_hover_thenable(context:ExtensionContext):Void {
        // Test hover code
		var disposable = Vscode.languages.registerHoverProvider('haxe', {
			provideHover:function(document:TextDocument,
                                  position:Position,
                                  cancelToken:CancellationToken):Thenable<Hover>
			{
                var s = untyped JSON.stringify(position);
				return new Thenable<Hover>( function(resolve) {
                    var h = new Hover('I am a thenable hover! pos: '+s);
                    resolve(h);
				});
            }
		});
        
        context.subscriptions.push(disposable);
    }
}
