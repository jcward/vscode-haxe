import Vscode;

class Main {
	@:expose("activate")
	static function main(context:vscode.ExtensionContext) {
		var disposable = Vscode.commands.registerCommand("haxe.hello", function() {
			Vscode.window.showInformationMessage("Hello from haxe!");
		});
		context.subscriptions.push(disposable);
	}
}