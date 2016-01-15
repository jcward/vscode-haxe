import Vscode;

import HaxeContext;
import haxe.HaxeClient;

class HxmlContext {
    public inline static function languageID() return "hxml";

    public var hxContext(default, null):HaxeContext;

    public var context(get, null):ExtensionContext;
    inline function get_context() return hxContext.context; 

    public var client(get, null):HaxeClient;
    inline function get_client() return hxContext.client;     
    
    public function new(hxContext) {
        this.hxContext = hxContext;
        var disposable = Vscode.languages.registerHoverProvider(languageID(), {provideHover:onHover});
        context.subscriptions.push(disposable);
        
        new features.hxml.CompletionHandler(this);
    }

    static var reCheckOption = ~/^\s*(-(-)?)([^\s]+)(\s+(.*))?/;
    static var reDefineParam = ~/([^=]+)(=(.+))?/;
    static var reMain = ~/\s*(.+)/;
    function onHover(document:TextDocument, position:Position, cancelToken:CancellationToken):Hover {
        var sHover = "";
        var client = hxContext.client;
        if (client != null) {
            var text = document.lineAt(position).text;
            if (reCheckOption.match(text)) {
                var prefix = reCheckOption.matched(1);
                var name = reCheckOption.matched(3);
                var param = reCheckOption.matched(5);
                if (prefix=="-" && name=="D") {
                    if (reDefineParam.match(param)) {
                        var defineName = reDefineParam.matched(1);
                        var define = client.definesByName.get(defineName);
                        if (define!=null) {
                            sHover = define.doc;
                        }
                    }
                } else {
                    var option = client.optionsByName.get(name);
                    if (option!=null) {
                        sHover = option.doc;
                    }
                }
            } else if (reMain.match(text)) {
                sHover = "Main file : "+reMain.matched(1);
            }
        }
        return new Hover(sHover);
    }
}