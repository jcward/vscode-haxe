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
<img src="https://cloud.githubusercontent.com/assets/2192439/13637956/41882252-e5c7-11e5-947a-51e53a2eed46.gif" width=400> | <img src="https://cloud.githubusercontent.com/assets/2192439/13637971/542aa33a-e5c7-11e5-961d-d645e8f54df0.gif" width=400>

Function Signature | Build Error Reporting
------------------ | ------------------------
<img src="https://cloud.githubusercontent.com/assets/2192439/13637928/180ff594-e5c7-11e5-831a-4a3653e53d54.gif" width=400> | <img src="https://cloud.githubusercontent.com/assets/2192439/14265893/681877fe-fa81-11e5-84e3-a897da115374.png" width=400>


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

#Build errors
While the `vscode-haxe` extension doesn't "build and launch" projects out-of-the-box (it gets complicated with so many targets and frameworks), it does show a list of build errors thanks to the code completion compilation step. To see build errors, hit `CTRL-SHIFT-M` (or `CMD-SHIFT-M`), or click on the little warnings/errors icon in the lower-left corner of the VSCode window: ![image](https://cloud.githubusercontent.com/assets/2192439/14284678/b7c904b0-fb05-11e5-815c-b73f28dbc096.png)


Note: My personal vision of `vscode-haxe` is to be a language helper, while you can add project launch / debug support per your chosen framework / target if you choose. E.g. see [vscode-hxcpp-debug](https://github.com/jcward/vscode-hxcpp-debug) for an example of an extension that provides hxcpp launch and debug capabilities. But feel free to file an issue to discuss ideas.

#Framework notes
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

##Current limitations
Some features may require a forthcoming version of the Haxe compiler.

##Troubleshooting the completion features
You can start the haxe completion server by hand in verbose mode in a separate terminal. First, kill any existing Haxe completion servers, start it with `haxe -v --wait 6000`, and open your project in code. Here's an example in Linux:

```
>pkill haxe
>haxe -v --wait 6000
```
After starting my project, the console spits out the arguments and results of the completion server, e.g.:
```
Client connected
Waiting for data...
Reading 203 bytes
Processing Arguments [-D,display-details,--cwd,/home/jward/dev/test openfl,vscode-project.hxml,--no-output,--display,/home/jward/dev/test openfl/Source/Main.hx@485]
Parsed /home/jward/dev/test openfl/Source/Main.hx
Completion Response =
<list>
...
</list>

Stats = 1 files, 507 classes, 927 methods, 29 macros
Time spent : 0.210s
```

