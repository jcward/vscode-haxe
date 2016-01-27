package haxe;

import platform.Platform;

typedef HaxeConfigurationObject = {
    haxePath:String,
    haxelibPath:String,
    haxeDefaultBuildFile:String,
    haxeServerHost:String,
    haxeServerPort:Int,
    haxeDiagnoseOnSave:Bool,
    haxeDiagnosticDelay:Int,
    haxeCacheHaxelib:Bool,
    haxeVSCodeBuildFile:String,
    haxeTmpDirectory:String,
    haxeUseTmpAsWorkingDirectory:Bool,
    ?haxeExec:String, // filled at runtime
    ?haxelibExec:String // filled at runtime
};

class HaxeConfiguration {
    public static function addTrailingSep(path:String, platform:Platform) {
        if (path=="") return path;
        path = path.split(platform.reversePathSeparator).join(platform.pathSeparator);
        if (path.charAt(path.length-1) != platform.pathSeparator) path += platform.pathSeparator;
        return path;
    }
    public static function update(conf:HaxeConfigurationObject, platform:Platform) {
        var exec = "haxe" + platform.executableExtension;
        var tmp = addTrailingSep(conf.haxePath, platform);
        conf.haxePath = tmp;
        conf.haxeExec = tmp + exec;
        tmp = addTrailingSep(conf.haxelibPath, platform);
        conf.haxelibPath = tmp;
        conf.haxelibExec = tmp + "haxelib" + platform.executableExtension;
        return conf;
    }
}