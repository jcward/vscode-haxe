import Vscode;
import haxe.ds.Either;
import haxe.Constraints.Function;

import HaxeContext;
import HxmlContext;
import haxe.HaxeClient;
import haxe.HaxeClient.Message;
using Tool;

class Main {
	@:expose("activate")
	static function main(context:ExtensionContext) {
        var hc = new HaxeContext(context);
        hc.init();
        new HxmlContext(hc);
	}
}
