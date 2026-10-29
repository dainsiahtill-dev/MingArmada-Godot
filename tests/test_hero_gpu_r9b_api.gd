extends SceneTree
## Lightweight acceptance-contract RED/GREEN; no model or GPU is loaded.
const Gate=preload("res://tools/research/hero_gpu_evidence_gate.gd")
func _initialize()->void:
	var paths:Array[String]=Gate.new().expected_source_paths("art_r9b")
	var expected:Array[String]=[]
	for lod in 3:expected.append("res://assets/models/hero_fuchuan_v3_r9b/fuchuan-lod%d.glb"%lod)
	var ok:=paths==expected
	if not ok:printerr("FAIL: R9b verifier must resolve the three actual R9b LOD paths")
	print("HERO_GPU_R9B_API assertions=1 failures=",0 if ok else 1)
	quit(0 if ok else 1)
