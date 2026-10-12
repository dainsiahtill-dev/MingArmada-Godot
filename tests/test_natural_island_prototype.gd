extends SceneTree
var failures:=0
var assertions:=0
func check(ok: bool,message: String) -> void:
	assertions+=1
	if not ok: failures+=1; printerr("FAIL: ",message)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var path:="res://game/scenes/natural_island/natural_island_prototype.gd"
	check(FileAccess.file_exists(path),"new independent natural-island visual baseline exists")
	if failures: _finish(); return
	var scene: Control=load(path).new(); root.add_child(scene)
	await process_frame
	check(scene.ready_receipt.get("ok",false),"native prototype composes the actual terrain and retained sea")
	if not scene.ready_receipt.get("ok",false): scene.free(); _finish(); return
	scene.paused=true
	check(scene.ocean.material_override.get_shader_parameter("wave_count")==5,"actual old five-wave sea is retained")
	check(scene.field.sample_triangle_height(-300,-300)<-8,"open water stays natural deep water")
	check(scene.inspect().artificial_channels==false and scene.inspect().ports==0,"clean baseline has no artificial harbor waterway or old port adaptations")
	var id: int=scene.terrain.get_mesh().get_instance_id()
	var anchors: Array=scene.trees.diagnostics().anchors
	check(not anchors.is_empty(),"actual imported 3D trees cover the new landform")
	var ground: RefCounted=scene.field
	check(absf(ground.sample_triangle_height(37,18)-scene.terrain.sample_height(37,18))<0.0001,"numerical height authority and rendered triangles agree")
	scene.orbit.yaw+=0.7; scene.seconds=14.0; scene._render()
	check(scene.terrain.get_mesh().get_instance_id()==id and scene.trees.diagnostics().anchors==anchors,"camera/time changes do not regenerate terrain or forest")
	check(scene.ocean.material_override.get_shader_parameter("u_time")==14.0,"water observes the scene clock")
	scene.dispose()
	check(scene.stage.get_child_count()==0,"all prototype 3D objects and reflection target are released")
	scene.free(); _finish()
func _finish() -> void:
	print("NATURAL_ISLAND_PROTOTYPE_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
