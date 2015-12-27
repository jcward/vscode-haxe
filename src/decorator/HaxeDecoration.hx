package decorator;

#if js
import Vscode;
class HaxeDecoration {
    public var errorLineDecoration(default, null):TextEditorDecorationType;
    public var errorCharDecoration(default, null):TextEditorDecorationType;
    public function new() {
        errorLineDecoration = Vscode.window.createTextEditorDecorationType(untyped {
			backgroundColor: "rgba(128,64,64,0.5)",
			isWholeLine: true
		});
        errorCharDecoration = Vscode.window.createTextEditorDecorationType(untyped {
            backgroundColor: "rgba(128,64,64,0.5)",
		});
    }
}
#end