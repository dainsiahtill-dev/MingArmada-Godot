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
	for puff: Dictionary in effects.get("_puffs"):
		var mesh: MeshInstance3D=puff.node
		var material: StandardMaterial3D=puff.material
		check(mesh.mesh is QuadMesh,"destruction smoke and flash use soft textured surfaces rather than solid spheres")
		check(material.albedo_texture!=null and material.albedo_texture.get_image().has_mipmaps(),"destruction texture retains original DDS mip chain")
		check(material.billboard_mode==BaseMaterial3D.BILLBOARD_ENABLED and material.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA,"destruction sprites face the active camera with fractional coverage")
		check(mesh.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"translucent smoke does not cast a solid quad shadow")
		alphas.append(material.albedo_color.a)
	check(event==immutable,"visual enhancement preserves destruction authority payload")
	effects.apply_snapshot({"time":10.06,"projectiles":[]},4.0)
	for index in alphas.size(): check(is_equal_approx(effects.get("_puffs")[index].material.albedo_color.a,alphas[index]),"pause freezes smoke opacity independent of wall delta")
	effects.apply_snapshot({"time":10.25,"projectiles":[]},0.0)
	check(effects.diagnostics().puffs==8,"short explosion flash expires while smoke remains")
	check(effects.get("_puffs")[0].material.albedo_color.a<alphas[1],"remaining textured smoke fades by actual event age")
	effects.apply_snapshot({"time":14.0,"projectiles":[]},0.0)
	check(effects.diagnostics().puffs==0,"all destruction smoke releases after its finite event lifetime")
	effects.dispose(); effects.free()
	print("COMBAT_PARTICLE_VISUAL_TESTS assertions=%d failures=%d"%[assertions,failures])
	quit(1 if failures else 0)
