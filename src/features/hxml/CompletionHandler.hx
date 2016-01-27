package features.hxml;

import Vscode;

import HxmlContext;

class CompletionHandler implements CompletionItemProvider
{
  var hxmlContext:HxmlContext;

  public function new(hxmlContext:HxmlContext):Void
  {
      this.hxmlContext = hxmlContext;

      var context = hxmlContext.context;

      var disposable = Vscode.languages.registerCompletionItemProvider(HxmlContext.languageID(), this, '-', 'D', ' ');
      context.subscriptions.push(disposable);
  }

  static var reI=~/<i n="([^"]+)" k="([^"]+)"( ip="([0-1])")?( f="(\d+)")?><t>([^<]*)<\/t><d>([^<]*)<\/d><\/i>/;
  static var reGT = ~/&gt;/g;
  static var reLT = ~/&lt;/g;
  static var reMethod = ~/Void|Unknown/;

  public function provideCompletionItems(document:TextDocument,
                                         position:Position,
                                         cancelToken:CancellationToken):Thenable<Array<CompletionItem>>
  {
      var items = [];

      var client = hxmlContext.client;
      if (client != null) {
          var textLine = document.lineAt(position);
          var text = textLine.text;
          var char_pos = position.character - 1;
          var char = text.charAt(char_pos);
          switch (char) {
              case '-':
                switch(char_pos) {
                    case 0:
                        for (data in client.options) {
                            var ci = new Vscode.CompletionItem(data.prefix.substr(1)+data.name);
                            ci.documentation = data.doc;
                            items.push(ci);
                        }
                    case 1:
                        for (data in client.options) {
                            if (data.prefix.length < 2) continue;
                            var ci = new Vscode.CompletionItem(data.name);
                            ci.documentation = data.doc;
                            items.push(ci);
                        }
                }
              case 'D':
                if ((char_pos==1) && (text.charAt(char_pos - 1)=='-')) {
                    for (data in client.defines) {
                        var ci = new Vscode.CompletionItem('D '+data.name);
                        ci.documentation = data.doc;
                        items.push(ci);
                    }
                }
              case ' ':
                if ((char_pos==2) && (text.substr(0, char_pos)=='-D')) {
                    for (data in client.defines) {
                        var ci = new Vscode.CompletionItem(data.name);
                        ci.documentation = data.doc;
                        items.push(ci);
                    }
                }

          }
      }
      return new Thenable<Array<CompletionItem>>(function(resolve) {resolve(items);});
  }
  public function resolveCompletionItem(item:CompletionItem, cancelToken:CancellationToken):CompletionItem {
    return item;
  }
}