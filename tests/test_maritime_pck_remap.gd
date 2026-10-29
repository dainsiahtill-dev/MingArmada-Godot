extends SceneTree
## Narrow export-remap regression probe, not a complete export certification.
## Parent writes only Temp pack/staging plus evidence. Child runs headlessly
## from an isolated project root whose PCK contains .png.remap/.ctex, no PNG.
const ART := "res://game/ui/shared/maritime_art_theme.gd"
const SELF := "res://tests/test_maritime_pck_remap.gd"
const QUIET := "res://assets/ui/ming_maritime/painted/quiet/"
const FRAME := QUIET+"framed/runtime/"
var assertions := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func check(value: bool,detail: String) -> bool:
	assertions+=1
	if not value: failures+=1;printerr("FAIL: ",detail)
	return value

func _hash(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256);context.update(bytes)
	return context.finish().hex_encode()

func _pixels(texture: Texture2D) -> Image:
	var result := texture.get_image()
	if result.is_compressed(): result.decompress()
	result.convert(Image.FORMAT_RGBA8)
	return result

func _write(path: String,content: String) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(content);file.close()

func _argument(prefix: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(prefix): return arg.trim_prefix(prefix)
	return ""

func _run() -> void:
	if "--remap-child" in OS.get_cmdline_user_args(): _child()
	else: _parent()

func _parent() -> void:
	var script=load(ART)
	if not check(script!=null and script.has_method("has_texture"),"current production theme exposes remap-aware has_texture"):
		_finish();return
	var task_root := ProjectSettings.globalize_path("res://Temp/maritime-pck-remap/"+str(Time.get_ticks_usec()))
	DirAccess.make_dir_recursive_absolute(task_root)
	var manifest := {"schema":1,"scope":"Isolated headless PCK remap and selected production skin factories only; not full export acceptance.","textures":[],"sourceHashes":{}}
	var files: Array[String]=[]
	for filename: String in ["command-panel.png","folio-panel.png","button-normal.png","button-selected.png"]:
		files.append(QUIET+filename);files.append(QUIET+"runtime/"+filename)
	for filename: String in ["command-panel.png","folio-panel.png"]: files.append(FRAME+filename)
	var pack := PCKPacker.new()
	var pack_path := task_root+"/probe.pck"
	if not check(pack.pck_start(pack_path)==OK,"create isolated PCK under Temp"):
		_finish();return
	var minimal := task_root+"/project.godot"
	_write(minimal,"config_version=5\n[application]\nconfig/name=\"Maritime remap probe\"\n[rendering]\nrenderer/rendering_method=\"gl_compatibility\"\n")
	check(pack.add_file("res://project.godot",minimal)==OK,"pack independent project settings")
	for path: String in [SELF,ART,"res://game/ui/shared/parchment_theme.gd","res://game/ui/shared/painted_window_style.gd"]:
		check(pack.add_file(path,ProjectSettings.globalize_path(path))==OK,"pack actual source "+path)
		manifest.sourceHashes[path]=FileAccess.get_sha256(path)
	var included: Dictionary={}
	for path: String in files:
		var config := ConfigFile.new()
		if not check(config.load(path+".import")==OK,"existing native import metadata available for "+path): continue
		var imported := str(config.get_value("remap","path",""))
		if not check(not imported.is_empty() and FileAccess.file_exists(imported),"actual imported .ctex exists for "+path): continue
		var original := Image.new()
		var decoded := original.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
		if not check(decoded==OK,"source quiet/framed PNG decodes before packing"): continue
		original.convert(Image.FORMAT_RGBA8)
		var native := _pixels(load(path) as Texture2D)
		var samples: Array=[]
		for yf in [0.25,0.5,0.75]:
			for xf in [0.25,0.5,0.75]:
				var x:=int(original.get_width()*xf);var y:=int(original.get_height()*yf)
				var color:=original.get_pixel(x,y)
				samples.append({"x":x,"y":y,"rgba":[color.r,color.g,color.b,color.a]})
		manifest.textures.append({"path":path,"ctex":imported,"pngFileSha256":FileAccess.get_sha256(path),"nativeDataSha256":_hash(native.get_data()),"rawDataSha256":_hash(original.get_data()),"size":[native.get_width(),native.get_height()],"samples":samples})
		var remap := task_root+"/remap-"+str(manifest.textures.size())+".txt"
		_write(remap,"[remap]\npath=\""+imported+"\"\n")
		check(pack.add_file(path+".remap",remap)==OK,"pack .png.remap without its original PNG")
		if not included.has(imported):
			check(pack.add_file(imported,ProjectSettings.globalize_path(imported))==OK,"pack actual imported .ctex")
			included[imported]=true
	var manifest_path := task_root+"/probe-manifest.json"
	_write(manifest_path,JSON.stringify(manifest,"\t"))
	check(pack.add_file("res://probe-manifest.json",manifest_path)==OK,"pack independent original pixel fingerprints")
	check(pack.flush()==OK,"finish isolated PCK")
	var receipt_path := task_root+"/child-result.json"
	var output: Array=[]
	var args:=PackedStringArray(["--headless","--path",task_root,"--main-pack",pack_path,"--script",SELF,"--quit-after","120","--","--remap-child","--receipt="+receipt_path])
	var exit_code:=OS.execute(OS.get_executable_path(),args,output,true,false)
	var child_log:=""
	for chunk in output: child_log+=str(chunk)
	_write(task_root+"/child.log",child_log)
	check(exit_code==0,"isolated PCK child exits zero")
	check(not child_log.contains("SCRIPT ERROR:") and not child_log.contains("\nERROR:"),"isolated PCK child has no engine/script error")
	check(FileAccess.file_exists(receipt_path),"isolated child writes a concrete receipt")
	if FileAccess.file_exists(receipt_path):
		var receipt=JSON.parse_string(FileAccess.get_file_as_string(receipt_path))
		check(receipt is Dictionary and receipt.get("failures",-1)==0,"real remap child assertions pass")
		print("PCK_REMAP_CHILD_RECEIPT ",JSON.stringify(receipt))
	var originals_unchanged:=true
	for entry: Dictionary in manifest.textures:
		originals_unchanged=originals_unchanged and FileAccess.file_exists(entry.path) and FileAccess.get_sha256(entry.path)==entry.pngFileSha256
	for path: String in manifest.sourceHashes:
		originals_unchanged=originals_unchanged and FileAccess.get_sha256(path)==manifest.sourceHashes[path]
	check(originals_unchanged,"original PNGs and production/helper sources remain present and byte-identical")
	print("PCK_REMAP_PACK ",pack_path," packed_textures=",manifest.textures.size()," original_pngs_in_pack=0")
	print("PCK_REMAP_CHILD_LOG ",child_log.strip_edges())
	_finish()

func _child() -> void:
	var manifest=JSON.parse_string(FileAccess.get_file_as_string("res://probe-manifest.json"))
	var script=load(ART)
	var observations: Array=[]
	var raw_bytes_equal:=0
	for entry: Dictionary in manifest.textures:
		var path:=str(entry.path)
		check(not FileAccess.file_exists(path),path+" original PNG absent from isolated pack namespace")
		check(FileAccess.file_exists(path+".remap") and FileAccess.file_exists(entry.ctex),path+" has only remap plus imported texture")
		check(ResourceLoader.exists(path),path+" ResourceLoader follows remap")
		check(script.has_texture(path),path+" production has_texture follows remap")
		var texture:=load(path) as Texture2D
		if not check(texture!=null,path+" native texture loads from remap"): continue
		var pixels:=_pixels(texture)
		check(pixels.get_width()==int(entry.size[0]) and pixels.get_height()==int(entry.size[1]) and _hash(pixels.get_data())==entry.nativeDataSha256,path+" packed image bytes equal original native image")
		var delta:=0.0
		for sample: Dictionary in entry.samples:
			var actual:=pixels.get_pixel(sample.x,sample.y)
			for channel in range(4): delta=maxf(delta,absf(actual[channel]-float(sample.rgba[channel])))
		check(delta<=1.0/255.0,path+" visible 3x3 pixel samples match original PNG")
		var full_equal: bool=_hash(pixels.get_data())==entry.rawDataSha256
		if full_equal: raw_bytes_equal+=1
		observations.append({"path":path,"fileAccess":FileAccess.file_exists(path),"resourceLoader":ResourceLoader.exists(path),"hasTexture":script.has_texture(path),"visibleSampleMaximumDelta":delta,"allRgbaBytesEqualRawPng":full_equal})
	var factories: Array=[]
	for test in [["normal",false,QUIET+"runtime/button-normal.png"],["normal",true,QUIET+"runtime/button-selected.png"]]:
		var style: StyleBoxTexture=script.button_style(test[0],test[1])
		_factory(style,str(test[2]),manifest,"button primary="+str(test[1]),factories)
	for tone: String in ["paper","folio"]:
		var style: StyleBox=script.panel(20,tone)
		check(style!=null and style.has_method("get_body_style") and style.has_method("get_edge_style"),"packed panel factory retains layered "+tone)
		if style!=null and style.has_method("get_body_style"):
			var filename:="folio-panel.png" if tone=="folio" else "command-panel.png"
			_factory(style.call("get_body_style"),QUIET+"runtime/"+filename,manifest,"panel body "+tone,factories)
			_factory(style.call("get_edge_style"),FRAME+filename,manifest,"panel edge "+tone,factories)
	var result={"assertions":assertions,"failures":failures,"display":DisplayServer.get_name(),"isolatedResRoot":ProjectSettings.globalize_path("res://"),"textures":observations,"factories":factories,"allRgbaBytesEqualRawPngCount":raw_bytes_equal,"sourceHashes":manifest.sourceHashes,"scope":manifest.scope}
	_write(_argument("--receipt="),JSON.stringify(result,"\t"))
	print("MARITIME_PCK_REMAP_CHILD assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)

func _factory(style: StyleBoxTexture,expected: String,manifest: Dictionary,detail: String,observations: Array) -> void:
	if not check(style!=null and style.texture!=null,"actual packed "+detail+" resolves texture"): return
	check(style.texture.resource_path==expected,"actual packed "+detail+" chooses current runtime family")
	var entry: Dictionary={}
	for candidate: Dictionary in manifest.textures:
		if candidate.path==expected: entry=candidate
	check(not entry.is_empty() and _hash(_pixels(style.texture).get_data())==entry.get("nativeDataSha256",""),"actual packed "+detail+" pixels match expected generated runtime")
	observations.append({"factory":detail,"path":style.texture.resource_path,"rawFileExists":FileAccess.file_exists(expected)})

func _finish() -> void:
	print("MARITIME_PCK_REMAP_TEST assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
