extends SceneTree
## Actual destruction events must show textured smoke, not opaque sphere clouds.
const Effects=preload("res://game/presentation/combat/combat_effects.gd")
var assertions:=0
var failures:=0
func check(ok: bool, detail: String) -> void:
	assertions+=1
	if not ok: failures+=1; printerr("FAIL: ",detail)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var effects:=Effects.new(); root.add_child(effects)
	effects.apply_snapshot({"time":10.06,"projectiles":[]},0.0)
	var event: Dictionary={"id":"destruction","type":"destruction-explosion","time":10.0,"position":{"x":3.0,"y":2.0,"z":4.0}}
	var immutable:=event.duplicate(true)
	effects.apply_events([event,event])
	check(effects.diagnostics().puffs==9,"one actual destruction emits one finite flash and eight smoke layers without duplicates")
	var alphas: Array=[]
	var poses: Array[Transform3D]=[]
	for puff: Dictionary in effects.get("_puffs"):
		var mesh: MeshInstance3D=puff.node
		var material: StandardMaterial3D=puff.material
		check(mesh.mesh is QuadMesh,"destruction smoke and flash use soft textured surfaces rather than solid spheres")
		check(material.albedo_texture!=null and material.albedo_texture.get_image().has_mipmaps(),"destruction texture retains original DDS mip chain")
		check(material.billboard_mode==BaseMaterial3D.BILLBOARD_ENABLED and material.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA,"destruction sprites face the active camera with fractional coverage")
		check(material.billboard_keep_scale,"textured destruction smoke and flash retain their accepted-size scale when billboarding")
		check(not material.no_depth_test and material.depth_draw_mode==BaseMaterial3D.DEPTH_DRAW_DISABLED,"textured destruction retains scene depth testing without writing transparent quad depth")
		check(mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"translucent smoke does not cast a solid quad shadow")
		check(material.shading_mode==BaseMaterial3D.SHADING_MODE_UNSHADED,"smoke coverage stays readable instead of depending on billboard face lighting")
		alphas.append(material.albedo_color.a)
		poses.append(mesh.transform)
	# Hand-derived sizes at the actual 0.06-second event age. The billboard
	# must preserve these transforms instead of drawing every layer at unit size.
	check(effects.get("_puffs")[0].node.scale.is_equal_approx(Vector3.ONE*3.24),"new flash retains its initial size plus six hundredths of accepted growth")
	check(effects.get("_puffs")[1].node.scale.is_equal_approx(Vector3.ONE*2.875),"new first smoke reconstructs its size at the accepted event age")
	check(effects.get("_puffs")[8].node.scale.is_equal_approx(Vector3.ONE*4.975),"new last smoke retains its larger initial size at the accepted birth age")
	check(event==immutable,"visual enhancement preserves destruction authority payload")
	effects.apply_snapshot({"time":10.06,"projectiles":[]},4.0)
	for index in alphas.size():
		check(is_equal_approx(effects.get("_puffs")[index].material.albedo_color.a,alphas[index]),"pause freezes smoke opacity independent of wall delta")
		check(effects.get("_puffs")[index].node.transform.is_equal_approx(poses[index]),"same accepted time freezes actual flash/smoke position and size despite wall delta")
	effects.apply_snapshot({"time":10.25,"projectiles":[]},0.0)
	check(effects.diagnostics().puffs==8,"short explosion flash expires while smoke remains")
	check(effects.get("_puffs")[0].material.albedo_color.a<alphas[1],"remaining textured smoke fades by actual event age")
	check(effects.get("_puffs")[0].node.scale.is_equal_approx(Vector3.ONE*3.1125),"next accepted snapshot grows the first real smoke to its quarter-second size")
	check(effects.get("_puffs")[7].node.scale.is_equal_approx(Vector3.ONE*5.2125),"next accepted snapshot grows the last real smoke from its original larger size")
	effects.apply_snapshot({"time":14.0,"projectiles":[]},0.0)
	check(effects.diagnostics().puffs==0,"all destruction smoke releases after its finite event lifetime")
	effects.dispose(); effects.free()
	print("COMBAT_PARTICLE_VISUAL_TESTS assertions=%d failures=%d"%[assertions,failures])
	quit(1 if failures else 0)
