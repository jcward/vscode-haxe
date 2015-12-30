# vscode-haxe
Haxe language extension for Visual Studio Code

This extension provides:
- Syntax highlighting for .hx and .hxml
- Code completion (ALPHA / EXPERIMENTAL, see below)
- Jump / peek definition (ctrl-click / ctrl-hover)

Feature  | Preview
------------- | -------------
Code Completion  |  <img src="https://lh3.googleusercontent.com/-ekHamgDiuZM/VnOd05QH04I/AAAAAAAAO4I/cfu718KBlO8/s1600/test.gif" width=400>
Peek definition  | <img src="https://lh3.googleusercontent.com/-0cTfJGLLrpk/VoBPk4GAz_I/AAAAAAAAPKs/bWvpJBDjwnA/s400/definition_peek.gif" width=400>

#Installation
Place the vscode-haxe directory in your `.vscode/extensions` directory:
- Windows: `%USERPROFILE%\.vscode\extensions`
- Linux / Mac: `~/.vscode/extensions`

#Code completion status: ALPHA
The code completion in this extension is currently in alpha. There are bugs, limitations, and requirements that still need to be worked out. There's an effort to standardize Haxe IDE support over at [snowkit/Tides](https://github.com/snowkit/tides). When this is ready, I'll integrate it (no need to duplicate effort and provide divergent experiences.)

#Current limitations:
- Currently only supports code/package completion, no function signatures, etc.
- You must start the haxe completion server yourself. Luckily it's easy. Open a terminal and run `haxe --wait 6000` and let it sit there while you edit.
- Currently requires a file named `build.hxml` in the root of the workspace (the folder you open in Code.)

I've provided a `test_proj` for you to try it. Start your completion server, open this folder in Code, and try it! You can add haxelib libraries to `test_proj`'s build.hxml if you want to see if they work.

#Framework notes:
Some frameworks support the creation of .hxml files so you can use completion with your project.

**OpenFL's** display command will show the contents of the necessary .hxml file. On Windows, paste the output into a build.hxml file, or on Linux/Mac, you can create a build.hxml file in your project directory by running, e.g. `openfl display neko > build.hxml` (substitue the proper platform name for your project.)
