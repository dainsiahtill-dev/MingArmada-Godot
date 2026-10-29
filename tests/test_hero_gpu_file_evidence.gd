extends SceneTree
## Exercise the real PNG writer and rehash against isolated user:// data.
## CPU-generated test pixels do not claim any GPU capture.
const Gate=preload("res://tools/research/hero_gpu_evidence_gate.gd")
var assertions:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,detail:String)->void:
	assertions+=1
	if not value:failures+=1;printerr("FAIL: ",detail)

func run()->void:
	var gate=Gate.new()
	check(gate.has_method("save_png"),"capture uses checked native PNG writer")
	check(gate.has_method("file_evidence"),"capture verifies saved bytes before acceptance")
	if gate.has_method("save_png") and gate.has_method("file_evidence"):
		var directory:="user://hero-gpu-file-evidence-%d"%Time.get_ticks_usec()
		check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))==OK,"isolated test directory created")
		var path:=directory.path_join("frame.png")
		var pixels:=Image.create_empty(3,2,false,Image.FORMAT_RGBA8)
		pixels.fill(Color("184251"))
		var result:Dictionary=gate.save_png(pixels,path,"frame",0.0,Vector2i(3,2))
		check(result.ok and result.entry.sha256==FileAccess.get_sha256(path),"PNG write and actual file SHA recorded")
		check(Image.load_from_file(path).get_size()==Vector2i(3,2),"written PNG decodes with real dimensions")
		var original:=FileAccess.get_file_as_bytes(path)
		check(not gate.save_png(pixels,path,"same path",0.0,Vector2i(3,2)).ok and FileAccess.get_file_as_bytes(path)==original,"existing frame is never overwritten")
		check(gate.file_evidence([result.entry]).ok,"unchanged saved frame is accepted")
		check(not gate.file_evidence([result.entry,result.entry]).ok,"duplicate recorded frame path is rejected")
		var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(PackedByteArray([1,2,3]));file.close()
		check(not gate.file_evidence([result.entry]).ok,"changed saved frame is rejected")
		file=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(original);file.close()
		check(gate.file_evidence([result.entry]).ok,"original bytes revalidate")
		var missing:Dictionary=result.entry.duplicate(true);missing.path=directory.path_join("missing.png")
		check(not gate.file_evidence([missing]).ok,"missing saved frame is rejected")
		check(not gate.save_png(pixels,directory.path_join("wrong-size.png"),"wrong",0.0,Vector2i(4,2)).ok,"wrong viewport dimensions are rejected")
	print("HERO_GPU_FILE_EVIDENCE assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
