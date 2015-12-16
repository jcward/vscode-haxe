import haxe.Constraints.Function;

import vscode.*;

@:jsRequire("vscode")
extern class Vscode {
	static var commands(default,null):Commands;
	static var window(default,null):Window;
}
