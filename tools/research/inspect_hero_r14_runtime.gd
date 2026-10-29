extends SceneTree
const Library=preload("res://modules/scene_engine/assets/asset_library.gd")
func _initialize():run.call_deferred()
func run():
	var lib=Library.new()
	var model=lib.instantiate_model("res://assets/models/hero_fuchuan_v3_r14/fuchuan-lod0.glb")
	for node in model.find_children("*","Node3D",true,false):
		if String(node.name).begins_with("cargo_hold"):
			print("COAMING_IMPORT ",node.name," class=",node.get_class()," childCount=",node.get_child_count()," meta=",node.get_meta_list())
	model.free();lib.dispose();quit()
