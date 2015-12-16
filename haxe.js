(function ($hx_exports) { "use strict";
var Main = function() { };
Main.main = $hx_exports.activate = function(context) {
	var disposable = Vscode.commands.registerCommand("haxe.hello",function() {
		Vscode.window.showInformationMessage("Hello from haxe!");
	});
	context.subscriptions.push(disposable);
};
var Vscode = require("vscode");
})(typeof window != "undefined" ? window : exports);
