# vscode-haxe
Haxe language extension for Visual Studio Code
by Patrick Le Clec'h, Jeff Ward, and Dan Korostelev

This extension provides:
- Syntax highlighting for .hx and .hxml files
- Code completion (work in progress)
- Function signature completion
- Jump / peek definition (ctrl-click / ctrl-hover)

Feature  | Preview
------------- | -------------
Code Completion  |  <img src="https://lh3.googleusercontent.com/-ekHamgDiuZM/VnOd05QH04I/AAAAAAAAO4I/cfu718KBlO8/s1600/test.gif" width=400>
Peek definition  | <img src="https://lh3.googleusercontent.com/-0cTfJGLLrpk/VoBPk4GAz_I/AAAAAAAAPKs/bWvpJBDjwnA/s400/definition_peek.gif" width=400>

#Installation
Place the vscode-haxe directory in your `.vscode/extensions` directory:
- Windows: `%USERPROFILE%\.vscode\extensions`
- Linux / Mac: `~/.vscode/extensions`

#Code completion status: BETA
The code completion in this extension is currently in beta. There are bugs, limitations, and requirements that still need to be worked out. There's an effort to standardize Haxe IDE support over at [snowkit/Tides](https://github.com/snowkit/tides). When this is ready, we'll integrate it (no need to duplicate effort and provide divergent experiences.)

#Current limitations:
Some features may require a forthcoming version of the Haxe compiler.

#Framework notes:
Some frameworks support the creation of .hxml files so you can use completion with your project.

**OpenFL's** display command will show the contents of the necessary .hxml file. On Windows, paste the output into a `build.hxml` file, or on Linux/Mac, you can create a `build.hxml` file in your project directory by running, e.g. `openfl display windows > build.hxml` (substitue the proper platform name for your project.)

**Kha** creates a build/project-<platform>.hxml file you can use.

**Flambe's** `haxe-flags` command will generate an .hxml file, e.g. `touch build.hxml && flambe haxe-flags >> ./build.hxml`

If anyone has info on **Snow** or other frameworks' .hxml file output, I'd be happy to add it here.
