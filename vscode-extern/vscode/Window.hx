package vscode;

import haxe.extern.Rest;

extern class Window {
	function showInformationMessage(message:String, items:Rest<String>):js.Promise<String>;
}
