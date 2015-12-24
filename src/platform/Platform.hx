package platform;

class Platform {
    public static var instance(default, null):Platform;

    public var pathSeparator:String;
    public var reversePathSeparator:String;
    public var executableExtension:String;

    function new() {    
    }

    public static function init(platformName:String) {
        if (instance == null) instance = new Platform();
        if (platformName=="win32") {
            instance.pathSeparator = "\\";
            instance.reversePathSeparator = "/";
            instance.executableExtension = ".exe";
        } else {
            instance.pathSeparator = "/";
            instance.reversePathSeparator = "\\";
            instance.executableExtension = "";            
        }
        return instance;
    }
}