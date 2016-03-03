# vscode-haxe
Haxe language extension for Visual Studio Code
by Patrick Le Clec'h, Jeff Ward, and Dan Korostelev

This extension provides:
- Syntax highlighting for .hx and .hxml files
- Code completion (work in progress)
- Function signature completion
- Jump / peek definition (ctrl-click / ctrl-hover)

Code Completion  | Peek Definition
------------- | -------------
<img src="https://lh3.googleusercontent.com/-ekHamgDiuZM/VnOd05QH04I/AAAAAAAAO4I/cfu718KBlO8/s1600/test.gif" width=400> | <img src="https://lh3.googleusercontent.com/-0cTfJGLLrpk/VoBPk4GAz_I/AAAAAAAAPKs/bWvpJBDjwnA/s400/definition_peek.gif" width=400>

#Install the Extension

For the stable version of this plugin, it is availble in the [VSCode Marketplace](https://marketplace.visualstudio.com/items/haxedevs.haxe). From within VSCode, press F1, type `ext install` and press enter, type `haxe` and it will be listed under publisher **Haxe Devs**.

For development versions, place the `vscode-haxe` directory in your `.vscode/extensions` directory:
- Windows: `%USERPROFILE%\.vscode\extensions`
- Linux / Mac: `~/.vscode/extensions`

#Project setup

Code completion and other features require an `.hxml` file in your project. Various frameworks (OpenFL, Snow, Kha, etc) can generate the `.hxml` file for you -- see the Framework notes section below.

By default the extension looks for a `build.hxml` in the root of the project, but you can set the location in your project's settings under File -> Preferences -> Workspace Settings. Add the following setting locating your `.hxml` file relative to the project directory:

```
{
    "haxe.haxeDefaultBuildFile": "path/to/build.hxml"
}
```

#Framework notes:
Some frameworks support the creation of `.hxml` files, which is necessary to run the Haxe code completion engine. Below is a list of how you can get an `.hxml` file from various frameworks.

Framework     | How to get .hxml                    | Example usage
------------- | ------------------------------------|------------------------
OpenFL        | `openfl display <platform>`         | `openfl display linux > build.hxml`
Snow          | `haxelib run flow info --hxml`      | `haxelib run flow info --hxml > build.hxml`
Kha           | See `build/project-<platform>.hxml` | Set location in Workspace Settings
Flambe        | `flambe haxe-flags`                 | `flambe haxe-flags > build.hxml`

Feel free to file an issue with details for other frameworks.

#Other notes and status

##Code completion status: BETA
The code completion in this extension is currently in beta. There are bugs, limitations, and requirements that still need to be worked out. There's an effort to standardize Haxe IDE support over at [snowkit/Tides](https://github.com/snowkit/tides). When this is ready, we'll integrate it (no need to duplicate effort and provide divergent experiences.)

##Current limitations:
Some features may require a forthcoming version of the Haxe compiler.
