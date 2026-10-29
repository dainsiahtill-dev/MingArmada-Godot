extends SceneTree
## R11 provenance contract and genuine actor checks; headless, never GPU proof.
const Gate=preload("res://tools/research/hero_gpu_evidence_gate.gd")
var assertions:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,detail:String)->bool:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: ",detail)
	return ok
func run()->void:
	var gate=Gate.new()
	var ready:=check(gate.has_method("r11_asset_hashes") and gate.has_method("r11_asset_evidence"),"R11 provenance guard exists")
	var expected:Array[String]=[]
	for lod in 3:expected.append("res://assets/models/hero_fuchuan_v3_r11/fuchuan-lod%d.glb"%lod)
	check(gate.expected_source_paths("art_r11")==expected,"all R11 LOD source paths are registered")
	if ready:
		var hashes:Dictionary=gate.r11_asset_hashes()
		var watched:Dictionary=gate.watched_source_hashes("art_r11")
		check(not hashes.values().has("MISSING"),"all provenance inputs exist")
		check(gate.r11_asset_evidence(hashes).ok,"real R11 and R9b provenance chain accepted")
		for path:String in hashes:
			check(watched.get(path,"")==hashes[path],"source is watched: "+path)
			var missing:=hashes.duplicate(true);missing.erase(path)
			check(not gate.r11_asset_evidence(missing).ok,"missing dependency rejected: "+path)
		var wrong:=hashes.duplicate(true)
		wrong["res://assets/models/hero_fuchuan_v3_r11/fuchuan-lod0.glb"]="0".repeat(64)
		check(not gate.r11_asset_evidence(wrong).ok,"wrong candidate hash rejected")
	print("HERO_GPU_R11_GATE assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
