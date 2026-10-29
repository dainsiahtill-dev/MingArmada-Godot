extends SceneTree
## Native import of copied originals, then an isolated remap-only PCK child.
## No source PNG/import metadata is removed or changed by this regression.
const SELF := "res://tests/test_combat_atmosphere_pck.gd"
const LAYER := "res://game/presentation/combat/combat_atmosphere.gd"
const DIRECTORY := "res://assets/textures/combat_atmosphere/r1/"
var assertions := 0
var failures := 0
func _initialize()->void:_run.call_deferred()
func check(value:bool,message:String)->bool:
	assertions+=1
	if not value:failures+=1;printerr("FAIL COMBAT ATMOSPHERE PCK: ",message)
	return value
func write_text(path:String,value:String)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(value);file.close()
func write_bytes(path:String,value:PackedByteArray)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(value);file.close()
func digest(value:PackedByteArray)->String:
	var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256);context.update(value);return context.finish().hex_encode()
func pixels(texture:Texture2D)->Image:
	var image:=texture.get_image()
	if image.is_compressed():image.decompress()
	image.clear_mipmaps();image.convert(Image.FORMAT_RGBA8);return image
func argument(prefix:String)->String:
	for value:String in OS.get_cmdline_user_args():
		if value.begins_with(prefix):return value.trim_prefix(prefix)
	return ""
func execute_isolated(args:PackedStringArray,profile:String)->Dictionary:
	var old_app:=OS.get_environment("APPDATA");var old_local:=OS.get_environment("LOCALAPPDATA")
	DirAccess.make_dir_recursive_absolute(profile+"/roaming");DirAccess.make_dir_recursive_absolute(profile+"/local")
	OS.set_environment("APPDATA",profile+"/roaming");OS.set_environment("LOCALAPPDATA",profile+"/local")
	var output:Array=[]
	var code:=OS.execute(OS.get_executable_path(),args,output,true,false)
	OS.set_environment("APPDATA",old_app);OS.set_environment("LOCALAPPDATA",old_local)
	var log:=""
	for chunk:Variant in output:log+=str(chunk)
	return {"code":code,"log":log}
func _run()->void:
	if "--atmosphere-pck-child" in OS.get_cmdline_user_args():child()
	else:parent()
func parent()->void:
	var task_root:=ProjectSettings.globalize_path("res://Temp/combat-atmosphere-pck/"+str(Time.get_ticks_usec()))
	var imported_root:=task_root+"/native-import"
	DirAccess.make_dir_recursive_absolute(imported_root)
	write_text(task_root+"/.gdignore","")
	var minimal:="config_version=5\n[application]\nconfig/name=\"Combat atmosphere pack probe\"\n[rendering]\nrenderer/rendering_method=\"gl_compatibility\"\n"
	write_text(imported_root+"/project.godot",minimal)
	var originals:Dictionary={LAYER:FileAccess.get_sha256(LAYER),SELF:FileAccess.get_sha256(SELF)}
	for file:String in ["smoke-puff.png","flame.png"]:
		var path:=DIRECTORY+file
		originals[path]=FileAccess.get_sha256(path)
		write_bytes(imported_root+"/"+file,FileAccess.get_file_as_bytes(path))
	var imported:=execute_isolated(PackedStringArray(["--headless","--path",imported_root,"--editor","--import","--quit"]),task_root+"/import-profile")
	write_text(task_root+"/import.log",imported.log)
	if not check(imported.code==0 and not str(imported.log).contains("SCRIPT ERROR:") and not str(imported.log).contains("\nERROR:"),"native import of copied original sprites succeeds"):
		printerr(imported.log);finish();return
	write_text(task_root+"/project.godot",minimal)
	var pack:=PCKPacker.new();var pack_path:=task_root+"/probe.pck"
	if not check(pack.pck_start(pack_path)==OK,"fresh isolated PCK opens"):finish();return
	check(pack.add_file("res://project.godot",task_root+"/project.godot")==OK,"minimal project packed")
	for path:String in [SELF,LAYER]:check(pack.add_file(path,ProjectSettings.globalize_path(path))==OK,"actual source packed: "+path)
	var manifest:Dictionary={"originals":originals,"textures":[],"scope":"Actual native-imported ctex and remap-only PCK, plus raw unimported PNG and editor import adapters; not complete game export certification."}
	for filename:String in ["smoke-puff.png","flame.png"]:
		var config:=ConfigFile.new()
		if not check(config.load(imported_root+"/"+filename+".import")==OK,"copied original has native import metadata"):continue
		var imported_path:=str(config.get_value("remap","path",""))
		var absolute:=imported_root+"/"+imported_path.trim_prefix("res://")
		if not check(imported_path.ends_with(".ctex") and FileAccess.file_exists(absolute),"actual importer produces compressed texture resource"):continue
		check(pack.add_file(imported_path,absolute)==OK,"native ctex packed")
		var canonical:=DIRECTORY+filename
		var remap_file:=task_root+"/"+filename+".remap"
		write_text(remap_file,"[remap]\npath=\""+imported_path+"\"\n")
		check(pack.add_file(canonical+".remap",remap_file)==OK,"canonical PNG has remap only")
		var raw:=Image.new();check(raw.load_png_from_buffer(FileAccess.get_file_as_bytes(canonical))==OK,"original pixels decode")
		raw.convert(Image.FORMAT_RGBA8)
		manifest.textures.append({"path":canonical,"ctex":imported_path,"size":[raw.get_width(),raw.get_height()],"rgbaSha256":digest(raw.get_data())})
		if filename=="smoke-puff.png":
			check(pack.add_file("res://probe/raw.png",ProjectSettings.globalize_path(canonical))==OK,"raw unimported PNG control packed")
			check(pack.add_file("res://probe/imported.png.import",imported_root+"/"+filename+".import")==OK,"editor import adapter control packed")
	write_text(task_root+"/manifest.json",JSON.stringify(manifest,"",false,true))
	check(pack.add_file("res://probe-manifest.json",task_root+"/manifest.json")==OK,"independent fingerprints packed")
	check(pack.flush()==OK,"isolated PCK finalized")
	var receipt_path:=task_root+"/child-result.json"
	var result:=execute_isolated(PackedStringArray(["--headless","--path",task_root,"--main-pack",pack_path,"--script",SELF,"--quit-after","120","--","--atmosphere-pck-child","--receipt="+receipt_path]),task_root+"/child-profile")
	write_text(task_root+"/child.log",result.log)
	check(result.code==0,"remap-only child exits successfully")
	check(not str(result.log).contains("SCRIPT ERROR:") and not str(result.log).contains("\nERROR:"),"child has no load or script errors")
	if check(FileAccess.file_exists(receipt_path),"child produced a concrete receipt"):
		var receipt:Variant=JSON.parse_string(FileAccess.get_file_as_string(receipt_path))
		check(receipt is Dictionary and receipt.get("failures",-1)==0,"actual production loader and layer initialize in remap-only pack")
		print("ATMOSPHERE_PCK_CHILD_RECEIPT ",JSON.stringify(receipt,"",false,true))
	for path:String in originals:check(FileAccess.get_sha256(path)==originals[path],"original remains byte-identical: "+path)
	print("ATMOSPHERE_PCK_PROBE ",task_root)
	print("ATMOSPHERE_PCK_CHILD_LOG ",str(result.log).strip_edges())
	finish()
func child()->void:
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://probe-manifest.json"))
	var layer:Script=load(LAYER)
	var observations:Array=[]
	for entry:Dictionary in manifest.textures:
		var path:String=entry.path
		check(not FileAccess.file_exists(path) and not FileAccess.file_exists(path+".import"),"original PNG and editor import metadata absent: "+path)
		check(FileAccess.file_exists(path+".remap") and ResourceLoader.exists(path),"native ResourceLoader resolves exported remap")
		var control:Texture2D=ResourceLoader.load(path) as Texture2D
		if not check(control!=null,"control native texture loads from ctex"):continue
		var actual:Texture2D=layer._load_texture(path)
		var loaded:bool=actual!=null
		check(loaded,"production loader accepts remap without PNG/import: "+path)
		if loaded:
			var image:=pixels(actual)
			check(image.get_width()==int(entry.size[0]) and image.get_height()==int(entry.size[1]) and digest(image.get_data())==digest(pixels(control).get_data()),"loaded pixels match native imported resource")
		observations.append({"path":path,"raw":FileAccess.file_exists(path),"editorImport":FileAccess.file_exists(path+".import"),"remap":FileAccess.file_exists(path+".remap"),"productionLoaded":loaded})
	var raw:Texture2D=layer._load_texture("res://probe/raw.png")
	check(raw!=null,"raw PNG fallback works without any import/remap")
	if raw!=null:check(digest(pixels(raw).get_data())==manifest.textures[0].rgbaSha256,"raw fallback preserves original RGBA")
	var imported:Texture2D=layer._load_texture("res://probe/imported.png")
	check(imported!=null,"editor import adapter remains supported")
	var effect:Node3D=layer.new();root.add_child(effect)
	var configured:Dictionary=effect.configure({},null,func(_x:float,_z:float,_t:float)->float:return 0.0)
	check(configured.get("ok",false) and effect.diagnostics().ready,"real atmosphere configures using both canonical remapped sprites")
	effect.dispose();effect.free()
	write_text(argument("--receipt="),JSON.stringify({"assertions":assertions,"failures":failures,"display":DisplayServer.get_name(),"textures":observations,"configured":configured,"scope":manifest.scope},"",false,true))
	print("ATMOSPHERE_REMAP_CHILD checks=",assertions," failures=",failures)
	quit(1 if failures else 0)
func finish()->void:
	print("COMBAT_ATMOSPHERE_PCK_TEST assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
