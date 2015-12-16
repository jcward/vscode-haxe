package vscode;

import haxe.Constraints.Function;

extern class Commands {
	function registerCommand(command:String, callback:Function):Disposable;
}
