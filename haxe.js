(function ($hx_exports) { "use strict";
var $estr = function() { return js_Boot.__string_rec(this,''); };
function $extend(from, fields) {
	function Inherit() {} Inherit.prototype = from; var proto = new Inherit();
	for (var name in fields) proto[name] = fields[name];
	if( fields.toString !== Object.prototype.toString ) proto.toString = fields.toString;
	return proto;
}
var EReg = function(r,opt) {
	opt = opt.split("u").join("");
	this.r = new RegExp(r,opt);
};
EReg.__name__ = true;
EReg.prototype = {
	match: function(s) {
		if(this.r.global) this.r.lastIndex = 0;
		this.r.m = this.r.exec(s);
		this.r.s = s;
		return this.r.m != null;
	}
	,matched: function(n) {
		if(this.r.m != null && n >= 0 && n < this.r.m.length) return this.r.m[n]; else throw new js__$Boot_HaxeError("EReg::matched");
	}
	,matchedPos: function() {
		if(this.r.m == null) throw new js__$Boot_HaxeError("No string matched");
		return { pos : this.r.m.index, len : this.r.m[0].length};
	}
	,matchSub: function(s,pos,len) {
		if(len == null) len = -1;
		if(this.r.global) {
			this.r.lastIndex = pos;
			this.r.m = this.r.exec(len < 0?s:HxOverrides.substr(s,0,pos + len));
			var b = this.r.m != null;
			if(b) this.r.s = s;
			return b;
		} else {
			var b1 = this.match(len < 0?HxOverrides.substr(s,pos,null):HxOverrides.substr(s,pos,len));
			if(b1) {
				this.r.s = s;
				this.r.m.index += pos;
			}
			return b1;
		}
	}
	,replace: function(s,by) {
		return s.replace(this.r,by);
	}
	,map: function(s,f) {
		var offset = 0;
		var buf = new StringBuf();
		do {
			if(offset >= s.length) break; else if(!this.matchSub(s,offset)) {
				buf.add(HxOverrides.substr(s,offset,null));
				break;
			}
			var p = this.matchedPos();
			buf.add(HxOverrides.substr(s,offset,p.pos - offset));
			buf.add(f(this));
			if(p.len == 0) {
				buf.add(HxOverrides.substr(s,p.pos,1));
				offset = p.pos + 1;
			} else offset = p.pos + p.len;
		} while(this.r.global);
		if(!this.r.global && offset > 0 && offset < s.length) buf.add(HxOverrides.substr(s,offset,null));
		return buf.b;
	}
	,__class__: EReg
};
var HaxeContext = function(context) {
	this.context = context;
	this.haxeProcess = null;
	this.configuration = Vscode.workspace.getConfiguration("haxe");
	platform_Platform.init(process.platform);
	haxe_HaxeConfiguration.update(this.configuration,platform_Platform.instance);
	this.initBuildFile();
	this.classPathsByLength = [];
	this.classPaths = [];
	this.classPathsReverse = [];
	this.useInternalBuildFile = false;
	this.useTmpDir = false;
	this.projectDir = Vscode.workspace.rootPath;
	this.tmpToRealMap = new haxe_ds_StringMap();
	this.insensitiveToSensitiveMap = new haxe_ds_StringMap();
	this.initTmpDir();
	this.createToolFile();
	this.diagnostics = Vscode.languages.createDiagnosticCollection("haxe");
	context.subscriptions.push(this.diagnostics);
	this.documentsState = new haxe_ds_StringMap();
	this.pendingSaves = new haxe_ds_StringMap();
	this.diagnosticStart = 0;
	this.lastDiagnostic = 1;
	this.checkForDiagnostic = false;
	this.checkTimer = new haxe_Timer(50);
	this.checkTimer.run = $bind(this,this.check);
	context.subscriptions.push(this);
};
HaxeContext.__name__ = true;
HaxeContext.languageID = function() {
	return "haxe";
};
HaxeContext.isDirty = function(ds) {
	return ds.document != null && ds.lastModification > ds.lastSave;
};
HaxeContext.isSaving = function(ds) {
	return ds.lastSave < ds.saveStartAt;
};
HaxeContext.isHaxeDocument = function(document) {
	return document.languageId == "haxe";
};
HaxeContext.saveStarted = function(ds) {
	ds.saveStartAt = new Date().getTime();
};
HaxeContext.saved = function(ds) {
	ds.lastSave = new Date().getTime();
};
HaxeContext.notSaved = function(ds) {
	ds.lastSave = ds.lastModification - 1;
};
HaxeContext.modified = function(ds) {
	ds.lastModification = new Date().getTime();
};
HaxeContext.path = function(ds) {
	if(ds.tmpPath == null) return ds.realPath; else return ds.tmpPath;
};
HaxeContext.prototype = {
	get_realWorkingDir: function() {
		return this.projectDir;
	}
	,get_workingDir: function() {
		if(this.useTmpDir && this.configuration.haxeUseTmpAsWorkingDirectory) return this.tmpProjectDir; else return this.projectDir;
	}
	,get_realBuildFile: function() {
		return this.configuration.haxeDefaultBuildFile;
	}
	,set_realBuildFile: function(path) {
		this.configuration.haxeDefaultBuildFile = path;
		return path;
	}
	,get_internalBuildFile: function() {
		return this.configuration.haxeVSCodeBuildFile;
	}
	,get_buildFile: function() {
		if(this.useInternalBuildFile) return this.configuration.haxeVSCodeBuildFile; else return this.configuration.haxeDefaultBuildFile;
	}
	,get_buildFileWithPath: function() {
		return js_node_Path.join(this.get_workingDir(),this.get_buildFile());
	}
	,get_realBuildFileWithPath: function() {
		return js_node_Path.join(this.projectDir,this.configuration.haxeDefaultBuildFile);
	}
	,get_internalBuildFileWithPath: function() {
		return js_node_Path.join(this.get_workingDir(),this.configuration.haxeVSCodeBuildFile);
	}
	,get_diagnosticRunning: function() {
		return this.diagnosticStart > this.lastDiagnostic;
	}
	,diagnosticStarted: function() {
		this.diagnosticStart = new Date().getTime();
	}
	,diagnosticEnded: function() {
		this.lastDiagnostic = new Date().getTime();
	}
	,needDiagnostic: function(ds) {
		return ds.lastSave > this.lastDiagnostic;
	}
	,getPackageFromString: function(path) {
		var npath;
		if(platform_Platform.instance.isWin) npath = path.toLowerCase(); else npath = path;
		var _g = 0;
		var _g1 = this.classPathsByLength;
		while(_g < _g1.length) {
			var cp = _g1[_g];
			++_g;
			var tmp = npath.split(cp);
			if(tmp.length > 1) {
				tmp.shift();
				var fileAndPath = HxOverrides.substr(path,cp.length,null);
				var dirs = fileAndPath.split(js_node_Path.sep);
				var file = dirs.pop();
				return { path : path, pack : dirs.join("."), fileAndPath : fileAndPath, file : file};
			}
		}
		return null;
	}
	,getPackageFromDS: function(ds) {
		return this.getPackageFromString(js_node_Path.normalize(ds.realPath));
	}
	,tmpToReal: function(fileName) {
		var nfile = Tool.normalize(fileName);
		var tmp = this.tmpToRealMap.get(nfile);
		if(tmp != null) return tmp;
		if(platform_Platform.instance.isWin) {
			tmp = this.insensitiveToSensitiveMap.get(nfile);
			if(tmp != null) return tmp;
		}
		if(this.useTmpDir) {
			var dirs = fileName.split(this.tmpProjectDir);
			if(dirs.length == 2) {
				var file = dirs.pop();
				var cp = this.resolveFile(file);
				if(cp != null) {
					fileName = this.insensitiveToSensitive(js_node_Path.join(cp,file));
					this.tmpToRealMap.set(nfile,fileName);
				}
			}
		}
		return fileName;
	}
	,insensitiveToSensitive: function(file) {
		if(!platform_Platform.instance.isWin) return file;
		var nfile = Tool.normalize(file);
		var tmp = this.insensitiveToSensitiveMap.get(nfile);
		if(tmp != null) return tmp;
		var paths = nfile.split(js_node_Path.sep);
		var fileName = paths.pop();
		var path = paths.join(js_node_Path.sep);
		var paths1 = [];
		try {
			paths1 = js_node_Fs.readdirSync(path);
		} catch( e ) {
			if (e instanceof js__$Boot_HaxeError) e = e.val;
			if(this.configuration.haxeUseTmpAsWorkingDirectory) {
				paths1 = path.split(this.get_workingDir());
				paths1.shift();
				paths1 = [this.projectDir,".."].concat(paths1);
				path = paths1.join(js_node_Path.sep);
				paths1 = js_node_Fs.readdirSync(path);
			}
		}
		var _g = 0;
		while(_g < paths1.length) {
			var p = paths1[_g];
			++_g;
			if(p.toLowerCase() == fileName) {
				file = js_node_Path.join(path,p);
				this.insensitiveToSensitiveMap.set(nfile,file);
				break;
			}
		}
		return file;
	}
	,initBuildFile: function() {
		var builds = [this.configuration.haxeDefaultBuildFile];
		try {
			var _g = 0;
			while(_g < builds.length) {
				var build = builds[_g];
				++_g;
				var bf = js_node_Path.join(this.projectDir,build);
				try {
					js_node_Fs.accessSync(bf,js_node_Fs.F_OK);
					this.configuration.haxeDefaultBuildFile = build;
					build;
					return;
				} catch( e ) {
					if (e instanceof js__$Boot_HaxeError) e = e.val;
				}
			}
			var fd = js_node_Fs.openSync(this.get_realBuildFileWithPath(),"a");
			js_node_Fs.closeSync(fd);
		} catch( e1 ) {
			if (e1 instanceof js__$Boot_HaxeError) e1 = e1.val;
		}
	}
	,diagnoseIfAllowed: function() {
		this.diagnose(1);
	}
	,getDirtyDocuments: function() {
		var dd = [];
		var $it0 = this.documentsState.iterator();
		while( $it0.hasNext() ) {
			var ds = $it0.next();
			if(ds.document != null && ds.lastModification > ds.lastSave) dd.push(ds);
		}
		return dd;
	}
	,createTmpFile: function(ds) {
		if(this.useTmpDir && ds.document != null && ds.tmpPath == null) {
			var path = js_node_Path.normalize(ds.realPath);
			var tmp = this.getPackageFromString(path);
			if(tmp != null) {
				var file = tmp.fileAndPath;
				var tmpFile = js_node_Path.join(this.tmpProjectDir,file);
				var dirs = file.split(js_node_Path.sep);
				dirs.pop();
				if(dirs.length > 0) {
					dirs = [this.tmpProjectDir].concat(dirs);
					try {
						Tool.mkDirsSync(dirs);
					} catch( e ) {
						if (e instanceof js__$Boot_HaxeError) e = e.val;
						Vscode.window.showErrorMessage("Can't create tmp directory " + tmpFile);
					}
				}
				try {
					js_node_Fs.writeFileSync(tmpFile,ds.text == null?ds.document.getText():ds.text,"utf8");
					ds.text = null;
					ds.tmpPath = tmpFile;
					var key = Tool.normalize(tmpFile);
					this.tmpToRealMap.set(key,path);
				} catch( e1 ) {
					if (e1 instanceof js__$Boot_HaxeError) e1 = e1.val;
					Vscode.window.showErrorMessage("Can't save temporary file " + tmpFile);
				}
			}
		}
	}
	,resolveFile: function(file) {
		var _g = 0;
		var _g1 = this.classPathsReverse;
		while(_g < _g1.length) {
			var cp = _g1[_g];
			++_g;
			var fn = js_node_Path.join(cp,file);
			try {
				js_node_Fs.accessSync(fn,js_node_Fs.F_OK);
				return cp;
			} catch( e ) {
				if (e instanceof js__$Boot_HaxeError) e = e.val;
			}
		}
		return null;
	}
	,addClassPath: function(cp) {
		if(!js_node_Path.isAbsolute(cp)) cp = js_node_Path.join(this.projectDir,cp);
		cp = Tool.normalize(cp + js_node_Path.sep);
		this.classPaths.push(cp);
		this.classPathsByLength = this.classPaths.concat([]);
		this.classPathsReverse = this.classPaths.concat([]);
		this.classPathsByLength.sort(function(a,b) {
			return b.length - a.length;
		});
		this.classPathsReverse.reverse();
		return cp;
	}
	,clearClassPaths: function() {
		this.classPathsByLength = [];
		this.classPaths = [];
		this.classPathsReverse = [];
		this.addClassPath(".");
	}
	,resetDirtyDocuments: function() {
		var dd = [];
		var $it0 = this.documentsState.iterator();
		while( $it0.hasNext() ) {
			var ds = $it0.next();
			if(ds.document == null) continue;
			if(ds.document.isDirty) {
				ds.lastSave = ds.lastModification - 1;
				dd.push(ds);
			}
		}
		return dd;
	}
	,resetSavedDocuments: function() {
		var t = new Date().getTime();
		var $it0 = this.documentsState.iterator();
		while( $it0.hasNext() ) {
			var ds = $it0.next();
			if(ds.document == null) continue;
			ds.lastSave = t;
		}
	}
	,send: function(categorie,restoreCommandLine,retry,priority) {
		if(priority == null) priority = 0;
		if(retry == null) retry = 1;
		if(restoreCommandLine == null) restoreCommandLine = false;
		var _g = this;
		return new Promise(function(accept,reject) {
			var trying = retry;
			var needResetSave = false;
			var onData;
			var onData1 = null;
			onData1 = function(m) {
				if(needResetSave) {
					_g.resetSavedDocuments();
					needResetSave = false;
				}
				if(m.severity == 3) {
					if(restoreCommandLine) _g.client.cmdLine.restore();
					reject(m);
					return;
				}
				var e = m.error;
				if(e == null && m.severity != 2) {
					if(restoreCommandLine) _g.client.cmdLine.restore();
					accept(m);
				} else if(e != null) {
					trying--;
					if(trying < 0) {
						if(restoreCommandLine) _g.client.cmdLine.restore();
						reject(m);
					} else _g.launchServer().then(function(port) {
						_g.client.sendAll(onData1,false,categorie,10000,false);
					},function(port1) {
						if(restoreCommandLine) _g.client.cmdLine.restore();
						reject(m);
					});
				} else {
					if(restoreCommandLine) _g.client.cmdLine.restore();
					reject(m);
				}
			};
			onData = onData1;
			_g.client.sendAll(onData,false,categorie,0,false);
		});
	}
	,saveDocument: function(ds) {
		return this.saveFullDocument(ds);
	}
	,saveFullDocument: function(ds) {
		var _g = this;
		if(this.client.isPatchAvailable) return new Promise(function(accept,reject) {
			if(!(ds.document != null && ds.lastModification > ds.lastSave)) accept(ds); else _g.patchFullDocument(ds).then(function(ds1) {
				accept(ds1);
			},function(ds2) {
				reject(ds2);
			});
		}); else return new Promise(function(accept1,reject1) {
			var document = ds.document;
			if(document == null) reject1(ds);
			if(_g.useTmpDir && ds.tmpPath != null) {
				try {
					ds.saveStartAt = new Date().getTime();
					js_node_Fs.writeFile(ds.tmpPath,ds.text == null?ds.document.getText():ds.text,"utf8",function(e) {
						ds.text = null;
						if(e != null) reject1(ds); else {
							_g.onSaveDocument(ds.document);
							accept1(ds);
						}
					});
				} catch( e1 ) {
					if (e1 instanceof js__$Boot_HaxeError) e1 = e1.val;
				}
				return;
			} else if(document.isDirty) {
				var path;
				if(ds.tmpPath == null) path = ds.realPath; else path = ds.tmpPath;
				var pf = _g.pendingSaves.get(path);
				var npf = { ds : ds, reject : reject1, accept : accept1, lastModification : ds.lastModification};
				if(pf != null) {
					pf.reject(pf.ds);
					_g.pendingSaves.set(path,npf);
				} else {
					_g.pendingSaves.set(path,npf);
					var doSave;
					var doSave1 = null;
					doSave1 = function(ds3) {
						ds3.saveStartAt = new Date().getTime();
						ds3.document.save().then(function(saved) {
							var path1;
							if(ds3.tmpPath == null) path1 = ds3.realPath; else path1 = ds3.tmpPath;
							var pf1 = _g.pendingSaves.get(path1);
							if(pf1 != null) {
								ds3 = pf1.ds;
								if(ds3.lastModification > pf1.lastModification) {
									pf1.lastModification = ds3.lastModification;
									doSave1(pf1.ds);
									return;
								} else _g.pendingSaves.remove(path1);
							}
							if(saved) {
								ds3.lastSave = new Date().getTime();
								pf1.accept(ds3);
							} else {
								ds3.saveStartAt = 0;
								pf1.reject(ds3);
							}
						});
					};
					doSave = doSave1;
					doSave(ds);
				}
			} else {
				ds.lastSave = new Date().getTime();
				accept1(ds);
			}
		});
	}
	,check: function() {
		var _g2 = this;
		var time = new Date().getTime();
		if(this.checkForDiagnostic && !(this.diagnosticStart > this.lastDiagnostic)) {
			var dlt = time - this.lastDiagnostic;
			if(dlt >= this.configuration.haxeDiagnosticDelay) {
				if(this.client.isPatchAvailable) {
					var dd = this.getDirtyDocuments();
					var cnt = dd.length;
					var needDiagnose = false;
					var _g1 = 0;
					var _g = dd.length;
					while(_g1 < _g) {
						var i = _g1++;
						var ds = dd[i];
						var document = ds.document;
						cnt--;
						needDiagnose = needDiagnose || ds.lastSave > this.lastDiagnostic;
						this.diagnostics["delete"](document.uri);
						this.patchFullDocument(ds).then(function(ds1) {
							if(cnt == 0 && needDiagnose) _g2.diagnose(1);
						});
					}
				} else {
					var isDirty = false;
					var needDiagnose1 = false;
					var $it0 = this.documentsState.iterator();
					while( $it0.hasNext() ) {
						var ds2 = $it0.next();
						var document1 = ds2.document;
						if(document1 == null) continue;
						if(ds2.document != null && ds2.lastModification > ds2.lastSave) {
							if(!(ds2.lastSave < ds2.saveStartAt)) {
								isDirty = true;
								ds2.diagnoseOnSave = false;
								this.diagnostics["delete"](ds2.document.uri);
								this.saveFullDocument(ds2);
							}
						} else needDiagnose1 = needDiagnose1 || ds2.lastSave > this.lastDiagnostic;
					}
					if(!isDirty) {
						this.checkForDiagnostic = false;
						if(needDiagnose1) this.diagnose(1);
					}
				}
			}
		}
	}
	,init: function() {
		var host = this.configuration.haxeServerHost;
		var port = this.configuration.haxeServerPort;
		this.client = new haxe_HaxeClient(host,port);
		this.context.subscriptions.push(Vscode.workspace.onDidChangeTextDocument($bind(this,this.changePatch)));
		this.changeDebouncer = new Debouncer(300,$bind(this,this.changePatchs));
		this.context.subscriptions.push(Vscode.workspace.onDidOpenTextDocument($bind(this,this.onOpenDocument)));
		this.context.subscriptions.push(Vscode.workspace.onDidSaveTextDocument($bind(this,this.onSaveDocument)));
		this.context.subscriptions.push(Vscode.workspace.onDidCloseTextDocument($bind(this,this.onCloseDocument)));
		this.completionHandler = new features_CompletionHandler(this);
		this.definitionHandler = new features_DefinitionHandler(this);
		this.signatureHandler = new features_SignatureHandler(this);
		return this.launchServer();
	}
	,initTmpDir: function() {
		if(this.configuration.haxeTmpDirectory != "") {
			this.tmpDir = haxe_HaxeConfiguration.addTrailingSep(this.configuration.haxeTmpDirectory,platform_Platform.instance);
			var hash = haxe_crypto_Sha1.encode(this.projectDir);
			this.tmpProjectDir = Tool.normalize(js_node_Path.join(this.tmpDir,hash));
			try {
				Tool.mkDirSync(this.tmpProjectDir);
				this.useTmpDir = true;
			} catch( e ) {
				if (e instanceof js__$Boot_HaxeError) e = e.val;
				this.unuseTmpDir();
				Vscode.window.showErrorMessage("Can't create temporary directory " + this.tmpProjectDir);
			}
		} else this.unuseTmpDir();
	}
	,unuseTmpDir: function() {
		this.useTmpDir = false;
		this.tmpProjectDir = null;
	}
	,createToolFile: function() {
		if(this.useTmpDir) js_node_Fs.writeFileSync(js_node_Path.join(this.tmpProjectDir,"VSCTool.hx"),"package;\r\nimport haxe.macro.Context;\r\nclass VSCTool {\r\n    macro public static function fatalError(){\r\n        Context.fatalError('@fatalError', Context.currentPos());\r\n        return macro null;\r\n    }\r\n}","utf8");
	}
	,removeToolFile: function() {
		if(this.useTmpDir) js_node_Fs.unlinkSync(js_node_Path.join(this.tmpProjectDir,"VSCTool.hx"));
	}
	,launchServer: function() {
		var _g = this;
		var host = this.configuration.haxeServerHost;
		var port = this.configuration.haxeServerPort;
		this.client.host = host;
		this.client.port = port;
		return new Promise(function(resolve,reject) {
			var incPort = 0;
			var onData;
			var onData1 = null;
			onData1 = function(data) {
				if(data.isHaxeServer) {
					_g.configuration.haxeServerPort = port;
					_g.client.port = port;
					Vscode.window.showInformationMessage("Using " + _g.client.version + " " + (_g.client.isPatchAvailable?"--patch":"non-patching") + " completion server at " + _g.configuration.haxeServerHost + " on port " + port);
					if(data.isPatchAvailable) {
						var cl = _g.client.cmdLine.save();
						var dd = _g.resetDirtyDocuments();
						if(dd.length > 0) {
							var _g1 = 0;
							while(_g1 < dd.length) {
								var ds = dd[_g1];
								++_g1;
								cl.beginPatch(ds.tmpPath == null?ds.realPath:ds.tmpPath).replace(ds.document.getText());
							}
							_g.client.sendAll(function(m) {
								resolve(port);
							},true,null,30000);
							return;
						}
					}
					resolve(port);
					return;
				} else {
					_g.killServer();
					port += incPort;
					incPort = 1;
					_g.haxeProcess = js_node_ChildProcess.spawn(_g.configuration.haxeExec,["--wait","" + port]);
					if(_g.haxeProcess.pid > 0) haxe_Timer.delay(function() {
						_g.client.port = port;
						_g.client.infos(onData1);
					},800);
					_g.haxeProcess.on("error",function(err) {
						_g.haxeProcess = null;
						Vscode.window.showErrorMessage("Can't spawn " + _g.configuration.haxeExec + " process\n" + err.message);
						reject(err);
					});
				}
			};
			onData = onData1;
			_g.client.infos(onData);
		});
	}
	,killServer: function() {
		if(this.haxeProcess != null) {
			this.haxeProcess.kill("SIGKILL");
			js_node_ChildProcess.spawn("kill",["-9","" + this.haxeProcess.pid]);
			this.haxeProcess = null;
		}
	}
	,dispose: function() {
		Vscode.window.showInformationMessage("Got dispose!");
		if(this.checkTimer != null) {
			this.checkTimer.stop();
			this.checkTimer = null;
		}
		if(this.client.isServerAvailable && this.client.isPatchAvailable) {
			var cl = this.client.cmdLine;
			var _g = 0;
			var _g1 = Vscode.window.visibleTextEditors;
			while(_g < _g1.length) {
				var editor = _g1[_g];
				++_g;
				var path = editor.document.uri.fsPath;
				this.documentsState.remove(path);
				cl.beginPatch(path).remove();
			}
			this.client.sendAll(null);
		}
		this.killServer();
		this.client = null;
		this.removeToolFile();
		return null;
	}
	,applyDiagnostics: function(message) {
		if(message.severity == 3) {
			this.lastDiagnostic = new Date().getTime();
			return;
		}
		this.diagnostics.clear();
		var all = new haxe_ds_StringMap();
		var _g = 0;
		var _g1 = message.infos;
		while(_g < _g1.length) {
			var info = _g1[_g];
			++_g;
			var diags = all.get(info.fileName);
			if(diags == null) {
				diags = [];
				all.set(info.fileName,diags);
			}
			var diag = new Vscode.Diagnostic(Tool.toVSCRange(info),info.message,Tool.toVSCSeverity(message.severity));
			diags.push(diag);
		}
		var $it0 = all.keys();
		while( $it0.hasNext() ) {
			var fileName = $it0.next();
			var diags1;
			diags1 = __map_reserved[fileName] != null?all.getReserved(fileName):all.h[fileName];
			fileName = this.tmpToReal(fileName);
			var url = Vscode.Uri.file(fileName);
			if(diags1 == null) {
				this.diagnostics.set(url,[]);
				continue;
			}
			this.diagnostics.set(url,diags1);
		}
		this.lastDiagnostic = new Date().getTime();
	}
	,getDocumentState: function(path,document) {
		var npath = Tool.normalize(path);
		var ds = this.documentsState.get(npath);
		if(ds != null) {
			if(document != null) ds.document = document;
			if(this.useTmpDir && ds.tmpPath == null) this.createTmpFile(ds);
		} else {
			var t = new Date().getTime();
			ds = { realPath : path, saveStartAt : 0, lastSave : t, lastModification : 0, document : document, diagnoseOnSave : this.configuration.haxeDiagnoseOnSave, tmpPath : null, text : null};
			this.documentsState.set(path,ds);
			if(npath != path) this.documentsState.set(npath,ds);
			this.createTmpFile(ds);
		}
		return ds;
	}
	,onCloseDocument: function(document) {
		var path = document.uri.fsPath;
		var ds = this.getDocumentState(path);
		ds.document = null;
		ds.realPath = null;
		ds.tmpPath = null;
		this.documentsState.remove(path);
		var key = Tool.normalize(path);
		this.documentsState.remove(key);
		if(this.client.isPatchAvailable) {
			this.client.cmdLine.save().beginPatch(path).remove();
			this.client.sendAll(null,true);
		}
		this.diagnostics["delete"](document.uri);
	}
	,onOpenDocument: function(document) {
		var path = document.uri.fsPath;
		var ds = this.getDocumentState(path,document);
		this.removeAndDiagnoseDocument(document);
	}
	,patchFullDocument: function(ds) {
		var _g = this;
		return new Promise(function(accept,reject) {
			var document = ds.document;
			if(document == null) return reject(ds);
			_g.client.cmdLine.save().beginPatch(ds.tmpPath == null?ds.realPath:ds.tmpPath).replace(document.getText());
			ds.saveStartAt = new Date().getTime();
			_g.send(null,true,1).then(function(m) {
				ds.lastSave = new Date().getTime();
				accept(ds);
			},function(m1) {
				reject(ds);
			});
		});
	}
	,onSaveDocument: function(document) {
		var path = document.uri.fsPath;
		var ds = this.getDocumentState(path,document);
		ds.lastSave = new Date().getTime();
		if(ds.diagnoseOnSave) this.removeAndDiagnoseDocument(document);
		ds.diagnoseOnSave = this.configuration.haxeDiagnoseOnSave;
	}
	,diagnose: function(retry) {
		var _g = this;
		this.diagnosticStart = new Date().getTime();
		var cl = this.client.cmdLine.save().cwd(this.get_workingDir()).hxml(this.get_buildFile()).noOutput();
		if(this.lastDSEdited != null && this.lastDSEdited.lastSave > this.lastDiagnostic) {
			var tmp = this.getPackageFromDS(this.lastDSEdited);
			if(tmp != null) cl.custom("",tmp.fileAndPath);
		}
		this.send("diagnostic@1",true,retry).then(function(m) {
			_g.applyDiagnostics(m);
		},function(m1) {
			if(m1.error != null) Vscode.window.showErrorMessage(m1.error.message);
			_g.applyDiagnostics(m1);
		});
	}
	,removeAndDiagnoseDocument: function(document) {
		this.diagnostics["delete"](document.uri);
		var path = document.uri.fsPath;
		if(this.client.isPatchAvailable) this.client.cmdLine.beginPatch(path).remove();
		this.diagnose(1);
	}
	,changePatch: function(event) {
		var document = event.document;
		if(event.contentChanges.length == 0 || !(document.languageId == "haxe")) return;
		this.checkForDiagnostic = false;
		var path = document.uri.fsPath;
		var ds = this.getDocumentState(path,document);
		ds.document = document;
		ds.lastModification = new Date().getTime();
		this.lastDSEdited = ds;
		this.changeDebouncer.debounce(event);
	}
	,changePatchs: function(events) {
		if(events.length == 0) return;
		if(!this.useTmpDir) {
			var editor = Vscode.window.activeTextEditor;
			var document = editor.document;
			if(document.languageId != "haxe") return;
			var lastEvent = events[events.length - 1];
			var changes = lastEvent.contentChanges;
			if(changes.length == 0) return;
			var lastChange = changes[changes.length - 1];
			var cursor = editor.selection.active;
			var line = document.lineAt(cursor);
			var text = line.text;
			var char_pos = cursor.character - 1;
			var len = text.length;
			var insertText = lastChange.text;
			var lastLen = insertText.length;
			if(lastLen > 0) {
				if(HaxeContext.reWS.match(insertText.charAt(lastLen - 1))) {
					var ei = char_pos + 1;
					while(ei < len) {
						if(!HaxeContext.reWS.match(text.charAt(ei))) break;
						ei++;
					}
					this.checkForDiagnostic = ei < len;
				} else this.checkForDiagnostic = true;
				return;
			}
			if(lastChange.rangeLength > 0) {
				var ei1 = char_pos;
				while(ei1 < len) {
					if(!HaxeContext.reWS.match(text.charAt(ei1))) break;
					ei1++;
				}
				this.checkForDiagnostic = ei1 < len;
				return;
			}
		} else this.checkForDiagnostic = true;
	}
	,__class__: HaxeContext
};
var HxOverrides = function() { };
HxOverrides.__name__ = true;
HxOverrides.dateStr = function(date) {
	var m = date.getMonth() + 1;
	var d = date.getDate();
	var h = date.getHours();
	var mi = date.getMinutes();
	var s = date.getSeconds();
	return date.getFullYear() + "-" + (m < 10?"0" + m:"" + m) + "-" + (d < 10?"0" + d:"" + d) + " " + (h < 10?"0" + h:"" + h) + ":" + (mi < 10?"0" + mi:"" + mi) + ":" + (s < 10?"0" + s:"" + s);
};
HxOverrides.cca = function(s,index) {
	var x = s.charCodeAt(index);
	if(x != x) return undefined;
	return x;
};
HxOverrides.substr = function(s,pos,len) {
	if(pos != null && pos != 0 && len != null && len < 0) return "";
	if(len == null) len = s.length;
	if(pos < 0) {
		pos = s.length + pos;
		if(pos < 0) pos = 0;
	} else if(len < 0) len = s.length + len - pos;
	return s.substr(pos,len);
};
HxOverrides.iter = function(a) {
	return { cur : 0, arr : a, hasNext : function() {
		return this.cur < this.arr.length;
	}, next : function() {
		return this.arr[this.cur++];
	}};
};
var HxmlContext = function(hxContext) {
	this.hxContext = hxContext;
	var disposable = Vscode.languages.registerHoverProvider("hxml",{ provideHover : $bind(this,this.onHover)});
	this.hxContext.context.subscriptions.push(disposable);
	this.haxelibCache = new haxe_ds_StringMap();
	this.buildWatcher = Vscode.workspace.createFileSystemWatcher(hxContext.get_realBuildFileWithPath(),true,false,true);
	this.buildWatcher.onDidChange($bind(this,this.onBuildChange));
	this.makeInternalBuild();
	new features_hxml_CompletionHandler(this);
	this.hxContext.context.subscriptions.push(this);
};
HxmlContext.__name__ = true;
HxmlContext.languageID = function() {
	return "hxml";
};
HxmlContext.isHxmlDocument = function(document) {
	return document.languageId == "hxml";
};
HxmlContext.prototype = {
	get_context: function() {
		return this.hxContext.context;
	}
	,get_client: function() {
		return this.hxContext.client;
	}
	,onBuildChange: function(e) {
		this.haxelibCache = new haxe_ds_StringMap();
		this.makeInternalBuild();
	}
	,dispose: function() {
		this.buildWatcher.dispose();
		js_node_Fs.unlinkSync(this.hxContext.get_internalBuildFileWithPath());
	}
	,makeInternalBuild: function() {
		this.hxContext.clearClassPaths();
		var lines = this.read(this.hxContext.get_realBuildFileWithPath());
		var newLines = this.parseLines(lines);
		if(newLines != null) lines = newLines;
		this.hxContext.useInternalBuildFile = true;
		js_node_Fs.writeFileSync(this.hxContext.get_internalBuildFileWithPath(),newLines.join("\n"),"utf8");
	}
	,read: function(fileName) {
		try {
			var txt = js_node_Fs.readFileSync(fileName,"utf8");
			var lines = txt.split("\n");
			return lines;
		} catch( e ) {
			if (e instanceof js__$Boot_HaxeError) e = e.val;
			Vscode.window.showErrorMessage("Can't read file " + fileName);
			return [];
		}
	}
	,parseLines: function(lines) {
		var newLines = ["#automatically generated do not edit","#@date " + Std.string(new Date())];
		newLines = this._parseLines(lines,newLines);
		if(this.hxContext.useTmpDir && newLines != null) {
			var hasEach = false;
			var hasNext = false;
			lines = [];
			var _g = 0;
			while(_g < newLines.length) {
				var line = newLines[_g];
				++_g;
				if(HxmlContext.reEach.match(line)) {
					hasEach = true;
					lines.push("-cp " + this.hxContext.tmpProjectDir);
					lines.push(line);
				} else if(!hasNext && HxmlContext.reNext.match(line)) {
					hasNext = true;
					if(!hasEach) {
						lines.push("-cp " + this.hxContext.tmpProjectDir);
						lines.push("--each");
					}
					lines.push("");
					lines.push(line);
				} else lines.push(line);
			}
			if(!hasEach && !hasNext) lines.push("-cp " + this.hxContext.tmpProjectDir);
		}
		return lines;
	}
	,_parseLines: function(lines,acc,isLib) {
		if(isLib == null) isLib = false;
		if(acc == null) acc = [];
		var _g = 0;
		while(_g < lines.length) {
			var line = lines[_g];
			++_g;
			line = StringTools.trim(line);
			if(line == "") {
				acc.push("\n");
				continue;
			}
			if(this.hxContext.configuration.haxeCacheHaxelib && HxmlContext.reLibOption.match(line)) {
				acc.push("#@begin-cache " + line);
				var ret = this.cacheLibData(HxmlContext.reLibOption.matched(1),acc);
				if(ret == null) return null;
				if(ret[ret.length - 1] == "\n") ret.pop();
				acc = ret;
				acc.push("#@end-cache");
			} else if(HxmlContext.reCpOption.match(line)) {
				var cp = this.hxContext.addClassPath(HxmlContext.reCpOption.matched(1));
				acc.push("-cp " + cp);
			} else if(!isLib) acc.push(line); else {
				var _g1 = line.charAt(0);
				switch(_g1) {
				case "-":case "#":
					acc.push(line);
					break;
				default:
					var cp1 = this.hxContext.addClassPath(line);
					acc.push("-cp " + cp1);
				}
			}
		}
		return acc;
	}
	,cacheLibData: function(libName,datas) {
		var d = this.haxelibCache.get(libName);
		if(d != null) return datas.concat(d);
		this.haxelibCache.set(libName,[]);
		var exec = this.hxContext.configuration.haxelibExec;
		var out = js_node_ChildProcess.spawnSync(exec,["path",libName],{ encoding : "utf8"});
		if(out.pid == 0) {
			Vscode.window.showErrorMessage("Cant find " + exec);
			return null;
		}
		if(out.status == 1) {
			Vscode.window.showErrorMessage(out.stdout);
			return null;
		}
		var lines = out.stdout.split("\n");
		lines = this._parseLines(lines,datas,true);
		this.haxelibCache.set(libName,lines);
		return lines;
	}
	,onHover: function(document,position,cancelToken) {
		var sHover = "";
		var client = this.hxContext.client;
		if(client != null) {
			var text = document.lineAt(position).text;
			if(HxmlContext.reCheckOption.match(text)) {
				var prefix = HxmlContext.reCheckOption.matched(1);
				var name = HxmlContext.reCheckOption.matched(3);
				var param = HxmlContext.reCheckOption.matched(5);
				if(prefix == "-" && name == "D") {
					if(HxmlContext.reDefineParam.match(param)) {
						var defineName = HxmlContext.reDefineParam.matched(1);
						var define = client.definesByName.get(defineName);
						if(define != null) sHover = define.doc;
					}
				} else {
					var option = client.optionsByName.get(name);
					if(option != null) sHover = option.doc;
				}
			} else if(HxmlContext.reMain.match(text)) sHover = "Main file : " + HxmlContext.reMain.matched(1);
		}
		return new Vscode.Hover(sHover);
	}
	,__class__: HxmlContext
};
var Main = function() { };
Main.__name__ = true;
Main.main = $hx_exports.activate = function(context) {
	var hc = new HaxeContext(context);
	hc.init();
	new HxmlContext(hc);
};
Math.__name__ = true;
var Socket = function() {
	this.s = new js_node_net_Socket();
	this.reset();
};
Socket.__name__ = true;
Socket.prototype = {
	reset: function() {
		this.datas = [];
		this.isConnected = false;
		this.isClosed = false;
		this.error = null;
	}
	,onConnect: function(callback) {
		if(callback != null) callback(this);
	}
	,onError: function(err,callback) {
		if(callback != null) callback(this,err);
	}
	,onData: function(data,callback) {
		data = data.toString();
		this.datas.push(data);
		if(callback != null) callback(this,data);
	}
	,onClose: function(callback) {
		this.isConnected = false;
		this.isClosed = true;
		if(callback != null) callback(this);
	}
	,connect: function(host,port,onConnect,onData,onError,onClose) {
		var _g = this;
		this.error = null;
		this.s.on("error",function(err) {
			_g.error = err;
			_g.onError(err,onError);
		});
		this.s.on("data",function(data) {
			_g.onData(data,onData);
		});
		this.s.on("close",function() {
			_g.onClose(onClose);
		});
		this.s.connect(port,host,function() {
			_g.isConnected = true;
			_g.onConnect(onConnect);
		});
	}
	,write: function(text) {
		return this.s.write(text);
	}
	,readAll: function() {
		return this.s.read();
	}
	,close: function() {
		this.s.destroy();
	}
	,__class__: Socket
};
var Std = function() { };
Std.__name__ = true;
Std.string = function(s) {
	return js_Boot.__string_rec(s,"");
};
Std.parseInt = function(x) {
	var v = parseInt(x,10);
	if(v == 0 && (HxOverrides.cca(x,1) == 120 || HxOverrides.cca(x,1) == 88)) v = parseInt(x);
	if(isNaN(v)) return null;
	return v;
};
var StringBuf = function() {
	this.b = "";
};
StringBuf.__name__ = true;
StringBuf.prototype = {
	add: function(x) {
		this.b += Std.string(x);
	}
	,__class__: StringBuf
};
var StringTools = function() { };
StringTools.__name__ = true;
StringTools.isSpace = function(s,pos) {
	var c = HxOverrides.cca(s,pos);
	return c > 8 && c < 14 || c == 32;
};
StringTools.ltrim = function(s) {
	var l = s.length;
	var r = 0;
	while(r < l && StringTools.isSpace(s,r)) r++;
	if(r > 0) return HxOverrides.substr(s,r,l - r); else return s;
};
StringTools.rtrim = function(s) {
	var l = s.length;
	var r = 0;
	while(r < l && StringTools.isSpace(s,l - r - 1)) r++;
	if(r > 0) return HxOverrides.substr(s,0,l - r); else return s;
};
StringTools.trim = function(s) {
	return StringTools.ltrim(StringTools.rtrim(s));
};
StringTools.hex = function(n,digits) {
	var s = "";
	var hexChars = "0123456789ABCDEF";
	do {
		s = hexChars.charAt(n & 15) + s;
		n >>>= 4;
	} while(n > 0);
	if(digits != null) while(s.length < digits) s = "0" + s;
	return s;
};
var Tool = function() { };
Tool.__name__ = true;
Tool.displayAsInfo = function(s) {
	Vscode.window.showInformationMessage(s);
};
Tool.displayAsError = function(s) {
	Vscode.window.showErrorMessage(s);
};
Tool.displayAsWarning = function(s) {
	Vscode.window.showWarningMessage(s);
};
Tool.getTime = function() {
	return new Date().getTime();
};
Tool.mkDirSync = function(path) {
	try {
		js_node_Fs.mkdirSync(path);
	} catch( e ) {
		if (e instanceof js__$Boot_HaxeError) e = e.val;
		if(e.code != "EEXIST") throw new js__$Boot_HaxeError(e);
	}
};
Tool.mkDirsSync = function(dirs) {
	var path = "";
	var _g = 0;
	while(_g < dirs.length) {
		var dir = dirs[_g];
		++_g;
		path = js_node_Path.join(path,dir);
		Tool.mkDirSync(path);
	}
};
Tool.normalize = function(path) {
	path = js_node_Path.normalize(path);
	if(platform_Platform.instance.isWin) path = path.toLowerCase();
	return path;
};
Tool.byteLength = function(str) {
	return js_node_buffer_Buffer.byteLength(str,null);
};
Tool.byte_pos = function(text,char_pos) {
	if(char_pos == text.length) return js_node_buffer_Buffer.byteLength(text,null); else return Tool.byteLength(HxOverrides.substr(text,0,char_pos));
};
Tool.toVSCSeverity = function(s) {
	switch(s) {
	case 0:
		return Vscode.DiagnosticSeverity.Hint;
	case 1:
		return Vscode.DiagnosticSeverity.Warning;
	case 2:
		return Vscode.DiagnosticSeverity.Error;
	default:
		return Vscode.DiagnosticSeverity.Hint;
	}
};
Tool.toVSCRange = function(info) {
	var r = info.range;
	if(r.isLineRange) return new Vscode.Range(new Vscode.Position(r.start - 1,0),new Vscode.Position(r.end - 1,0)); else return new Vscode.Range(new Vscode.Position(info.lineNumber - 1,r.start),new Vscode.Position(info.lineNumber - 1,r.end));
};
var Debouncer = function(delay_ms,fn) {
	this.last = 0;
	this.queue = [];
	this.onDone = [];
	this.delay = delay_ms;
	this.fn = fn;
	this.last = 0;
	this.timer = new haxe_Timer(50);
	this.timer.run = $bind(this,this.apply);
};
Debouncer.__name__ = true;
Debouncer.prototype = {
	apply: function() {
		var dlt = new Date().getTime() - this.last;
		var q = this.queue;
		if(dlt < this.delay || q.length == 0) return;
		var od = this.onDone;
		this.queue = [];
		this.onDone = [];
		this.fn(q);
		var _g = 0;
		while(_g < od.length) {
			var f = od[_g];
			++_g;
			f();
		}
	}
	,debounce: function(e) {
		this.queue.push(e);
		this.last = new Date().getTime();
	}
	,whenDone: function(f) {
		if(this.queue.length == 0) f(); else this.onDone.push(f);
	}
	,dispose: function() {
		if(this.timer != null) {
			this.timer.stop();
			this.timer = null;
		}
	}
	,__class__: Debouncer
};
var Vscode = require("vscode");
var CompletionItemProvider = function() { };
CompletionItemProvider.__name__ = true;
CompletionItemProvider.prototype = {
	__class__: CompletionItemProvider
};
var DefinitionProvider = function() { };
DefinitionProvider.__name__ = true;
DefinitionProvider.prototype = {
	__class__: DefinitionProvider
};
var SignatureHelpProvider = function() { };
SignatureHelpProvider.__name__ = true;
SignatureHelpProvider.prototype = {
	__class__: SignatureHelpProvider
};
var features_CompletionHandler = function(hxContext) {
	this.hxContext = hxContext;
	var context = hxContext.context;
	var disposable = Vscode.languages.registerCompletionItemProvider("haxe",this,".",":","{"," ");
	context.subscriptions.push(disposable);
};
features_CompletionHandler.__name__ = true;
features_CompletionHandler.__interfaces__ = [CompletionItemProvider];
features_CompletionHandler.prototype = {
	parse_items: function(msg) {
		var rtn = [];
		var datas = msg.stderr;
		if(datas.length > 2 && datas[0] == "<list>") {
			datas.shift();
			datas.pop();
			datas.pop();
			var len = datas.length;
			var i = 0;
			while(i < len) {
				var tmp = datas[i++];
				var data = "";
				if(HxOverrides.substr(tmp,0,2) == "<i") {
					while(i < len) {
						data += tmp;
						if(HxOverrides.substr(tmp,tmp.length - 2,2) == "i>") break;
						tmp = datas[i++];
					}
					if(i == len) data += tmp;
				}
				if(features_CompletionHandler.reI.match(data)) {
					var n = features_CompletionHandler.reI.matched(1);
					var k = features_CompletionHandler.reI.matched(2);
					var ip = features_CompletionHandler.reI.matched(4);
					var f = Std.parseInt(features_CompletionHandler.reI.matched(6)) | 0;
					var t = features_CompletionHandler.reI.matched(7);
					t = features_CompletionHandler.reGT.replace(features_CompletionHandler.reLT.replace(t,"<"),">");
					var d = features_CompletionHandler.reI.matched(8);
					var ci = new Vscode.CompletionItem(n);
					ci.documentation = d;
					ci.detail = t;
					switch(k) {
					case "method":
						var ts = t.split("->");
						var l = ts.length;
						if(features_CompletionHandler.reMethod.match(ts[l - 1])) ci.kind = Vscode.CompletionItemKind.Method; else ci.kind = Vscode.CompletionItemKind.Function;
						break;
					case "var":
						if(ip == "1") ci.kind = Vscode.CompletionItemKind.Property; else if((f & 1) != 0) ci.kind = Vscode.CompletionItemKind.Property; else ci.kind = Vscode.CompletionItemKind.Field;
						break;
					case "package":
						ci.kind = Vscode.CompletionItemKind.Module;
						break;
					case "type":
						ci.kind = Vscode.CompletionItemKind.Class;
						break;
					default:
						ci.kind = Vscode.CompletionItemKind.Field;
					}
					rtn.push(ci);
				}
			}
		} else rtn.push(null);
		return rtn;
	}
	,provideCompletionItems: function(document,position,cancelToken) {
		var _g = this;
		return new Promise(function(accept,reject) {
			if(cancelToken.isCancellationRequested) {
				reject([]);
				return;
			}
			var changeDebouncer = _g.hxContext.changeDebouncer;
			var client = _g.hxContext.client;
			var text = document.getText();
			var char_pos = document.offsetAt(position);
			var ds = _g.hxContext.getDocumentState(document.uri.fsPath);
			var path;
			if(ds.tmpPath == null) path = ds.realPath; else path = ds.tmpPath;
			var makeCall = false;
			var displayMode = haxe_DisplayMode.Default;
			var lastChar = text.charAt(char_pos - 1);
			var isDot = lastChar == ".";
			var isProbablyMeta = lastChar == ":";
			var doMetaCompletion = isProbablyMeta && text.charAt(char_pos - 2) == "@";
			var word = "";
			var displayClasses = isProbablyMeta && !doMetaCompletion;
			var isTriggerChar = isDot || lastChar == "{" || displayClasses;
			if(!displayClasses && !doMetaCompletion && !isTriggerChar) {
				var j = char_pos - 2;
				if(features_CompletionHandler.reWS.match(lastChar)) {
					while(j >= 0) {
						if(!features_CompletionHandler.reWS.match(text.charAt(j))) break;
						j--;
					}
					char_pos = j + 1;
				}
				while(j >= 0) {
					if(!features_CompletionHandler.reWord.match(text.charAt(j))) break;
					j--;
				}
				var word1 = HxOverrides.substr(text,j + 1,char_pos - 1 - j);
				switch(word1) {
				case "import":
					if(features_CompletionHandler.reWS.match(lastChar)) {
						isTriggerChar = true;
						displayClasses = true;
					} else {
						while(j >= 0) {
							if(!features_CompletionHandler.reWS.match(text.charAt(j))) break;
							j--;
						}
						lastChar = text.charAt(j);
						isDot = lastChar == ".";
						isTriggerChar = isDot || lastChar == "{";
						if(isTriggerChar) char_pos = j + 1;
					}
					break;
				case "package":
					if(features_CompletionHandler.reWS.match(lastChar)) {
						var tmp = _g.hxContext.getPackageFromDS(ds);
						if(tmp != null) {
							var ci = new Vscode.CompletionItem(tmp.pack + ";");
							ci.kind = Vscode.CompletionItemKind.File;
							accept([ci]);
							return;
						}
					} else {
						while(j >= 0) {
							if(!features_CompletionHandler.reWS.match(text.charAt(j))) break;
							j--;
						}
						lastChar = text.charAt(j);
						isDot = lastChar == ".";
						isTriggerChar = isDot || lastChar == "{";
						if(isTriggerChar) char_pos = j + 1;
					}
					break;
				default:
					while(j >= 0) {
						if(!features_CompletionHandler.reWS.match(text.charAt(j))) break;
						j--;
					}
					lastChar = text.charAt(j);
					isDot = lastChar == ".";
					isTriggerChar = isDot || lastChar == "{";
					if(isTriggerChar) char_pos = j + 1;
				}
			}
			makeCall = isTriggerChar;
			if(makeCall && features_CompletionHandler.reWS.match(lastChar)) {
				if(new Date().getTime() - ds.lastModification < 250) {
					reject([]);
					return;
				}
			}
			if(!makeCall) {
				var items = [];
				if(doMetaCompletion) {
					var _g11 = 0;
					var _g21 = _g.hxContext.client.metas;
					while(_g11 < _g21.length) {
						var data = _g21[_g11];
						++_g11;
						var ci1 = new Vscode.CompletionItem(data.name);
						ci1.documentation = data.doc;
						items.push(ci1);
					}
				}
				accept(items);
				return;
			}
			var byte_pos;
			if(char_pos == text.length) byte_pos = js_node_buffer_Buffer.byteLength(text,null); else byte_pos = Tool.byteLength(HxOverrides.substr(text,0,char_pos));
			var make_request = function() {
				if(cancelToken.isCancellationRequested) {
					reject([]);
					return;
				}
				var cl = client.cmdLine.save().cwd(_g.hxContext.get_workingDir()).define("display-details").hxml(_g.hxContext.get_buildFile()).noOutput();
				if(displayClasses) cl.classes(); else cl.display(path,byte_pos,displayMode);
				client.setContext({ fileName : path, line : position.line + 1, column : char_pos}).setCancelToken(cancelToken);
				_g.hxContext.send("completion@2",true,1,10).then(function(m) {
					if(cancelToken.isCancellationRequested) reject([]); else {
						var ret = _g.parse_items(m);
						if(ret.length == 1 && ret[0] == null) {
							ret = [];
							_g.hxContext.diagnoseIfAllowed();
						}
						accept(ret);
					}
				},function(m1) {
					if(!cancelToken.isCancellationRequested) {
						if(m1.severity == 2) _g.hxContext.applyDiagnostics(m1);
					}
					reject([]);
				});
			};
			var ds1 = _g.hxContext.getDocumentState(path);
			var isDirty;
			if(client.isPatchAvailable) isDirty = ds1.document != null && ds1.lastModification > ds1.lastSave; else isDirty = ds1.document != null && ds1.lastModification > ds1.lastSave || document.isDirty;
			var doRequest = function() {
				if(cancelToken.isCancellationRequested) {
					reject([]);
					return;
				}
				var isPatchAvailable = client.isPatchAvailable;
				var isServerAvailable = client.isServerAvailable;
				if(isPatchAvailable) {
					if(isDirty) _g.hxContext.patchFullDocument(ds1).then(function(ds2) {
						make_request();
					},function(ds3) {
						reject([]);
					}); else make_request();
				} else changeDebouncer.whenDone(function() {
					if(cancelToken.isCancellationRequested) {
						reject([]);
						return;
					}
					var ps = [];
					var _g1 = 0;
					var _g2 = _g.hxContext.getDirtyDocuments();
					while(_g1 < _g2.length) {
						var ds4 = _g2[_g1];
						++_g1;
						ds4.diagnoseOnSave = false;
						ps.push(_g.hxContext.saveDocument(ds4));
					}
					if(ps.length == 0) make_request(); else Promise.all(ps).then(function(all) {
						if(cancelToken.isCancellationRequested) {
							reject([]);
							return;
						}
						make_request();
					},function(all1) {
						reject([]);
					});
				});
			};
			if(!client.isServerAvailable) _g.hxContext.launchServer().then(function(port) {
				doRequest();
			},function(port1) {
				reject([]);
			}); else doRequest();
		});
	}
	,resolveCompletionItem: function(item,cancelToken) {
		return item;
	}
	,__class__: features_CompletionHandler
};
var features_DefinitionHandler = function(hxContext) {
	this.hxContext = hxContext;
	var context = hxContext.context;
	var disposable = Vscode.languages.registerDefinitionProvider("haxe",this);
	context.subscriptions.push(disposable);
};
features_DefinitionHandler.__name__ = true;
features_DefinitionHandler.__interfaces__ = [DefinitionProvider];
features_DefinitionHandler.prototype = {
	provideDefinition: function(document,position,cancelToken) {
		var _g = this;
		var changeDebouncer = this.hxContext.changeDebouncer;
		var client = this.hxContext.client;
		var documentState = this.hxContext.getDocumentState(document.uri.fsPath);
		var path;
		if(documentState.tmpPath == null) path = documentState.realPath; else path = documentState.tmpPath;
		var displayMode = haxe_DisplayMode.Position;
		var text = document.getText();
		var range = document.getWordRangeAtPosition(position);
		position = range.end;
		var char_pos = document.offsetAt(position) + 1;
		var byte_pos;
		if(char_pos == text.length) byte_pos = js_node_buffer_Buffer.byteLength(text,null); else byte_pos = Tool.byteLength(HxOverrides.substr(text,0,char_pos));
		return new Promise(function(accept,reject) {
			if(cancelToken.isCancellationRequested) reject(null);
			var trying = 1;
			var make_request = function() {
				var cl = client.cmdLine.save().cwd(_g.hxContext.get_workingDir()).hxml(_g.hxContext.get_buildFile()).noOutput().display(path,byte_pos,displayMode);
				var parse = function(m) {
					if(cancelToken.isCancellationRequested) return reject(null);
					var datas = m.stderr;
					var defs = [];
					if(datas.length >= 2 && datas[0] == "<list>") {
						datas.shift();
						datas.pop();
						var _g1 = 0;
						while(_g1 < datas.length) {
							var data = datas[_g1];
							++_g1;
							if(!features_DefinitionHandler.rePos.match(data)) continue;
							data = features_DefinitionHandler.rePos.matched(1);
							var i = haxe_Info.decode(data,_g.hxContext.projectDir);
							if(i == null) continue;
							var info = i.info;
							var fileName = _g.hxContext.tmpToReal(_g.hxContext.insensitiveToSensitive(info.fileName));
							defs.push(new Vscode.Location(Vscode.Uri.file(fileName),Tool.toVSCRange(info)));
						}
					}
					accept(defs);
					return;
				};
				client.setContext({ fileName : path, line : position.line + 1, column : char_pos}).setCancelToken(cancelToken);
				_g.hxContext.send(null,true,1).then(parse,function(m1) {
					if(m1.error != null) Vscode.window.showErrorMessage(m1.error.message);
					reject(null);
				});
			};
			var ds = _g.hxContext.getDocumentState(path);
			var isDirty;
			if(client.isPatchAvailable) isDirty = ds.document != null && ds.lastModification > ds.lastSave; else isDirty = ds.document != null && ds.lastModification > ds.lastSave || document.isDirty;
			var doRequest = function() {
				if(cancelToken.isCancellationRequested) {
					reject(null);
					return;
				}
				var isPatchAvailable = client.isPatchAvailable;
				var isServerAvailable = client.isServerAvailable;
				if(isPatchAvailable) {
					if(isDirty) _g.hxContext.patchFullDocument(ds).then(function(ds1) {
						make_request();
					},function(ds2) {
						reject(null);
					}); else make_request();
				} else changeDebouncer.whenDone(function() {
					if(cancelToken.isCancellationRequested) {
						reject(null);
						return;
					}
					var ps = [];
					var _g11 = 0;
					var _g2 = _g.hxContext.getDirtyDocuments();
					while(_g11 < _g2.length) {
						var ds3 = _g2[_g11];
						++_g11;
						ds3.diagnoseOnSave = false;
						ps.push(_g.hxContext.saveDocument(ds3));
					}
					if(ps.length == 0) make_request(); else Promise.all(ps).then(function(all) {
						if(cancelToken.isCancellationRequested) {
							reject(null);
							return;
						}
						make_request();
					},function(all1) {
						reject(null);
					});
				});
			};
			if(!client.isServerAvailable) _g.hxContext.launchServer().then(function(port) {
				doRequest();
			},function(port1) {
				reject(null);
			}); else doRequest();
		});
	}
	,__class__: features_DefinitionHandler
};
var features_FunctionDecoder = function() { };
features_FunctionDecoder.__name__ = true;
features_FunctionDecoder.asFunctionArgs = function(data) {
	var l = data.length;
	var args = [];
	var i = 0;
	var sp = 0;
	var pc = "";
	var consLevel = 0;
	var parLevel = 0;
	var argName = "";
	var canParseArgName = true;
	while(i < l) {
		var c = data.charAt(i);
		switch(c) {
		case ":":
			if(canParseArgName) {
				canParseArgName = false;
				argName = data.substring(sp,i - 1);
				sp = i + 2;
			}
			break;
		case "(":
			parLevel++;
			break;
		case ")":
			parLevel--;
			break;
		case "<":
			consLevel++;
			break;
		case ">":
			if(pc == "-") {
				if(parLevel == 0 && consLevel == 0) {
					args.push({ name : argName, type : data.substring(sp,i - 2)});
					canParseArgName = true;
					sp = i + 2;
				}
			} else consLevel--;
			break;
		}
		pc = c;
		i++;
	}
	args.push({ name : "", type : HxOverrides.substr(data,sp,null)});
	return args;
};
features_FunctionDecoder.findNameAndParameterPlace = function(data,from) {
	var argCount = 0;
	var parLevel = 0;
	var bkLevel = 0;
	var strSep = "\"";
	var inStr = false;
	try {
		while(from >= 0) {
			var c = data.charAt(from--);
			if(inStr) {
				if(c == strSep) {
					var slCnt = 0;
					var i = from;
					while(i >= 0) {
						if(data.charAt(i) == "\\") slCnt++; else break;
						i--;
					}
					if((slCnt & 1) == 0) inStr = false; else from = i;
				}
			} else switch(c) {
			case "(":
				parLevel++;
				if(parLevel == 1) {
					var pp = from + 1;
					while(from >= 0) {
						c = data.charAt(from);
						if(!features_FunctionDecoder.reWS.match(c)) break;
						from--;
					}
					if(from < 0) throw "__break__";
					if(!features_FunctionDecoder.reLastId.match(c)) throw "__break__";
					from--;
					while(from >= 0) {
						c = data.charAt(from);
						if(!features_FunctionDecoder.reLastId.match(c)) break;
						from--;
					}
					if(features_FunctionDecoder.reFirstId.match(data.charAt(from + 1))) return { start : pp + 1, cnt : argCount};
				}
				break;
			case "[":
				bkLevel++;
				if(bkLevel != 0) throw "__break__";
				break;
			case ")":
				parLevel--;
				break;
			case "]":
				bkLevel--;
				break;
			case ",":
				if(bkLevel == 0 && parLevel == 0) argCount++;
				break;
			case "'":case "\"":
				inStr = true;
				strSep = c;
				break;
			}
		}
	} catch( e ) { if( e != "__break__" ) throw e; }
	return null;
};
var features_SignatureHandler = function(hxContext) {
	this.hxContext = hxContext;
	var context = hxContext.context;
	var disposable = Vscode.languages.registerSignatureHelpProvider("haxe",this,"(",",");
	context.subscriptions.push(disposable);
};
features_SignatureHandler.__name__ = true;
features_SignatureHandler.__interfaces__ = [SignatureHelpProvider];
features_SignatureHandler.prototype = {
	provideSignatureHelp: function(document,position,cancelToken) {
		var _g = this;
		var client = this.hxContext.client;
		var changeDebouncer = this.hxContext.changeDebouncer;
		var ds = this.hxContext.getDocumentState(document.uri.fsPath,document);
		var path;
		if(ds.tmpPath == null) path = ds.realPath; else path = ds.tmpPath;
		var text = document.getText();
		var char_pos = document.offsetAt(position);
		var text1 = document.getText();
		var lastChar = text1.charAt(char_pos - 1);
		var byte_pos = 0;
		var displayMode = haxe_DisplayMode.Default;
		var activeParameter = 0;
		if(lastChar == ",") {
			text1 = HxOverrides.substr(text1,0,char_pos) + "VSCTool.fatalError()." + HxOverrides.substr(text1,char_pos,null);
			ds.text = text1;
			ds.lastModification = new Date().getTime();
			byte_pos = Tool.byte_pos(text1,char_pos + 21);
		} else if(char_pos == text1.length) byte_pos = js_node_buffer_Buffer.byteLength(text1,null); else byte_pos = Tool.byteLength(HxOverrides.substr(text1,0,char_pos));
		return new Promise(function(accept,reject) {
			if(cancelToken.isCancellationRequested) reject(null);
			var make_request;
			var make_request1 = null;
			make_request1 = function() {
				var cl = client.cmdLine.save().cwd(_g.hxContext.get_workingDir()).hxml(_g.hxContext.get_buildFile()).noOutput().display(path,byte_pos,displayMode);
				client.setContext({ fileName : path, line : position.line + 1, column : char_pos}).setCancelToken(cancelToken);
				_g.hxContext.send(null,true,1).then(function(m) {
					_g.hxContext.diagnostics.clear();
					var datas = m.stderr;
					var sh = new Vscode.SignatureHelp();
					sh.activeParameter = activeParameter;
					sh.activeSignature = 0;
					var sigs = [];
					sh.signatures = sigs;
					if(datas.length > 2 && features_SignatureHandler.reType.match(datas[0])) {
						var opar = Std.parseInt(features_SignatureHandler.reType.matched(2)) | 0;
						var index = Std.parseInt(features_SignatureHandler.reType.matched(4)) | 0;
						if(index > 0) sh.activeParameter = index;
						datas.shift();
						datas.pop();
						datas.pop();
						var _g11 = 0;
						while(_g11 < datas.length) {
							var data = datas[_g11];
							++_g11;
							data = features_SignatureHandler.reGT.replace(data,">");
							data = features_SignatureHandler.reLT.replace(data,"<");
							var args = features_FunctionDecoder.asFunctionArgs(data);
							var ret = args.pop();
							var params = args.map(function(v) {
								return v.name + ":" + v.type;
							});
							data = "(" + params.join(", ") + "):" + ret.type;
							var si = new Vscode.SignatureInformation(data);
							sigs.push(si);
							var pis = args.map(function(v1) {
								return new Vscode.ParameterInformation(v1.name,v1.type);
							});
							si.parameters = pis;
						}
					}
					accept(sh);
				},function(m1) {
					if(m1.error != null) Vscode.window.showErrorMessage(m1.error.message); else if(lastChar == ",") {
						_g.hxContext.diagnostics.clear();
						var fnInfo = null;
						var _g12 = 0;
						var _g21 = m1.infos;
						while(_g12 < _g21.length) {
							var i = _g21[_g12];
							++_g12;
							if(features_SignatureHandler.reFatalError.match(i.message)) {
								fnInfo = features_FunctionDecoder.findNameAndParameterPlace(text1,char_pos - 1);
								break;
							}
						}
						if(fnInfo != null) {
							activeParameter = fnInfo.cnt;
							byte_pos = Tool.byte_pos(text1,fnInfo.start);
							make_request1();
							return;
						}
					}
					reject(null);
				});
			};
			make_request = make_request1;
			var ds1 = _g.hxContext.getDocumentState(path);
			var isDirty;
			if(client.isPatchAvailable) isDirty = ds1.document != null && ds1.lastModification > ds1.lastSave; else isDirty = ds1.document != null && ds1.lastModification > ds1.lastSave || document.isDirty;
			var doRequest = function() {
				if(cancelToken.isCancellationRequested) {
					reject(null);
					return;
				}
				var isPatchAvailable = client.isPatchAvailable;
				var isServerAvailable = client.isServerAvailable;
				if(isPatchAvailable) {
					if(isDirty) _g.hxContext.patchFullDocument(ds1).then(function(ds2) {
						make_request();
					},function(ds3) {
						reject(null);
					}); else make_request();
				} else changeDebouncer.whenDone(function() {
					if(cancelToken.isCancellationRequested) {
						reject(null);
						return;
					}
					var ps = [];
					var _g1 = 0;
					var _g2 = _g.hxContext.getDirtyDocuments();
					while(_g1 < _g2.length) {
						var ds4 = _g2[_g1];
						++_g1;
						ds4.diagnoseOnSave = false;
						ps.push(_g.hxContext.saveDocument(ds4));
					}
					if(ps.length == 0) make_request(); else Promise.all(ps).then(function(all) {
						if(cancelToken.isCancellationRequested) {
							reject(null);
							return;
						}
						make_request();
					},function(all1) {
						reject(null);
					});
				});
			};
			if(!client.isServerAvailable) _g.hxContext.launchServer().then(function(port) {
				doRequest();
			},function(port1) {
				reject(null);
			}); else doRequest();
		});
	}
	,__class__: features_SignatureHandler
};
var features_hxml_CompletionHandler = function(hxmlContext) {
	this.hxmlContext = hxmlContext;
	var context = hxmlContext.hxContext.context;
	var disposable = Vscode.languages.registerCompletionItemProvider("hxml",this,"-","D"," ");
	context.subscriptions.push(disposable);
};
features_hxml_CompletionHandler.__name__ = true;
features_hxml_CompletionHandler.__interfaces__ = [CompletionItemProvider];
features_hxml_CompletionHandler.prototype = {
	provideCompletionItems: function(document,position,cancelToken) {
		var items = [];
		var client = this.hxmlContext.hxContext.client;
		if(client != null) {
			var textLine = document.lineAt(position);
			var text = textLine.text;
			var char_pos = position.character - 1;
			var $char = text.charAt(char_pos);
			switch($char) {
			case "-":
				switch(char_pos) {
				case 0:
					var _g = 0;
					var _g1 = client.options;
					while(_g < _g1.length) {
						var data = _g1[_g];
						++_g;
						var ci = new Vscode.CompletionItem(HxOverrides.substr(data.prefix,1,null) + data.name);
						ci.documentation = data.doc;
						items.push(ci);
					}
					break;
				case 1:
					var _g2 = 0;
					var _g11 = client.options;
					while(_g2 < _g11.length) {
						var data1 = _g11[_g2];
						++_g2;
						if(data1.prefix.length < 2) continue;
						var ci1 = new Vscode.CompletionItem(data1.name);
						ci1.documentation = data1.doc;
						items.push(ci1);
					}
					break;
				}
				break;
			case "D":
				if(char_pos == 1 && text.charAt(char_pos - 1) == "-") {
					var _g3 = 0;
					var _g12 = client.defines;
					while(_g3 < _g12.length) {
						var data2 = _g12[_g3];
						++_g3;
						var ci2 = new Vscode.CompletionItem("D " + data2.name);
						ci2.documentation = data2.doc;
						items.push(ci2);
					}
				}
				break;
			case " ":
				if(char_pos == 2 && HxOverrides.substr(text,0,char_pos) == "-D") {
					var _g4 = 0;
					var _g13 = client.defines;
					while(_g4 < _g13.length) {
						var data3 = _g13[_g4];
						++_g4;
						var ci3 = new Vscode.CompletionItem(data3.name);
						ci3.documentation = data3.doc;
						items.push(ci3);
					}
				}
				break;
			}
		}
		return new Promise(function(resolve) {
			resolve(items);
		});
	}
	,resolveCompletionItem: function(item,cancelToken) {
		return item;
	}
	,__class__: features_hxml_CompletionHandler
};
var haxe_IMap = function() { };
haxe_IMap.__name__ = true;
var haxe_RangeInfo = function(s,e,isLineRange) {
	if(isLineRange == null) isLineRange = false;
	if(e == null) e = -1;
	if(e == -1) e = s;
	if(s > e) {
		this.start = e;
		this.end = s;
	} else {
		this.start = s;
		this.end = e;
	}
	if(!isLineRange && this.start == this.end) this.end++;
	this.isLineRange = isLineRange;
};
haxe_RangeInfo.__name__ = true;
haxe_RangeInfo.prototype = {
	__class__: haxe_RangeInfo
};
var haxe_Info = function(fileName,lineNumber,range,message) {
	this.fileName = fileName;
	this.lineNumber = lineNumber;
	this.range = range;
	this.message = message;
};
haxe_Info.__name__ = true;
haxe_Info.decode = function(str,cwd) {
	if(cwd == null) cwd = "";
	if(!haxe_Info.re1.match(str)) return null;
	if(!haxe_Info.re2.match(haxe_Info.re1.matched(5))) return null;
	var rs = Std.parseInt(haxe_Info.re2.matched(4));
	var re;
	var tmp = haxe_Info.re2.matched(6);
	if(tmp != null) re = Std.parseInt(tmp); else re = rs;
	if(re == null) re = rs;
	var isLine = haxe_Info.re2.matched(3) != null;
	var fn = haxe_Info.re1.matched(1);
	var wd = haxe_Info.re1.matched(2);
	if(wd != null) fn = fn.split("/").join("\\"); else {
		var ps = "/";
		var dps = "\\";
		if(haxe_Info.reWin.match(cwd)) {
			ps = "\\";
			dps = "/";
		}
		if(cwd.charAt(cwd.length - 1) != ps) cwd += ps;
		var _g = fn.charAt(0);
		switch(_g) {
		case "/":
			break;
		case "\\":
			break;
		default:
			fn = cwd + fn;
		}
		fn = fn.split(dps).join(ps);
	}
	var ln = Std.parseInt(haxe_Info.re1.matched(4));
	return { info : new haxe_Info(fn,ln,new haxe_RangeInfo(rs,re,isLine),haxe_Info.re1.matched(7)), winDrive : wd};
};
haxe_Info.prototype = {
	__class__: haxe_Info
};
var haxe_HaxeClient = function(host,port) {
	this.currentJob = null;
	this.host = host;
	this.port = port;
	this.cmdLine = new haxe_HaxeCmdLine();
	this.queue = [];
	this.working = false;
	this.resetInfos();
};
haxe_HaxeClient.__name__ = true;
haxe_HaxeClient.isOptionExists = function(optionName,data) {
	var re = new EReg("unknown option '" + optionName + "'","");
	return !re.match(data);
};
haxe_HaxeClient.prototype = {
	resetInfos: function() {
		this.options = [];
		this.defines = [];
		this.metas = [];
		this.keywords = [];
		this.optionsByName = new haxe_ds_StringMap();
		this.definesByName = new haxe_ds_StringMap();
		this.isHaxeServer = false;
		this.isPatchAvailable = false;
		this.isServerAvailable = false;
	}
	,clear: function() {
		this.cmdLine.clear();
	}
	,setContext: function(ctx) {
		this.sourceContext = ctx;
		return this;
	}
	,setCancelToken: function(ct) {
		this.cancelToken = ct;
		return this;
	}
	,sendAll: function(onClose,restoreCmdLine,id,priority,clearCmdAfterExec) {
		if(clearCmdAfterExec == null) clearCmdAfterExec = true;
		if(priority == null) priority = 0;
		if(restoreCmdLine == null) restoreCmdLine = false;
		var _g = this;
		var ctx = this.sourceContext;
		var ct = this.cancelToken;
		this.sourceContext = null;
		this.cancelToken = null;
		var cmds = this.cmdLine.toString();
		if(cmds == "") {
			if(restoreCmdLine) _g.cmdLine.restore();
			restoreCmdLine = false;
			if(onClose != null) onClose({ stdout : null, stderr : null, infos : null, socket : null, error : null, severity : 3});
			onClose = null;
			_g.working = false;
			_g.currentJob = null;
			this.runQueue();
			return null;
		}
		this.cmdLine.clearPatch();
		var workingDir = this.cmdLine.workingDir;
		if(restoreCmdLine) _g.cmdLine.restore();
		restoreCmdLine = false;
		var run = function(job) {
			_g.currentJob = job;
			var s = null;
			var ct1 = job.cancelToken;
			if(job.cancel || ct1 != null && ct1.isCancellationRequested) {
				if(s != null) s.close();
				if(restoreCmdLine) _g.cmdLine.restore();
				restoreCmdLine = false;
				if(onClose != null) onClose({ stdout : null, stderr : null, infos : null, socket : null, error : null, severity : 3});
				onClose = null;
				_g.working = false;
				_g.currentJob = null;
				_g.runQueue();
				return;
			}
			_g.working = true;
			s = new Socket();
			s.connect(_g.host,_g.port,function(s1) {
				if(job.cancel || ct1 != null && ct1.isCancellationRequested) {
					if(s != null) s.close();
					if(restoreCmdLine) _g.cmdLine.restore();
					restoreCmdLine = false;
					if(onClose != null) onClose({ stdout : null, stderr : null, infos : null, socket : null, error : null, severity : 3});
					onClose = null;
					_g.working = false;
					_g.currentJob = null;
					_g.runQueue();
					return;
				}
				s1.write(cmds);
				s1.write("\x00");
			},function(s2,d) {
				if(job.cancel || ct1 != null && ct1.isCancellationRequested) {
					if(s != null) s.close();
					if(restoreCmdLine) _g.cmdLine.restore();
					restoreCmdLine = false;
					if(onClose != null) onClose({ stdout : null, stderr : null, infos : null, socket : null, error : null, severity : 3});
					onClose = null;
					_g.working = false;
					_g.currentJob = null;
					_g.runQueue();
					return;
				}
			},null,function(s3) {
				_g.working = false;
				_g.isServerAvailable = s3.error == null;
				if(clearCmdAfterExec) _g.clear();
				if(job.cancel || ct1 != null && ct1.isCancellationRequested) {
					if(s != null) s.close();
					if(restoreCmdLine) _g.cmdLine.restore();
					restoreCmdLine = false;
					if(onClose != null) onClose({ stdout : null, stderr : null, infos : null, socket : null, error : null, severity : 3});
					onClose = null;
					_g.working = false;
					_g.currentJob = null;
					_g.runQueue();
					return;
				}
				if(onClose != null) {
					var stdout = [];
					var stderr = [];
					var infos = [];
					var hasError = false;
					var nl = "\n";
					var _g1 = 0;
					var _g2 = s3.datas.join("").split(nl);
					while(_g1 < _g2.length) {
						var line = _g2[_g1];
						++_g1;
						var _g3 = HxOverrides.cca(line,0);
						if(_g3 != null) switch(_g3) {
						case 1:
							stdout.push(HxOverrides.substr(line,1,null).split("\x01").join(nl));
							break;
						case 2:
							hasError = true;
							break;
						default:
							stderr.push(line);
							var info = haxe_Info.decode(line,workingDir);
							if(info == null && ctx != null && line != "") {
								var msg = [ctx.fileName,ctx.line == null?"null":"" + ctx.line," character " + ctx.column + " ",line].join(":");
								info = haxe_Info.decode(msg,workingDir);
							}
							if(info != null) infos.push(info.info);
						} else {
							stderr.push(line);
							var info = haxe_Info.decode(line,workingDir);
							if(info == null && ctx != null && line != "") {
								var msg = [ctx.fileName,ctx.line == null?"null":"" + ctx.line," character " + ctx.column + " ",line].join(":");
								info = haxe_Info.decode(msg,workingDir);
							}
							if(info != null) infos.push(info.info);
						}
					}
					var severity;
					if(hasError) severity = 2; else severity = 1;
					onClose({ stdout : stdout, stderr : stderr, infos : infos, severity : severity, socket : s3, error : s3.error});
				}
				_g.runQueue();
			});
		};
		if(id == "") id = null;
		var group = 0;
		if(id != null) {
			var tmp = id.split("@");
			id = tmp[0];
			if(id == "") id = null;
			if(tmp.length > 1) group = Std.parseInt(tmp[1]);
		}
		haxe_HaxeClient.jobId++;
		var sId = "-" + Std.string(haxe_HaxeClient.jobId);
		if(id == null) id = sId; else id += sId;
		var job1 = { run : run, id : id, group : group, priority : priority, cancelToken : ct, cancel : false};
		if(this.queue.length == 0) this.queue.push(job1); else {
			var oq = this.queue;
			this.queue = [];
			if(group != 0 && this.currentJob != null && group >= this.currentJob.group) this.currentJob.cancel = true;
			var jobPushed = false;
			while(oq.length > 0) {
				var j = oq.shift();
				if(j.priority < priority) {
					jobPushed = true;
					this.queue.push(job1);
					this.queue.push(j);
					break;
				} else this.queue.push(j);
			}
			this.queue = this.queue.concat(oq);
			if(!jobPushed) this.queue.push(job1);
		}
		if(!this.working) this.runQueue();
		return job1;
	}
	,runQueue: function() {
		if(this.queue.length == 0) return;
		var job = this.queue.shift();
		var group = job.group;
		if(group != 0) {
			var oq = this.queue;
			this.queue = [];
			while(oq.length > 0) {
				var nj = oq.shift();
				if(nj.group >= group) {
					if(nj.priority != job.priority) {
						nj.cancel = true;
						nj.run(nj);
					} else {
						job.cancel = true;
						job.run(job);
						job = nj;
					}
				} else this.queue.push(nj);
			}
		}
		if(job != null) job.run(job);
	}
	,unformatDoc: function(s) {
		return s;
	}
	,infos: function(onData) {
		var _g = this;
		this.resetInfos();
		var step = 0;
		var next;
		var next1 = null;
		next1 = function() {
			_g.cmdLine.save();
			switch(step) {
			case 0:
				_g.cmdLine.help();
				break;
			case 1:
				_g.cmdLine.helpDefines();
				break;
			case 2:
				_g.cmdLine.helpMetas();
				break;
			case 3:
				_g.cmdLine.keywords();
				break;
			}
			_g.sendAll(function(message) {
				var s = message.socket;
				var error = message.error;
				var abort = true;
				_g.isServerAvailable = error == null;
				if(_g.isServerAvailable) switch(step) {
				case 0:
					var datas = message.stderr;
					if(datas.length > 0) {
						_g.version = datas.shift();
						_g.isHaxeServer = haxe_HaxeClient.reVersion.match(_g.version);
						abort = !_g.isHaxeServer;
						if(_g.isHaxeServer) {
							var _g1 = 0;
							while(_g1 < datas.length) {
								var data = datas[_g1];
								++_g1;
								if(haxe_HaxeClient.reCheckOption.match(data)) {
									if(haxe_HaxeClient.reCheckOptionName.match(haxe_HaxeClient.reCheckOption.matched(3))) {
										var name = haxe_HaxeClient.reCheckOptionName.matched(1);
										_g.isPatchAvailable = _g.isPatchAvailable || name == "patch";
										var option = { prefix : haxe_HaxeClient.reCheckOption.matched(1), name : name, doc : _g.unformatDoc(haxe_HaxeClient.reCheckOption.matched(4)), param : haxe_HaxeClient.reCheckOptionName.matched(3)};
										_g.options.push(option);
										_g.optionsByName.set(name,option);
									}
								}
							}
						}
					}
					break;
				case 1:
					var datas1 = message.stdout;
					abort = datas1.length <= 0;
					var _g11 = 0;
					while(_g11 < datas1.length) {
						var data1 = datas1[_g11];
						++_g11;
						if(haxe_HaxeClient.reCheckDefine.match(data1)) {
							var define = { name : haxe_HaxeClient.reCheckDefine.matched(1), doc : _g.unformatDoc(haxe_HaxeClient.reCheckDefine.matched(2))};
							_g.defines.push(define);
							_g.definesByName.set(define.name,define);
						}
					}
					break;
				case 2:
					var datas2 = message.stdout;
					abort = datas2.length <= 0;
					var _g12 = 0;
					while(_g12 < datas2.length) {
						var data2 = datas2[_g12];
						++_g12;
						if(haxe_HaxeClient.reCheckMeta.match(data2)) _g.metas.push({ prefix : haxe_HaxeClient.reCheckMeta.matched(1), name : haxe_HaxeClient.reCheckMeta.matched(2), doc : _g.unformatDoc(haxe_HaxeClient.reCheckMeta.matched(3))});
					}
					break;
				case 3:
					var datas3 = message.stderr;
					abort = datas3.length <= 0;
					if(!abort) haxe_HaxeClient.reKeywords.map(datas3[0],function(r) {
						var match = r.matched(1);
						_g.keywords.push({ name : match});
						return match;
					});
					break;
				}
				if(abort) {
					if(onData != null) onData(_g);
				} else {
					step++;
					next1();
				}
			},true);
		};
		next = next1;
		next();
	}
	,__class__: haxe_HaxeClient
};
var haxe_DisplayMode = { __ename__ : true, __constructs__ : ["Default","Position","Usage","Type","TopLevel","Resolve"] };
haxe_DisplayMode.Default = ["Default",0];
haxe_DisplayMode.Default.toString = $estr;
haxe_DisplayMode.Default.__enum__ = haxe_DisplayMode;
haxe_DisplayMode.Position = ["Position",1];
haxe_DisplayMode.Position.toString = $estr;
haxe_DisplayMode.Position.__enum__ = haxe_DisplayMode;
haxe_DisplayMode.Usage = ["Usage",2];
haxe_DisplayMode.Usage.toString = $estr;
haxe_DisplayMode.Usage.__enum__ = haxe_DisplayMode;
haxe_DisplayMode.Type = ["Type",3];
haxe_DisplayMode.Type.toString = $estr;
haxe_DisplayMode.Type.__enum__ = haxe_DisplayMode;
haxe_DisplayMode.TopLevel = ["TopLevel",4];
haxe_DisplayMode.TopLevel.toString = $estr;
haxe_DisplayMode.TopLevel.__enum__ = haxe_DisplayMode;
haxe_DisplayMode.Resolve = function(v) { var $x = ["Resolve",5,v]; $x.__enum__ = haxe_DisplayMode; $x.toString = $estr; return $x; };
var haxe_HaxeCmdLine = function() {
	this.reset();
};
haxe_HaxeCmdLine.__name__ = true;
haxe_HaxeCmdLine.prototype = {
	clear: function(haveToClearPatch) {
		if(haveToClearPatch == null) haveToClearPatch = false;
		this.cmds = [];
		this.unique = new haxe_ds_StringMap();
		this.workingDir = "";
		if(haveToClearPatch) this.clearPatch();
	}
	,reset: function() {
		this.stack = [];
		this.clear(true);
	}
	,define: function(name,value) {
		if(name != "") {
			var str = "-D " + name;
			if(value != null) str += "=" + value;
			this.cmds.push(str);
		}
		return this;
	}
	,hxml: function(fileName) {
		this.unique.set(" ",fileName);
		return this;
	}
	,cwd: function(dir) {
		this.unique.set("--cwd","" + dir);
		this.workingDir = dir;
		return this;
	}
	,verbose: function() {
		this.unique.set("-v","");
		return this;
	}
	,version: function() {
		this.unique.set("-version","");
		return this;
	}
	,wait: function(port) {
		this.unique.set("--wait","" + port);
		return this;
	}
	,noOutput: function() {
		this.unique.set("--no-output","");
		return this;
	}
	,keywords: function() {
		this.unique.set("--display","keywords");
	}
	,classes: function() {
		this.unique.set("--display","classes");
	}
	,display: function(fileName,pos,mode) {
		var dm;
		switch(mode[1]) {
		case 0:
			dm = "";
			break;
		case 1:
			dm = "@position";
			break;
		case 2:
			dm = "@usage";
			break;
		case 3:
			dm = "@position";
			break;
		case 4:
			dm = "@toplevel";
			break;
		case 5:
			var v = mode[2];
			dm = "@resolve@" + v;
			break;
		}
		this.unique.set("--display","" + fileName + "@" + pos + dm);
		return this;
	}
	,help: function() {
		this.unique.set("--help","");
		return this;
	}
	,helpDefines: function() {
		this.unique.set("--help-defines","");
		return this;
	}
	,helpMetas: function() {
		this.unique.set("--help-metas","");
		return this;
	}
	,custom: function(argName,data,is_unique) {
		if(is_unique == null) is_unique = true;
		if(is_unique) this.unique.set(argName,data); else this.cmds.push("" + argName + " " + data);
		return this;
	}
	,beginPatch: function(fileName) {
		var tmp = this.patchers.get(fileName);
		if(tmp == null) tmp = new haxe_HaxePatcherCmd(fileName);
		this.patchers.set(fileName,tmp);
		return tmp;
	}
	,clearPatch: function() {
		this.patchers = new haxe_ds_StringMap();
		return this;
	}
	,save: function() {
		var wd = this.workingDir;
		var pt = this.patchers;
		this.stack.push({ cmds : this.cmds, unique : this.unique, workingDir : wd});
		this.clear();
		this.patchers = pt;
		if(wd != "") this.cwd(wd);
		return this;
	}
	,restore: function() {
		var i = this.stack.pop();
		this.cmds = i.cmds;
		this.unique = i.unique;
		this.workingDir = i.workingDir;
		return this;
	}
	,clone: function() {
		var cl = new haxe_HaxeCmdLine();
		cl.cmds = this.cmds.concat([]);
		var clu = cl.unique;
		var $it0 = this.unique.keys();
		while( $it0.hasNext() ) {
			var key = $it0.next();
			var value = this.unique.get(key);
			if(__map_reserved[key] != null) clu.setReserved(key,value); else clu.h[key] = value;
		}
		cl.workingDir = this.workingDir;
		return cl;
	}
	,toString: function() {
		var cmds = this.cmds.concat([]);
		var $it0 = this.unique.keys();
		while( $it0.hasNext() ) {
			var key = $it0.next();
			cmds.push(key + " " + this.unique.get(key));
		}
		var $it1 = this.patchers.keys();
		while( $it1.hasNext() ) {
			var key1 = $it1.next();
			cmds.push(this.patchers.get(key1).toString());
		}
		return cmds.join("\n");
	}
	,__class__: haxe_HaxeCmdLine
};
var haxe_HaxeConfiguration = function() { };
haxe_HaxeConfiguration.__name__ = true;
haxe_HaxeConfiguration.addTrailingSep = function(path,platform) {
	if(path == "") return path;
	path = path.split(platform.reversePathSeparator).join(platform.pathSeparator);
	if(path.charAt(path.length - 1) != platform.pathSeparator) path += platform.pathSeparator;
	return path;
};
haxe_HaxeConfiguration.update = function(conf,platform) {
	var exec = "haxe" + platform.executableExtension;
	var tmp = haxe_HaxeConfiguration.addTrailingSep(conf.haxePath,platform);
	conf.haxePath = tmp;
	conf.haxeExec = tmp + exec;
	tmp = haxe_HaxeConfiguration.addTrailingSep(conf.haxelibPath,platform);
	conf.haxelibPath = tmp;
	conf.haxelibExec = tmp + "haxelib" + platform.executableExtension;
	return conf;
};
var haxe_HaxePatcherCmd = function(fileName) {
	this.fileName = fileName;
	this.actions = [];
};
haxe_HaxePatcherCmd.__name__ = true;
haxe_HaxePatcherCmd.$name = function() {
	return "--patch";
};
haxe_HaxePatcherCmd.opToString = function(pop) {
	var _g = pop.op;
	switch(_g) {
	case "+":
		return "" + pop.unit + "+" + pop.pos + ":" + pop.content + "\x01";
	case "-":
		return "" + pop.unit + "-" + pop.pos + ":" + pop.len + "\x01";
	case "r":
		return "" + pop.unit + "-" + "0:-1\x01@" + pop.unit + "+" + "0:" + pop.content + "\x01";
	}
};
haxe_HaxePatcherCmd.prototype = {
	reset: function() {
		this.actions = [];
		return this;
	}
	,remove: function() {
		this.pendingOP = null;
		this.actions = ["x\x01"];
		return this;
	}
	,'delete': function(pos,len,unit) {
		if(unit == null) unit = "b";
		var op = "-";
		if(this.pendingOP == null) this.pendingOP = { unit : unit, op : op, pos : pos, len : len}; else if(this.pendingOP.op == op && this.pendingOP.unit == unit) {
			if(this.pendingOP.pos == pos) this.pendingOP.len += len; else if(this.pendingOP.pos == pos + len) {
				this.pendingOP.len += len;
				this.pendingOP.pos = pos;
			} else {
				this.actions.push(haxe_HaxePatcherCmd.opToString(this.pendingOP));
				this.pendingOP = { unit : unit, op : op, pos : pos, len : len};
			}
		} else {
			this.actions.push(haxe_HaxePatcherCmd.opToString(this.pendingOP));
			this.pendingOP = { unit : unit, op : op, pos : pos, len : len};
		}
		return this;
	}
	,insert: function(pos,len,text,unit) {
		if(unit == null) unit = "b";
		var op = "+";
		if(this.pendingOP == null) this.pendingOP = { unit : unit, op : op, pos : pos, len : len, content : text}; else if(this.pendingOP.op == op && this.pendingOP.unit == unit) {
			if(this.pendingOP.pos + this.pendingOP.len == pos) {
				this.pendingOP.len += len;
				this.pendingOP.content += text;
			} else if(this.pendingOP.pos == pos) {
				this.pendingOP.len += len;
				this.pendingOP.content = text + this.pendingOP.content;
			} else {
				this.actions.push(haxe_HaxePatcherCmd.opToString(this.pendingOP));
				this.pendingOP = { unit : unit, op : op, pos : pos, len : len, content : text};
			}
		} else {
			this.actions.push(haxe_HaxePatcherCmd.opToString(this.pendingOP));
			this.pendingOP = { unit : unit, op : op, pos : pos, len : len, content : text};
		}
		return this;
	}
	,replace: function(text) {
		var unit = "b";
		var op = "r";
		if(this.pendingOP == null) this.pendingOP = { unit : unit, op : op, pos : 0, len : -1, content : text}; else if(this.pendingOP.op == op) this.pendingOP.content = text; else {
			this.actions.push(haxe_HaxePatcherCmd.opToString(this.pendingOP));
			this.pendingOP = { unit : unit, op : op, pos : 0, len : -1, content : text};
		}
		return this;
	}
	,toString: function() {
		if(this.pendingOP != null) {
			this.actions.push(haxe_HaxePatcherCmd.opToString(this.pendingOP));
			this.pendingOP = null;
		}
		if(this.actions.length == 0) return "";
		var tmp = this.actions.join("@");
		var cmd = "--patch" + (" " + this.fileName + "@" + tmp + "\n");
		return cmd;
	}
	,__class__: haxe_HaxePatcherCmd
};
var haxe__$Int64__$_$_$Int64 = function(high,low) {
	this.high = high;
	this.low = low;
};
haxe__$Int64__$_$_$Int64.__name__ = true;
haxe__$Int64__$_$_$Int64.prototype = {
	__class__: haxe__$Int64__$_$_$Int64
};
var haxe_Timer = function(time_ms) {
	var me = this;
	this.id = setInterval(function() {
		me.run();
	},time_ms);
};
haxe_Timer.__name__ = true;
haxe_Timer.delay = function(f,time_ms) {
	var t = new haxe_Timer(time_ms);
	t.run = function() {
		t.stop();
		f();
	};
	return t;
};
haxe_Timer.prototype = {
	stop: function() {
		if(this.id == null) return;
		clearInterval(this.id);
		this.id = null;
	}
	,run: function() {
	}
	,__class__: haxe_Timer
};
var haxe_crypto_Sha1 = function() {
};
haxe_crypto_Sha1.__name__ = true;
haxe_crypto_Sha1.encode = function(s) {
	var sh = new haxe_crypto_Sha1();
	var h = sh.doEncode(haxe_crypto_Sha1.str2blks(s));
	return sh.hex(h);
};
haxe_crypto_Sha1.str2blks = function(s) {
	var nblk = (s.length + 8 >> 6) + 1;
	var blks = [];
	var _g1 = 0;
	var _g = nblk * 16;
	while(_g1 < _g) {
		var i1 = _g1++;
		blks[i1] = 0;
	}
	var _g11 = 0;
	var _g2 = s.length;
	while(_g11 < _g2) {
		var i2 = _g11++;
		var p1 = i2 >> 2;
		blks[p1] |= HxOverrides.cca(s,i2) << 24 - ((i2 & 3) << 3);
	}
	var i = s.length;
	var p = i >> 2;
	blks[p] |= 128 << 24 - ((i & 3) << 3);
	blks[nblk * 16 - 1] = s.length * 8;
	return blks;
};
haxe_crypto_Sha1.prototype = {
	doEncode: function(x) {
		var w = [];
		var a = 1732584193;
		var b = -271733879;
		var c = -1732584194;
		var d = 271733878;
		var e = -1009589776;
		var i = 0;
		while(i < x.length) {
			var olda = a;
			var oldb = b;
			var oldc = c;
			var oldd = d;
			var olde = e;
			var j = 0;
			while(j < 80) {
				if(j < 16) w[j] = x[i + j]; else w[j] = this.rol(w[j - 3] ^ w[j - 8] ^ w[j - 14] ^ w[j - 16],1);
				var t = (a << 5 | a >>> 27) + this.ft(j,b,c,d) + e + w[j] + this.kt(j);
				e = d;
				d = c;
				c = b << 30 | b >>> 2;
				b = a;
				a = t;
				j++;
			}
			a += olda;
			b += oldb;
			c += oldc;
			d += oldd;
			e += olde;
			i += 16;
		}
		return [a,b,c,d,e];
	}
	,rol: function(num,cnt) {
		return num << cnt | num >>> 32 - cnt;
	}
	,ft: function(t,b,c,d) {
		if(t < 20) return b & c | ~b & d;
		if(t < 40) return b ^ c ^ d;
		if(t < 60) return b & c | b & d | c & d;
		return b ^ c ^ d;
	}
	,kt: function(t) {
		if(t < 20) return 1518500249;
		if(t < 40) return 1859775393;
		if(t < 60) return -1894007588;
		return -899497514;
	}
	,hex: function(a) {
		var str = "";
		var _g = 0;
		while(_g < a.length) {
			var num = a[_g];
			++_g;
			str += StringTools.hex(num,8);
		}
		return str.toLowerCase();
	}
	,__class__: haxe_crypto_Sha1
};
var haxe_ds__$StringMap_StringMapIterator = function(map,keys) {
	this.map = map;
	this.keys = keys;
	this.index = 0;
	this.count = keys.length;
};
haxe_ds__$StringMap_StringMapIterator.__name__ = true;
haxe_ds__$StringMap_StringMapIterator.prototype = {
	hasNext: function() {
		return this.index < this.count;
	}
	,next: function() {
		return this.map.get(this.keys[this.index++]);
	}
	,__class__: haxe_ds__$StringMap_StringMapIterator
};
var haxe_ds_StringMap = function() {
	this.h = { };
};
haxe_ds_StringMap.__name__ = true;
haxe_ds_StringMap.__interfaces__ = [haxe_IMap];
haxe_ds_StringMap.prototype = {
	set: function(key,value) {
		if(__map_reserved[key] != null) this.setReserved(key,value); else this.h[key] = value;
	}
	,get: function(key) {
		if(__map_reserved[key] != null) return this.getReserved(key);
		return this.h[key];
	}
	,setReserved: function(key,value) {
		if(this.rh == null) this.rh = { };
		this.rh["$" + key] = value;
	}
	,getReserved: function(key) {
		if(this.rh == null) return null; else return this.rh["$" + key];
	}
	,remove: function(key) {
		if(__map_reserved[key] != null) {
			key = "$" + key;
			if(this.rh == null || !this.rh.hasOwnProperty(key)) return false;
			delete(this.rh[key]);
			return true;
		} else {
			if(!this.h.hasOwnProperty(key)) return false;
			delete(this.h[key]);
			return true;
		}
	}
	,keys: function() {
		var _this = this.arrayKeys();
		return HxOverrides.iter(_this);
	}
	,arrayKeys: function() {
		var out = [];
		for( var key in this.h ) {
		if(this.h.hasOwnProperty(key)) out.push(key);
		}
		if(this.rh != null) {
			for( var key in this.rh ) {
			if(key.charCodeAt(0) == 36) out.push(key.substr(1));
			}
		}
		return out;
	}
	,iterator: function() {
		return new haxe_ds__$StringMap_StringMapIterator(this,this.arrayKeys());
	}
	,__class__: haxe_ds_StringMap
};
var haxe_io_Error = { __ename__ : true, __constructs__ : ["Blocked","Overflow","OutsideBounds","Custom"] };
haxe_io_Error.Blocked = ["Blocked",0];
haxe_io_Error.Blocked.toString = $estr;
haxe_io_Error.Blocked.__enum__ = haxe_io_Error;
haxe_io_Error.Overflow = ["Overflow",1];
haxe_io_Error.Overflow.toString = $estr;
haxe_io_Error.Overflow.__enum__ = haxe_io_Error;
haxe_io_Error.OutsideBounds = ["OutsideBounds",2];
haxe_io_Error.OutsideBounds.toString = $estr;
haxe_io_Error.OutsideBounds.__enum__ = haxe_io_Error;
haxe_io_Error.Custom = function(e) { var $x = ["Custom",3,e]; $x.__enum__ = haxe_io_Error; $x.toString = $estr; return $x; };
var haxe_io_FPHelper = function() { };
haxe_io_FPHelper.__name__ = true;
haxe_io_FPHelper.i32ToFloat = function(i) {
	var sign = 1 - (i >>> 31 << 1);
	var exp = i >>> 23 & 255;
	var sig = i & 8388607;
	if(sig == 0 && exp == 0) return 0.0;
	return sign * (1 + Math.pow(2,-23) * sig) * Math.pow(2,exp - 127);
};
haxe_io_FPHelper.floatToI32 = function(f) {
	if(f == 0) return 0;
	var af;
	if(f < 0) af = -f; else af = f;
	var exp = Math.floor(Math.log(af) / 0.6931471805599453);
	if(exp < -127) exp = -127; else if(exp > 128) exp = 128;
	var sig = Math.round((af / Math.pow(2,exp) - 1) * 8388608) & 8388607;
	return (f < 0?-2147483648:0) | exp + 127 << 23 | sig;
};
haxe_io_FPHelper.i64ToDouble = function(low,high) {
	var sign = 1 - (high >>> 31 << 1);
	var exp = (high >> 20 & 2047) - 1023;
	var sig = (high & 1048575) * 4294967296. + (low >>> 31) * 2147483648. + (low & 2147483647);
	if(sig == 0 && exp == -1023) return 0.0;
	return sign * (1.0 + Math.pow(2,-52) * sig) * Math.pow(2,exp);
};
haxe_io_FPHelper.doubleToI64 = function(v) {
	var i64 = haxe_io_FPHelper.i64tmp;
	if(v == 0) {
		i64.low = 0;
		i64.high = 0;
	} else {
		var av;
		if(v < 0) av = -v; else av = v;
		var exp = Math.floor(Math.log(av) / 0.6931471805599453);
		var sig;
		var v1 = (av / Math.pow(2,exp) - 1) * 4503599627370496.;
		sig = Math.round(v1);
		var sig_l = sig | 0;
		var sig_h = sig / 4294967296.0 | 0;
		i64.low = sig_l;
		i64.high = (v < 0?-2147483648:0) | exp + 1023 << 20 | sig_h;
	}
	return i64;
};
var js__$Boot_HaxeError = function(val) {
	Error.call(this);
	this.val = val;
	this.message = String(val);
	if(Error.captureStackTrace) Error.captureStackTrace(this,js__$Boot_HaxeError);
};
js__$Boot_HaxeError.__name__ = true;
js__$Boot_HaxeError.__super__ = Error;
js__$Boot_HaxeError.prototype = $extend(Error.prototype,{
	__class__: js__$Boot_HaxeError
});
var js_Boot = function() { };
js_Boot.__name__ = true;
js_Boot.getClass = function(o) {
	if((o instanceof Array) && o.__enum__ == null) return Array; else {
		var cl = o.__class__;
		if(cl != null) return cl;
		var name = js_Boot.__nativeClassName(o);
		if(name != null) return js_Boot.__resolveNativeClass(name);
		return null;
	}
};
js_Boot.__string_rec = function(o,s) {
	if(o == null) return "null";
	if(s.length >= 5) return "<...>";
	var t = typeof(o);
	if(t == "function" && (o.__name__ || o.__ename__)) t = "object";
	switch(t) {
	case "object":
		if(o instanceof Array) {
			if(o.__enum__) {
				if(o.length == 2) return o[0];
				var str2 = o[0] + "(";
				s += "\t";
				var _g1 = 2;
				var _g = o.length;
				while(_g1 < _g) {
					var i1 = _g1++;
					if(i1 != 2) str2 += "," + js_Boot.__string_rec(o[i1],s); else str2 += js_Boot.__string_rec(o[i1],s);
				}
				return str2 + ")";
			}
			var l = o.length;
			var i;
			var str1 = "[";
			s += "\t";
			var _g2 = 0;
			while(_g2 < l) {
				var i2 = _g2++;
				str1 += (i2 > 0?",":"") + js_Boot.__string_rec(o[i2],s);
			}
			str1 += "]";
			return str1;
		}
		var tostr;
		try {
			tostr = o.toString;
		} catch( e ) {
			if (e instanceof js__$Boot_HaxeError) e = e.val;
			return "???";
		}
		if(tostr != null && tostr != Object.toString && typeof(tostr) == "function") {
			var s2 = o.toString();
			if(s2 != "[object Object]") return s2;
		}
		var k = null;
		var str = "{\n";
		s += "\t";
		var hasp = o.hasOwnProperty != null;
		for( var k in o ) {
		if(hasp && !o.hasOwnProperty(k)) {
			continue;
		}
		if(k == "prototype" || k == "__class__" || k == "__super__" || k == "__interfaces__" || k == "__properties__") {
			continue;
		}
		if(str.length != 2) str += ", \n";
		str += s + k + " : " + js_Boot.__string_rec(o[k],s);
		}
		s = s.substring(1);
		str += "\n" + s + "}";
		return str;
	case "function":
		return "<function>";
	case "string":
		return o;
	default:
		return String(o);
	}
};
js_Boot.__interfLoop = function(cc,cl) {
	if(cc == null) return false;
	if(cc == cl) return true;
	var intf = cc.__interfaces__;
	if(intf != null) {
		var _g1 = 0;
		var _g = intf.length;
		while(_g1 < _g) {
			var i = _g1++;
			var i1 = intf[i];
			if(i1 == cl || js_Boot.__interfLoop(i1,cl)) return true;
		}
	}
	return js_Boot.__interfLoop(cc.__super__,cl);
};
js_Boot.__instanceof = function(o,cl) {
	if(cl == null) return false;
	switch(cl) {
	case Int:
		return (o|0) === o;
	case Float:
		return typeof(o) == "number";
	case Bool:
		return typeof(o) == "boolean";
	case String:
		return typeof(o) == "string";
	case Array:
		return (o instanceof Array) && o.__enum__ == null;
	case Dynamic:
		return true;
	default:
		if(o != null) {
			if(typeof(cl) == "function") {
				if(o instanceof cl) return true;
				if(js_Boot.__interfLoop(js_Boot.getClass(o),cl)) return true;
			} else if(typeof(cl) == "object" && js_Boot.__isNativeObj(cl)) {
				if(o instanceof cl) return true;
			}
		} else return false;
		if(cl == Class && o.__name__ != null) return true;
		if(cl == Enum && o.__ename__ != null) return true;
		return o.__enum__ == cl;
	}
};
js_Boot.__nativeClassName = function(o) {
	var name = js_Boot.__toStr.call(o).slice(8,-1);
	if(name == "Object" || name == "Function" || name == "Math" || name == "JSON") return null;
	return name;
};
js_Boot.__isNativeObj = function(o) {
	return js_Boot.__nativeClassName(o) != null;
};
js_Boot.__resolveNativeClass = function(name) {
	return (Function("return typeof " + name + " != \"undefined\" ? " + name + " : null"))();
};
var js_html_compat_ArrayBuffer = function(a) {
	if((a instanceof Array) && a.__enum__ == null) {
		this.a = a;
		this.byteLength = a.length;
	} else {
		var len = a;
		this.a = [];
		var _g = 0;
		while(_g < len) {
			var i = _g++;
			this.a[i] = 0;
		}
		this.byteLength = len;
	}
};
js_html_compat_ArrayBuffer.__name__ = true;
js_html_compat_ArrayBuffer.sliceImpl = function(begin,end) {
	var u = new Uint8Array(this,begin,end == null?null:end - begin);
	var result = new ArrayBuffer(u.byteLength);
	var resultArray = new Uint8Array(result);
	resultArray.set(u);
	return result;
};
js_html_compat_ArrayBuffer.prototype = {
	slice: function(begin,end) {
		return new js_html_compat_ArrayBuffer(this.a.slice(begin,end));
	}
	,__class__: js_html_compat_ArrayBuffer
};
var js_html_compat_DataView = function(buffer,byteOffset,byteLength) {
	this.buf = buffer;
	if(byteOffset == null) this.offset = 0; else this.offset = byteOffset;
	if(byteLength == null) this.length = buffer.byteLength - this.offset; else this.length = byteLength;
	if(this.offset < 0 || this.length < 0 || this.offset + this.length > buffer.byteLength) throw new js__$Boot_HaxeError(haxe_io_Error.OutsideBounds);
};
js_html_compat_DataView.__name__ = true;
js_html_compat_DataView.prototype = {
	getInt8: function(byteOffset) {
		var v = this.buf.a[this.offset + byteOffset];
		if(v >= 128) return v - 256; else return v;
	}
	,getUint8: function(byteOffset) {
		return this.buf.a[this.offset + byteOffset];
	}
	,getInt16: function(byteOffset,littleEndian) {
		var v = this.getUint16(byteOffset,littleEndian);
		if(v >= 32768) return v - 65536; else return v;
	}
	,getUint16: function(byteOffset,littleEndian) {
		if(littleEndian) return this.buf.a[this.offset + byteOffset] | this.buf.a[this.offset + byteOffset + 1] << 8; else return this.buf.a[this.offset + byteOffset] << 8 | this.buf.a[this.offset + byteOffset + 1];
	}
	,getInt32: function(byteOffset,littleEndian) {
		var p = this.offset + byteOffset;
		var a = this.buf.a[p++];
		var b = this.buf.a[p++];
		var c = this.buf.a[p++];
		var d = this.buf.a[p++];
		if(littleEndian) return a | b << 8 | c << 16 | d << 24; else return d | c << 8 | b << 16 | a << 24;
	}
	,getUint32: function(byteOffset,littleEndian) {
		var v = this.getInt32(byteOffset,littleEndian);
		if(v < 0) return v + 4294967296.; else return v;
	}
	,getFloat32: function(byteOffset,littleEndian) {
		return haxe_io_FPHelper.i32ToFloat(this.getInt32(byteOffset,littleEndian));
	}
	,getFloat64: function(byteOffset,littleEndian) {
		var a = this.getInt32(byteOffset,littleEndian);
		var b = this.getInt32(byteOffset + 4,littleEndian);
		return haxe_io_FPHelper.i64ToDouble(littleEndian?a:b,littleEndian?b:a);
	}
	,setInt8: function(byteOffset,value) {
		if(value < 0) this.buf.a[byteOffset + this.offset] = value + 128 & 255; else this.buf.a[byteOffset + this.offset] = value & 255;
	}
	,setUint8: function(byteOffset,value) {
		this.buf.a[byteOffset + this.offset] = value & 255;
	}
	,setInt16: function(byteOffset,value,littleEndian) {
		this.setUint16(byteOffset,value < 0?value + 65536:value,littleEndian);
	}
	,setUint16: function(byteOffset,value,littleEndian) {
		var p = byteOffset + this.offset;
		if(littleEndian) {
			this.buf.a[p] = value & 255;
			this.buf.a[p++] = value >> 8 & 255;
		} else {
			this.buf.a[p++] = value >> 8 & 255;
			this.buf.a[p] = value & 255;
		}
	}
	,setInt32: function(byteOffset,value,littleEndian) {
		this.setUint32(byteOffset,value,littleEndian);
	}
	,setUint32: function(byteOffset,value,littleEndian) {
		var p = byteOffset + this.offset;
		if(littleEndian) {
			this.buf.a[p++] = value & 255;
			this.buf.a[p++] = value >> 8 & 255;
			this.buf.a[p++] = value >> 16 & 255;
			this.buf.a[p++] = value >>> 24;
		} else {
			this.buf.a[p++] = value >>> 24;
			this.buf.a[p++] = value >> 16 & 255;
			this.buf.a[p++] = value >> 8 & 255;
			this.buf.a[p++] = value & 255;
		}
	}
	,setFloat32: function(byteOffset,value,littleEndian) {
		this.setUint32(byteOffset,haxe_io_FPHelper.floatToI32(value),littleEndian);
	}
	,setFloat64: function(byteOffset,value,littleEndian) {
		var i64 = haxe_io_FPHelper.doubleToI64(value);
		if(littleEndian) {
			this.setUint32(byteOffset,i64.low);
			this.setUint32(byteOffset,i64.high);
		} else {
			this.setUint32(byteOffset,i64.high);
			this.setUint32(byteOffset,i64.low);
		}
	}
	,__class__: js_html_compat_DataView
};
var js_html_compat_Uint8Array = function() { };
js_html_compat_Uint8Array.__name__ = true;
js_html_compat_Uint8Array._new = function(arg1,offset,length) {
	var arr;
	if(typeof(arg1) == "number") {
		arr = [];
		var _g = 0;
		while(_g < arg1) {
			var i = _g++;
			arr[i] = 0;
		}
		arr.byteLength = arr.length;
		arr.byteOffset = 0;
		arr.buffer = new js_html_compat_ArrayBuffer(arr);
	} else if(js_Boot.__instanceof(arg1,js_html_compat_ArrayBuffer)) {
		var buffer = arg1;
		if(offset == null) offset = 0;
		if(length == null) length = buffer.byteLength - offset;
		if(offset == 0) arr = buffer.a; else arr = buffer.a.slice(offset,offset + length);
		arr.byteLength = arr.length;
		arr.byteOffset = offset;
		arr.buffer = buffer;
	} else if((arg1 instanceof Array) && arg1.__enum__ == null) {
		arr = arg1.slice();
		arr.byteLength = arr.length;
		arr.byteOffset = 0;
		arr.buffer = new js_html_compat_ArrayBuffer(arr);
	} else throw new js__$Boot_HaxeError("TODO " + Std.string(arg1));
	arr.subarray = js_html_compat_Uint8Array._subarray;
	arr.set = js_html_compat_Uint8Array._set;
	return arr;
};
js_html_compat_Uint8Array._set = function(arg,offset) {
	var t = this;
	if(js_Boot.__instanceof(arg.buffer,js_html_compat_ArrayBuffer)) {
		var a = arg;
		if(arg.byteLength + offset > t.byteLength) throw new js__$Boot_HaxeError("set() outside of range");
		var _g1 = 0;
		var _g = arg.byteLength;
		while(_g1 < _g) {
			var i = _g1++;
			t[i + offset] = a[i];
		}
	} else if((arg instanceof Array) && arg.__enum__ == null) {
		var a1 = arg;
		if(a1.length + offset > t.byteLength) throw new js__$Boot_HaxeError("set() outside of range");
		var _g11 = 0;
		var _g2 = a1.length;
		while(_g11 < _g2) {
			var i1 = _g11++;
			t[i1 + offset] = a1[i1];
		}
	} else throw new js__$Boot_HaxeError("TODO");
};
js_html_compat_Uint8Array._subarray = function(start,end) {
	var t = this;
	var a = js_html_compat_Uint8Array._new(t.slice(start,end));
	a.byteOffset = start;
	return a;
};
var js_node_ChildProcess = require("child_process");
var js_node_Fs = require("fs");
var js_node_Path = require("path");
var js_node_buffer_Buffer = require("buffer").Buffer;
var js_node_net_Socket = require("net").Socket;
var platform_Platform = function() {
};
platform_Platform.__name__ = true;
platform_Platform.init = function(platformName) {
	if(platform_Platform.instance == null) platform_Platform.instance = new platform_Platform();
	if(platformName == "win32") {
		platform_Platform.instance.pathSeparator = "\\";
		platform_Platform.instance.reversePathSeparator = "/";
		platform_Platform.instance.executableExtension = ".exe";
		platform_Platform.instance.isWin = true;
	} else {
		platform_Platform.instance.pathSeparator = "/";
		platform_Platform.instance.reversePathSeparator = "\\";
		platform_Platform.instance.executableExtension = "";
		platform_Platform.instance.isWin = false;
	}
	return platform_Platform.instance;
};
platform_Platform.prototype = {
	__class__: platform_Platform
};
var $_, $fid = 0;
function $bind(o,m) { if( m == null ) return null; if( m.__id__ == null ) m.__id__ = $fid++; var f; if( o.hx__closures__ == null ) o.hx__closures__ = {}; else f = o.hx__closures__[m.__id__]; if( f == null ) { f = function(){ return f.method.apply(f.scope, arguments); }; f.scope = o; f.method = m; o.hx__closures__[m.__id__] = f; } return f; }
String.prototype.__class__ = String;
String.__name__ = true;
Array.__name__ = true;
Date.prototype.__class__ = Date;
Date.__name__ = ["Date"];
var Int = { __name__ : ["Int"]};
var Dynamic = { __name__ : ["Dynamic"]};
var Float = Number;
Float.__name__ = ["Float"];
var Bool = Boolean;
Bool.__ename__ = ["Bool"];
var Class = { __name__ : ["Class"]};
var Enum = { };
var __map_reserved = {}
var ArrayBuffer = (Function("return typeof ArrayBuffer != 'undefined' ? ArrayBuffer : null"))() || js_html_compat_ArrayBuffer;
if(ArrayBuffer.prototype.slice == null) ArrayBuffer.prototype.slice = js_html_compat_ArrayBuffer.sliceImpl;
var DataView = (Function("return typeof DataView != 'undefined' ? DataView : null"))() || js_html_compat_DataView;
var Uint8Array = (Function("return typeof Uint8Array != 'undefined' ? Uint8Array : null"))() || js_html_compat_Uint8Array._new;
HaxeContext.reWS = new EReg("[\\s\t\r\n]","");
HxmlContext.reComment = new EReg("\\s*#(.+)","");
HxmlContext.reCheckOption = new EReg("^\\s*(-(-)?)([^\\s]+)(\\s+(.*))?","");
HxmlContext.reDefineParam = new EReg("([^=]+)(=(.+))?","");
HxmlContext.reMain = new EReg("\\s*(.+)","");
HxmlContext.reLibOption = new EReg("^\\s*-lib\\s+([^\\s]+)(.*)","");
HxmlContext.reCpOption = new EReg("^\\s*-cp\\s+([^#]+)(.*)","");
HxmlContext.reEach = new EReg("^\\s*--each(.*)","");
HxmlContext.reNext = new EReg("^\\s*--next(.*)","");
features_CompletionHandler.reI = new EReg("<i n=\"([^\"]+)\" k=\"([^\"]+)\"( ip=\"([0-1])\")?( f=\"(\\d+)\")?><t>([^<]*)</t><d>([^<]*)</d></i>","");
features_CompletionHandler.reGT = new EReg("&gt;","g");
features_CompletionHandler.reLT = new EReg("&lt;","g");
features_CompletionHandler.reMethod = new EReg("Void|Unknown","");
features_CompletionHandler.reWord = new EReg("[a-zA-Z_$]","");
features_CompletionHandler.reWS = new EReg("[\r\n\t\\s]","");
features_DefinitionHandler.rePos = new EReg("[^<]*<pos>(.+)</pos>.*","");
features_FunctionDecoder.reFirstId = new EReg("[_a-zA-Z]","");
features_FunctionDecoder.reLastId = new EReg("[0-9_a-zA-Z]","");
features_FunctionDecoder.reWS = new EReg("[\r\n\t\\s]","");
features_SignatureHandler.reType = new EReg("<type(\\s+opar='(\\d+)')?(\\s+index='(\\d+)')?>","");
features_SignatureHandler.reGT = new EReg("&gt;","g");
features_SignatureHandler.reLT = new EReg("&lt;","g");
features_SignatureHandler.reFatalError = new EReg("\\s*@fatalError(\\s+(.*))?","");
features_hxml_CompletionHandler.reI = new EReg("<i n=\"([^\"]+)\" k=\"([^\"]+)\"( ip=\"([0-1])\")?( f=\"(\\d+)\")?><t>([^<]*)</t><d>([^<]*)</d></i>","");
features_hxml_CompletionHandler.reGT = new EReg("&gt;","g");
features_hxml_CompletionHandler.reLT = new EReg("&lt;","g");
features_hxml_CompletionHandler.reMethod = new EReg("Void|Unknown","");
haxe_Info.reWin = new EReg("^\\w+:\\\\","");
haxe_Info.re1 = new EReg("^((\\w+:\\\\)?([^:]+)):(\\d+):\\s*([^:]+)(:(.+))?","");
haxe_Info.re2 = new EReg("^((character[s]?)|(line[s]?))\\s+(\\d+)(\\-(\\d+))?","");
haxe_HaxeClient.jobId = 0;
haxe_HaxeClient.reVersion = new EReg("^Haxe\\s+(.+?)(\\d+).(\\d+).(\\d+)(.+)?","");
haxe_HaxeClient.reCheckOption = new EReg("^\\s*(-(-)?)(.+?) : ([\\s\\S]+)","");
haxe_HaxeClient.reCheckDefine = new EReg("^\\s*([^\\s]+)\\s+: ([\\s\\S]+)","");
haxe_HaxeClient.reCheckMeta = new EReg("^\\s*(@:)([^\\s]+)\\s+: ([\\s\\S]+)","");
haxe_HaxeClient.reCheckOptionName = new EReg("([^\\s]+)(\\s+(.+))?","");
haxe_HaxeClient.reKeywords = new EReg("n=\\\\\"([^\\\\]+?)\\\\\"","g");
haxe_io_FPHelper.i64tmp = (function($this) {
	var $r;
	var x = new haxe__$Int64__$_$_$Int64(0,0);
	$r = x;
	return $r;
}(this));
js_Boot.__toStr = {}.toString;
js_html_compat_Uint8Array.BYTES_PER_ELEMENT = 1;
})(typeof window != "undefined" ? window : exports);
