import haxe.Constraints.Function;
import haxe.extern.EitherType;
import haxe.extern.Rest;

@:jsRequire("vscode")
extern class Vscode {
	static var commands(default,null):Commands;
	static var window(default,null):Window;
	static var languages(default,null):Languages;
	static var workspace(default,null):Workspace;
}

// The following externs are from a scrape/translation of the
// VSCode API. Sources:
//
//  https://code.visualstudio.com/docs/extensionAPI/vscode-api
//  https://github.com/Microsoft/vscode/blob/master/src/vs/vscode.d.ts
//
// They're not all in proper shape, as I fix only those I use
// as I find need of them (e.g. CompletionItemProvider, Hover/HoverPro).
//
// Known issues:
// - I discovered haxe.extern.Rest after commenting a few out, etc.
// - I tried to use EitherType, but didn't for 3 or more types. I
//   inserted Dynamic for some of those, and for the 'any' type
// - The Thenable/Promise is likely incorrect, but it's basically
//   working for where it's used so far.

extern class Commands {
  // Functions
  public function executeCommand<T>(command:String/* , ...rest:Array<Dynamic> */):Thenable<T>;
  public function getCommands():Thenable<Array<String>>;
  public function registerCommand(command:String, callback:Function, ?thisArg:Dynamic):Disposable;
  public function registerTextEditorCommand(command:String, callback:TextEditor -> TextEditorEdit -> Void, ?thisArg:Dynamic):Disposable;
}
extern class Extensions {
  // Variables
  public var all:Array<Extension<Dynamic>>;
  // Functions
  public function getExtension(extensionId:String):Extension<Dynamic>;
  //public function getExtension<T>(extensionId:String):Extension<T>;
}
extern class Languages {
  // Functions
  public function createDiagnosticCollection(?name:String):DiagnosticCollection;
  public function getLanguages():Thenable<Array<String>>;
  public function match(selector:DocumentSelector, document:TextDocument):Int;
  public function registerCodeActionsProvider(selector:DocumentSelector, provider:CodeActionProvider):Disposable;
  public function registerCodeLensProvider(selector:DocumentSelector, provider:CodeLensProvider):Disposable;
  public function registerCompletionItemProvider(selector:DocumentSelector, provider:CompletionItemProvider, triggerCharacters:Rest<String>):Disposable;
  public function registerDefinitionProvider(selector:DocumentSelector, provider:DefinitionProvider):Disposable;
  public function registerDocumentFormattingEditProvider(selector:DocumentSelector, provider:DocumentFormattingEditProvider):Disposable;
  public function registerDocumentHighlightProvider(selector:DocumentSelector, provider:DocumentHighlightProvider):Disposable;
  public function registerDocumentRangeFormattingEditProvider(selector:DocumentSelector, provider:DocumentRangeFormattingEditProvider):Disposable;
  public function registerDocumentSymbolProvider(selector:DocumentSelector, provider:DocumentSymbolProvider):Disposable;
  public function registerHoverProvider(selector:DocumentSelector, provider:HoverProvider):Disposable;
  public function registerOnTypeFormattingEditProvider(selector:DocumentSelector, provider:OnTypeFormattingEditProvider, firstTriggerCharacter:String/* , ...moreTriggerCharacter:Array<String> */):Disposable;
  public function registerReferenceProvider(selector:DocumentSelector, provider:ReferenceProvider):Disposable;
  public function registerRenameProvider(selector:DocumentSelector, provider:RenameProvider):Disposable;
  public function registerSignatureHelpProvider(selector:DocumentSelector, provider:SignatureHelpProvider, triggerCharacters:Rest<String>):Disposable;
  public function registerWorkspaceSymbolProvider(provider:WorkspaceSymbolProvider):Disposable;
  public function setLanguageConfiguration(language:String, configuration:LanguageConfiguration):Disposable;
}
extern class Window {
  // Variables
  public var activeTextEditor:TextEditor;
  public var visibleTextEditors:Array<TextEditor>;
  // Events
  // TODO: onDidChangeActiveTextEditor:Event<TextEditor>;
  // TODO: onDidChangeTextEditorOptions:Event<TextEditorOptionsChangeEvent>;
  // TODO: onDidChangeTextEditorSelection:Event<TextEditorSelectionChangeEvent>;
  // Functions
  public function createOutputChannel(name:String):OutputChannel;
  public function createStatusBarItem(?alignment:StatusBarAlignment, ?priority:Float):StatusBarItem;
  public function createTextEditorDecorationType(options:DecorationRenderOptions):TextEditorDecorationType;
  public function setStatusBarMessage(text:String):Disposable;
  // TODO: @:overload
  //public function setStatusBarMessage(text:String, hideAfterTimeout:Float):Disposable;
  //public function setStatusBarMessage(text:String, hideWhenDone:Thenable<Dynamic>):Disposable;
  public function showErrorMessage(message:String/* , ...items:Array<String> */):Thenable<String>;
  //public function showErrorMessage<T extends MessageItem>(message:String/* , ...items:Array<T> */):Thenable<T>;
  public function showInformationMessage(message:String/* , ...items:Array<String> */):Thenable<String>;
  //public function showInformationMessage<T extends MessageItem>(message:String/* , ...items:Array<T> */):Thenable<T>;
  public function showInputBox(?options:InputBoxOptions):Thenable<String>;
  public function showQuickPick(items:EitherType<Array<String>, Thenable<Array<String>>>, ?options:QuickPickOptions):Thenable<String>;
  //public function showQuickPick<T extends QuickPickItem>(items:EitherType<Array<T>, Thenable<Array<T>>>, ?options:QuickPickOptions):Thenable<T>;
  public function showTextDocument(document:TextDocument, ?column:ViewColumn):Thenable<TextEditor>;
  public function showWarningMessage(message:String/* , ...items:Array<String> */):Thenable<String>;
  //public function showWarningMessage<T extends MessageItem>(message:String/* , ...items:Array<T> */):Thenable<T>;
}
extern class Workspace {
  // Variables
  public var rootPath:String;
  public var textDocuments:Array<TextDocument>;
  // Events
  // TODO: onDidChangeConfiguration:Event<Void>;
  // Functions
  public function onDidChangeTextDocument(event:TextDocumentChangeEvent -> Void):Disposable;
  public function onDidOpenTextDocument(event:TextDocument -> Void):Disposable;
  public function onDidCloseTextDocument(event:TextDocument -> Void):Disposable;
  public function onDidSaveTextDocument(event:TextDocument -> Void):Disposable;
  public function applyEdit(edit:WorkspaceEdit):Thenable<Bool>;
  public function asRelativePath(pathOrUri:EitherType<String, Uri>):String;
  public function createFileSystemWatcher(globPattern:String, ?ignoreCreateEvents:Bool, ?ignoreChangeEvents:Bool, ?ignoreDeleteEvents:Bool):FileSystemWatcher;
  public function findFiles(include:String, exclude:String, ?maxResults:Int):Thenable<Array<Uri>>;
  public function getConfiguration(?section:String):WorkspaceConfiguration;
  // Hmm, couldn't get @:overload to work...
  public function openTextDocument(uri_or_fileName:EitherType<Uri, String>):Thenable<TextDocument>;
  //public function openTextDocument(fileName:String):Thenable<TextDocument>;
  public function saveAll(?includeUntitled:Bool):Thenable<Bool>;
}
extern class CancellationToken {
  // Properties
  public var isCancellationRequested:Bool;
  public var onCancellationRequested:Event<Dynamic>;
}
extern class CancellationtokenSource {
  // Properties
  public var token:CancellationToken;
  // Methods
  public function cancel():Void;
  public function dispose():Void;
}
extern class CharacterPair {
  public var CharacterPair:Dynamic /* [String, String] */;
}
extern class CodeActionContext {
  // Properties
  public var diagnostics:Array<Diagnostic>;
}
extern class CodeActionProvider {
  // Methods
  public function provideCodeActions(document:TextDocument, range:Range, context:CodeActionContext, token:CancellationToken):EitherType<Array<Command>, Thenable<Array<Command>>>;
}
extern class CodeLens {
  // Constructors
  public function new(range:Range, ?command:Command);
  // Properties
  public var command:Command;
  public var isResolved:Bool;
  public var range:Range;
}
extern class CodeLensProvider {
  // Methods
  public function provideCodeLenses(document:TextDocument, token:CancellationToken):EitherType<Array<CodeLens>, Thenable<Array<CodeLens>>>;
  public function resolveCodeLens(codeLens:CodeLens, token:CancellationToken):EitherType<CodeLens, Thenable<CodeLens>>;
}
extern class Command {
  // Properties
  public var arguments:Array<Dynamic>;
  public var command:String;
  public var title:String;
}
extern class CommentRule {
  // Properties
  public var blockComment:CharacterPair;
  public var lineComment:String;
}
@:native("Vscode.CompletionItem")
extern class CompletionItem {
  // Constructors
  public function new(label:String);
  // Properties
  public var detail:String;
  public var documentation:String;
  public var filterText:String;
  public var insertText:String;
  public var kind:CompletionItemKind;
  public var label:String;
  public var sortText:String;
  public var textEdit:TextEdit;
}
@:native("Vscode.CompletionItemKind")
extern class CompletionItemKind {
  // Enumeration members
  public static var Class;
  public static var Color;
  public static var Constructor;
  public static var Enum;
  public static var Field;
  public static var File;
  public static var Function;
  public static var Interface;
  public static var Keyword;
  public static var Method;
  public static var Module;
  public static var Property;
  public static var Reference;
  public static var Snippet;
  public static var Text;
  public static var Unit;
  public static var Value;
  public static var Variable;
}

interface CompletionItemProvider {
  // Methods
  public function provideCompletionItems(document:TextDocument,
                                         position:Position,
                                         cancelToken:CancellationToken):Thenable<Array<CompletionItem>>;
  public function resolveCompletionItem(item:CompletionItem,
                                        cancelToken:CancellationToken):CompletionItem;
}

extern class Decorationoptions {
  // Properties
  public var hoverMessage:EitherType<MarkedString, Array<MarkedString>>;
  public var range:Range;
}
extern class DecorationRenderOptions {
  // Properties
  public var backgroundColor:String;
  public var borderColor:String;
  public var borderRadius:String;
  public var borderSpacing:String;
  public var borderStyle:String;
  public var borderWidth:String;
  public var color:String;
  public var cursor:String;
  public var dark:ThemableDecorationRenderOptions;
  public var gutterIconPath:String;
  public var isWholeLine:Bool;
  public var light:ThemableDecorationRenderOptions;
  public var outlineColor:String;
  public var outlineStyle:String;
  public var outlineWidth:String;
  public var overviewRulerColor:String;
  public var overviewRulerLane:OverviewRulerLane;
  public var textDecoration:String;
}
@:native('Vscode.Definition')
extern class Definition {
  public var Definition:EitherType<Location, Array<Location>>;
}
interface DefinitionProvider {
  // Methods
  public function provideDefinition(document:TextDocument, position:Position, token:CancellationToken):EitherType<Definition, Thenable<Definition>>;
}
@:native('Vscode.Diagnostic')
extern class Diagnostic {
  // Constructors
  public function new(range:Range, message:String, ?severity:DiagnosticSeverity);
  // Properties
  public var code:EitherType<String, Float>;
  public var message:String;
  public var range:Range;
  public var severity:DiagnosticSeverity;
}
@:native('Vscode.DiagnosticCollection')
extern class DiagnosticCollection {
  // Properties
  public var name:String;
  // Methods
  public function clear():Void;
  public function delete(uri:Uri):Void;
  public function dispose():Void;
  public function set(uri:Uri, diagnostics:Array<Diagnostic>):Void;
  //public function set(entries:Dynamic /* [Uri, Array<Diagnostic>][] */):Void;
}
@:native('Vscode.DiagnosticSeverity')
extern class DiagnosticSeverity {
  // Enumeration members
  public static var Error;
  public static var Hint;
  public static var Information;
  public static var Warning;
}
@:native('Vscode.Disposable')
extern class Disposable {
  // Static
  public static function from(val:Dynamic):Disposable;
  // Constructors
  public function new(callOnDispose:Function);
  // Methods
  public function dispose():Dynamic;
}
extern class Documentfilter {
  // Properties
  public var language:String;
  public var pattern:String;
  public var scheme:String;
}
extern class DocumentFormattingEditProvider {
  // Methods
  public function provideDocumentFormattingEdits(document:TextDocument, options:FormattingOptions, token:CancellationToken):EitherType<Array<TextEdit>, Thenable<Array<TextEdit>>>;
}
extern class DocumentHighlight {
  // Constructors
  public function new(range:Range, ?kind:DocumentHighlightKind);
  // Properties
  public var kind:DocumentHighlightKind;
  public var range:Range;
}
extern class DocumentHighlightKind {
  // Enumeration members
  public static var Read;
  public static var Text;
  public static var Write;
}
extern class DocumentHighlightProvider {
  // Methods
  public function provideDocumentHighlights(document:TextDocument, position:Position, token:CancellationToken):EitherType<Array<DocumentHighlight>, Thenable<Array<DocumentHighlight>>>;
}
extern class DocumentRangeFormattingEditProvider {
  // Methods
  public function provideDocumentRangeFormattingEdits(document:TextDocument, range:Range, options:FormattingOptions, token:CancellationToken):EitherType<Array<TextEdit>, Thenable<Array<TextEdit>>>;
}
// extern class DocumentSelector {
//   public var DocumentSelector:Dynamic;
// }
typedef DocumentSelector = String;
extern class DocumentSymbolProvider {
  // Methods
  public function provideDocumentSymbols(document:TextDocument, token:CancellationToken):EitherType<Array<SymbolInformation>, Thenable<Array<SymbolInformation>>>;
}
extern class EnterAction {
  // Properties
  public var appendText:String;
  public var indentAction:IndentAction;
  public var removeText:Float;
}
extern class Event<T> {
  // public var (listener:T -> Dynamic, ?thisArgs:Dynamic, ?disposables:Array<Disposable>):Disposable;
}
extern class Extension<T> {
  // Properties
  public var exports:T;
  public var extensionPath:String;
  public var id:String;
  public var isActive:Bool;
  public var packageJSON:Dynamic;
  // Methods
  public function activate():Thenable<T>;
}
extern class Extensioncontext {
  // Properties
  public var extensionPath:String;
  public var globalState:Memento;
  public var subscriptions:Dynamic;
  public var workspaceState:Memento;
  // Methods
  public function asAbsolutePath(relativePath:String):String;
}
extern class FileSystemWatcher {
  // Events
  // TODO: onDidChange:Event<Uri>;
  // TODO: onDidCreate:Event<Uri>;
  // TODO: onDidDelete:Event<Uri>;
  // Static
  public static function from(val:Dynamic):Disposable;
  // Constructors
  public function new(callOnDispose:Function);
  // Properties
  public var ignoreChangeEvents:Bool;
  public var ignoreCreateEvents:Bool;
  public var ignoreDeleteEvents:Bool;
  // Methods
  public function dispose():Dynamic;
}
extern class FormattingOptions {
  // Properties
  public var insertSpaces:Bool;
  public var tabSize:Float;
}

@:native('Vscode.Hover')
extern class Hover {
  // Constructors
  public function new(contents:EitherType<MarkedString, Array<MarkedString>>, ?range:Range);
  // Properties
  public var contents:Array<MarkedString>;
  public var range:Range;
}
//extern class HoverProvider {
//  // Methods
//  //provideHover:TextDocument->Position->CancellationToken->Hover
//  public function provideHover(document:TextDocument, position:Position, token:CancellationToken):Either<Hover, Thenable<Hover>>;
//}
typedef HoverProvider = { provideHover:TextDocument->Position->CancellationToken->EitherType<Hover, Thenable<Hover>> }

extern class IndentAction {
  // Enumeration members
  public static var Indent;
  public static var IndentOutdent;
  public static var None;
  public static var Outdent;
}
extern class IndentationRule {
  // Properties
  public var decreaseIndentPattern:EReg;
  public var increaseIndentPattern:EReg;
  public var indentNextLinePattern:EReg;
  public var unIndentedLinePattern:EReg;
}
extern class InputBoxOptions {
  // Properties
  public var password:Bool;
  public var placeHolder:String;
  public var prompt:String;
  public var value:String;
}
extern class LanguageConfiguration {
  // Properties
  //public var ___characterPairSupport:{autoClosingPairs:{close:String, notIn:Array<String>, open:String}[]};
  //public var ___electricCharacterSupport:{brackets:{close:String, isElectric:Bool, open:String, tokenType:String}[], docComment:{close:String, lineStart:String, open:String, scope:String}};
  public var brackets:Array<CharacterPair>;
  public var comments:CommentRule;
  public var indentationRules:IndentationRule;
  public var onEnterRules:Array<OnEnterRule>;
  public var wordPattern:EReg;
}
@:native('Vscode.Location')
extern class Location {
  // Constructors
  public function new(uri:Uri,rangeOrPosition:EitherType<Range, Position>);
  // Properties
  public var range:Range;
  public var uri:Uri;
}
typedef MarkedString = String;
//extern class MarkedString {
//  //public var MarkedString:EitherType<String, {language:String>, value:String};
//}
extern class Memento {
  // Methods
  public function get<T>(key:String, ?defaultValue:T):T;
  public function update(key:String, value:Dynamic):Thenable<Void>;
}
extern class Messageitem {
  // Properties
  public var title:String;
}
extern class OnEnterRule {
  // Properties
  public var action:EnterAction;
  public var afterText:EReg;
  public var beforeText:EReg;
}
extern class OnTypeFormattingEditProvider {
  // Methods
  public function provideOnTypeFormattingEdits(document:TextDocument, position:Position, ch:String, options:FormattingOptions, token:CancellationToken):EitherType<Array<TextEdit>, Thenable<Array<TextEdit>>>;
}
extern class OutputChannel {
  // Properties
  public var name:String;
  // Methods
  public function append(value:String):Void;
  public function appendLine(value:String):Void;
  public function clear():Void;
  public function dispose():Void;
  public function hide():Void;
  public function show(?column:ViewColumn):Void;
}
extern class OverviewRulerLane {
  // Enumeration members
  public static var Center;
  public static var Full;
  public static var Left;
  public static var Right;
}
@:native("Vscode.ParameterInformation")
extern class ParameterInformation {
  // Constructors
  public function new(label:String, ?documentation:String);
  // Properties
  public var documentation:String;
  public var label:String;
}
@:native('Vscode.Position')
extern class Position {
  // Constructors
  public function new(line:Int, character:Int);
  // Properties
  public var character:Int;
  public var line:Int;
  // Methods
  public function compareTo(other:Position):Int;
  public function isAfter(other:Position):Bool;
  public function isAfterOrEqual(other:Position):Bool;
  public function isBefore(other:Position):Bool;
  public function isBeforeOrEqual(other:Position):Bool;
  public function isEqual(other:Position):Bool;
  public function translate(?lineDelta:Int, ?characterDelta:Int):Position;
  public function with(?line:Int, ?character:Int):Position;
}
extern class Quickpickitem {
  // Properties
  public var description:String;
  public var label:String;
}
extern class QuickPickOptions {
  // Properties
  public var matchOnDescription:Bool;
  public var placeHolder:String;
}
@:native('Vscode.Range')
extern class Range {
  // Constructors
  public function new(start:Position, end:Position);
  // TODO: public function new(startLine:Float, startCharacter:Float, endLine:Float, endCharacter:Float);
  // Properties
  public var end:Position;
  public var isEmpty:Bool;
  public var isSingleLine:Bool;
  public var start:Position;
  // Methods
  public function contains(positionOrRange:EitherType<Position, Range>):Bool;
  public function intersection(range:Range):Range;
  public function isEqual(other:Range):Bool;
  public function union(other:Range):Range;
  public function with(?start:Position, ?end:Position):Range;
}
extern class ReferenceContext {
  // Properties
  public var includeDeclaration:Bool;
}
extern class ReferenceProvider {
  // Methods
  public function provideReferences(document:TextDocument, position:Position, context:ReferenceContext, token:CancellationToken):EitherType<Array<Location>, Thenable<Array<Location>>>;
}
extern class RenameProvider {
  // Methods
  public function provideRenameEdits(document:TextDocument, position:Position, newName:String, token:CancellationToken):EitherType<WorkspaceEdit, Thenable<WorkspaceEdit>>;
}
extern class Selection {
  // Constructors
  public function new(anchor:Position, active:Position);
  // TODO: public function new(anchorLine:Float, anchorCharacter:Float, activeLine:Float, activeCharacter:Float);
  // Properties
  public var active:Position;
  public var anchor:Position;
  public var end:Position;
  public var isEmpty:Bool;
  public var isReversed:Bool;
  public var isSingleLine:Bool;
  public var start:Position;
  // Methods
  public function contains(positionOrRange:EitherType<Position, Range>):Bool;
  public function intersection(range:Range):Range;
  public function isEqual(other:Range):Bool;
  public function union(other:Range):Range;
  public function with(?start:Position, ?end:Position):Range;
}
@:native("Vscode.SignatureHelp")
extern class SignatureHelp {
    public function new();
  // Properties
  public var activeParameter:Int;
  public var activeSignature:Int;
  public var signatures:Array<SignatureInformation>;
}
interface SignatureHelpProvider {
  // Methods
  public function provideSignatureHelp(document:TextDocument, position:Position, token:CancellationToken):EitherType<SignatureHelp, Thenable<SignatureHelp>>;
}
@:native("Vscode.SignatureInformation")
extern class SignatureInformation {
  // Constructors
  public function new(label:String, ?documentation:String);
  // Properties
  public var documentation:String;
  public var label:String;
  public var parameters:Array<ParameterInformation>;
}
extern class StatusBarAlignment {
  // Enumeration members
  public static var Left;
  public static var Right;
}
extern class StatusBarItem {
  // Properties
  public var alignment:StatusBarAlignment;
  public var color:String;
  public var command:String;
  public var priority:Float;
  public var text:String;
  public var tooltip:String;
  // Methods
  public function dispose():Void;
  public function hide():Void;
  public function show():Void;
  // SymbolInformation
  // Constructors
  public function new(name:String, kind:SymbolKind, range:Range, ?uri:Uri, ?containerName:String);
  // Properties
  public var containerName:String;
  public var kind:SymbolKind;
  public var location:Location;
  public var name:String;
}
extern class SymbolKind {
  // Enumeration members
  public static var Array;
  public static var Boolean;
  public static var Class;
  public static var Constant;
  public static var Constructor;
  public static var Enum;
  public static var Field;
  public static var File;
  public static var Function;
  public static var Interface;
  public static var Method;
  public static var Module;
  public static var Namespace;
  public static var Number;
  public static var Package;
  public static var Property;
  public static var String;
  public static var Variable;
}
extern class TextDocument {
  // Properties
  public var fileName:String;
  public var isDirty:Bool;
  public var isUntitled:Bool;
  public var languageId:String;
  public var lineCount:Int;
  public var uri:Uri;
  public var version:Float;
  // Methods
  public function getText(?range:Range):String;
  public function getWordRangeAtPosition(position:Position):Range;
  public function lineAt(line_or_position:EitherType<Int,Position>):TextLine;
  //public function lineAt(position:Position):TextLine;
  public function offsetAt(position:Position):Int;
  public function positionAt(offset:Int):Position;
  public function save():Thenable<Bool>;
  public function validatePosition(position:Position):Position;
  public function validateRange(range:Range):Range;
}
extern class TextDocumentChangeEvent {
  // Properties
  public var contentChanges:Array<TextDocumentContentChangeEvent>;
  public var document:TextDocument;
}
extern class TextDocumentContentChangeEvent {
  // Properties
  public var range:Range;
  public var rangeLength:Int;
  public var text:String;
}
extern class TextEdit {
  // Static
  public static function delete(range:Range):TextEdit;
  public static function insert(position:Position, newText:String):TextEdit;
  public static function replace(range:Range, newText:String):TextEdit;
  // Constructors
  public function new(range:Range, newText:String);
  // Properties
  public var newText:String;
  public var range:Range;
}
extern class TextEditor {
  // Properties
  public var document:TextDocument;
  public var options:TextEditorOptions;
  public var selection:Selection;
  public var selections:Array<Selection>;
  // Methods
  public function edit(callback:TextEditorEdit -> Void):Thenable<Bool>;
  public function hide():Void;
  public function revealRange(range:Range, ?revealType:TextEditorRevealType):Void;
  public function setDecorations(decorationType:TextEditorDecorationType,rangesOrOptions:EitherType<Array<Range>, Array<DecorationOptions>>):Void;
  public function show(?column:ViewColumn):Void;
}
extern class TextEditorDecorationType {
  // Properties
  public var key:String;
  // Methods
  public function dispose():Void;
}
extern class TextEditorEdit {
  // Methods
  public function delete(location:EitherType<Range, Selection>):Void;
  public function insert(location:Position, value:String):Void;
  public function replace(val:Dynamic, value:String):Void;
}
extern class TextEditorOptions {
  // Properties
  public var insertSpaces:Bool;
  public var tabSize:Float;
}
extern class TextEditorOptionsChangeEvent {
  // Properties
  public var options:TextEditorOptions;
  public var textEditor:TextEditor;
}
extern class TextEditorRevealType {
  // Enumeration members
  public static var Default;
  public static var InCenter;
  public static var InCenterIfOutsideViewport;
}
extern class Texteditorselectionchangeevent {
  // Properties
  public var selections:Array<Selection>;
  public var textEditor:TextEditor;
}
extern class TextLine {
  // Properties
  public var firstNonWhitespaceCharacterIndex:Int;
  public var isEmptyOrWhitespace:Bool;
  public var lineNumber:Int;
  public var range:Range;
  public var rangeIncludingLineBreak:Range;
  public var text:String;
}
extern class ThemableDecorationRenderOptions {
  // Properties
  public var backgroundColor:String;
  public var borderColor:String;
  public var borderRadius:String;
  public var borderSpacing:String;
  public var borderStyle:String;
  public var borderWidth:String;
  public var color:String;
  public var cursor:String;
  public var gutterIconPath:String;
  public var outlineColor:String;
  public var outlineStyle:String;
  public var outlineWidth:String;
  public var overviewRulerColor:String;
  public var textDecoration:String;
}
@:native('Vscode.Uri')
extern class Uri {
  // Static
  public static function file(path:String):Uri;
  public static function parse(value:String):Uri;
  // Properties
  public var authority:String;
  public var fragment:String;
  public var fsPath:String;
  public var path:String;
  public var query:String;
  public var scheme:String;
  // Methods
  public function toJSON():Dynamic;
  public function toString():String;
}
extern class ViewColumn {
  // Enumeration members
  public static var One;
  public static var Three;
  public static var Two;
}
extern class WorkspaceConfiguration {
  // Methods
  public function get<T>(section:String, ?defaultValue:T):T;
  public function has(section:String):Bool;
}
extern class WorkspaceEdit {
  // Properties
  public var size: Int;
  // Methods
  public function delete(uri:Uri, range:Range):Void;
  public function entries():Dynamic /* [Uri, Array<TextEdit>][] */;
  public function get(uri:Uri):Array<TextEdit>;
  public function has(uri:Uri):Bool;
  public function insert(uri:Uri, position:Position, newText:String):Void;
  public function replace(uri:Uri, range:Range, newText:String):Void;
  public function set(uri:Uri, edits:Array<TextEdit>):Void;
}
extern class WorkspaceSymbolProvider {
  // Methods
  public function provideWorkspaceSymbols(query:String, token:CancellationToken):EitherType<Array<SymbolInformation>, Thenable<Array<SymbolInformation>>>;
}


// ???
extern class SymbolInformation { }
//extern class DecorationOptions { }
typedef DecorationOptions = {
    ?hoverMessage:String,
    range:Range,
};

extern class ExtensionContext {
	var subscriptions(default,null):Array<Disposable>;
}


@:native('Promise')
extern class Thenable<T> {
	public function new(resolve:(T->Void)->Void, ?reject:(Dynamic->Void)->Void);
	public function then(onResolved:T->Void, ?onError:Dynamic->Void):Thenable<T>;
	//public function resolve(val:T):Thenable<T>;
}


// @:native('Promise')
// extern class Thenable<T> {
//  
//   @:native("then")
//   public function thenFlat<U>(f : T -> Thenable<U>) : Thenable<U>;
//  
//   public function then<U>(f : T -> U) : Thenable<U>;
// }

