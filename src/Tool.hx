import Vscode;

#if js
import js.node.Buffer;
#end

class Tool {
    public static inline function displayAsInfo(s:String) Vscode.window.showInformationMessage(s);
    public static inline function displayAsError(s:String) Vscode.window.showErrorMessage(s);
    public static inline function displayAsWarning(s:String) Vscode.window.showWarningMessage(s);
#if js
    public static inline function byteLength(str:String) return Buffer.byteLength(str);
#end
}