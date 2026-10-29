extends SceneTree
const Candidate=preload("res://game/research/fixtures/hero_palette_provider.gd")
const Production=preload("res://modules/scene_engine/assets/hero_ship_provider.gd")
const Library=preload("res://modules/scene_engine/assets/asset_library.gd")
var assertions:=0
var failures:=0
func check(value:bool,why:String)->void:
	assertions+=1
	if not value:failures+=1;printerr("FAIL proxy provider: ",why)
func _initialize()->void:run.call_deferred()
func run()->void:
	var library:=Library.new()
	for lod in 3:
		var candidate:Node3D=Candidate.new("art_r6",true,"r8b").instantiate_ship("fuchuan",lod,library)
		check(candidate!=null,"independent R8b candidate loads LOD%d"%lod)
		if candidate==null:continue
		check(candidate.get_meta("source_path","")=="res://assets/models/hero_fuchuan_v3_r8b/fuchuan-lod%d.glb"%lod,"actual candidate path retained")
		check(candidate.get_meta("art_revision",0)==8,"candidate revision is distinct from palette-only R7")
		var baseline:Node3D=Production.new("art_r7c",true).instantiate_ship("fuchuan",lod,library)
		var old_proxy:Mesh=baseline.find_child("deck",true,false).get_meta("target_shadow_geometry")
		var new_proxy:Mesh=candidate.find_child("deck",true,false).get_meta("target_shadow_geometry")
		check(absf(old_proxy.get_aabb().end.y-new_proxy.get_aabb().end.y-.004)<.00001,"runtime reads four-millimetre inner deck top")
		check(absf(old_proxy.get_aabb().position.y-new_proxy.get_aabb().position.y)<.00001,"runtime retains original deck proxy bottom")
		var count:=0
		for mesh:MeshInstance3D in candidate.find_children("*","MeshInstance3D",true,false):
			if mesh.get_meta("target_rigid_shadow_caster",false):
				count+=1;check(mesh.has_meta("target_shadow_geometry"),"candidate retains authored caster input "+str(mesh.name))
		check(count==5,"candidate keeps all five rigid casters")
		baseline.free();candidate.free()
	var rejected:Node3D=Candidate.new("art_r6",true,"r8a").instantiate_ship("fuchuan",0,library)
	check(rejected==null,"failed full export is not exposed as a validated candidate")
	if rejected!=null:rejected.free()
	var current:Node3D=Production.new().instantiate_ship("fuchuan",0,library)
	check(current.get_meta("source_path","").contains("hero_fuchuan_v3_r7c"),"production remains R7c during independent R8 validation")
	current.free();library.dispose()
	print("HERO_PROXY_PROVIDER_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
