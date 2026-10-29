extends SceneTree
## Real R9 model and texture-binding checks in headless mode; no GPU claim.
const Gate=preload("res://tools/research/hero_gpu_evidence_gate.gd")
const Experiment=preload("res://game/research/demos/hero_fuchuan_experiment.gd")
const MANIFEST="res://assets/models/hero_fuchuan_v3_r9/manifest.json"
const PNG="res://assets/textures/hero_fuchuan_r9/cinnabar-hemp-sail.png"
var assertions:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,detail:String)->bool:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: ",detail)
	return ok
func resource_path(value:String)->String:
	return "res://"+value.replace("\\","/")

func run()->void:
	var gate=Gate.new()
	var methods:=check(gate.has_method("expected_source_paths"),"R9 expected source paths are exposed to the actual verifier")
	methods=check(gate.has_method("r9_asset_hashes"),"R9 full authoring and runtime dependencies are hashed") and methods
	methods=check(gate.has_method("r9_asset_evidence"),"R9 provenance is checked rather than merely recorded") and methods
	methods=check(gate.has_method("watched_source_hashes"),"the GPU verifier records the full R9 asset and shader dependency set") and methods
	if methods:
		var manifest:Variant=JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		if check(manifest is Dictionary and manifest.asset=="hero-fuchuan-v3-r9" and manifest.lods.size()==3,"R9 manifest is a real three-LOD candidate"):
			var expected:Array=gate.expected_source_paths("art_r9")
			var assets:Dictionary=gate.r9_asset_hashes()
			var watched:Dictionary=gate.watched_source_hashes("art_r9")
			check(not watched.values().has("MISSING"),"every declared R9 GPU source dependency exists")
			var all_watched:=true
			for path:String in assets:all_watched=all_watched and watched.get(path,"")==assets[path] and assets[path]!="MISSING"
			check(all_watched,"every R9 candidate and baseline asset is in the actual GPU source guard")
			for path:String in ["res://game/presentation/ships/ship_damage.gdshader","res://game/presentation/ships/ship_damage_alpha.gdshader","res://game/presentation/ships/ship_damage_surface.gdshaderinc","res://assets/textures/pirates_damage_reference/ship_sail_damage020.dds.png","res://assets/textures/pirates_damage_reference/ship_sail_damage040.dds.png","res://assets/textures/pirates_damage_reference/ship_sail_damage060.dds.png"]:
				check(watched.get(path,"")==FileAccess.get_sha256(path),"actual damage shader/texture is guarded: "+path)
			check(gate.r9_asset_evidence(assets).ok,"current R9 assets agree with recorded provenance")
			var changed:=assets.duplicate(true);changed[PNG]="0".repeat(64)
			check(not gate.r9_asset_evidence(changed).ok,"incorrect generated sail hash is rejected")
			changed=assets.duplicate(true);changed.erase(resource_path(manifest.sourceBlend))
			check(not gate.r9_asset_evidence(changed).ok,"missing original Blender baseline is rejected")
			changed=assets.duplicate(true);changed.erase("res://assets/textures/hero_fuchuan_r9/provenance.json")
			check(not gate.r9_asset_evidence(changed).ok,"missing provenance file hash is rejected")
			changed=assets.duplicate(true);changed.erase(MANIFEST)
			check(not gate.r9_asset_evidence(changed).ok,"missing model manifest hash is rejected")
			check(expected.size()==3,"R9 has three expected model sources")
			check(assets.get(PNG,"")==manifest.pngSha256,"generated sail PNG matches manifest")
			check(assets.get(resource_path(manifest.authorBlend),"")==manifest.authorBlendSha256,"editable R9 blend matches manifest")
			check(assets.get(resource_path(manifest.sourceBlend),"")==manifest.sourceBlendSha256,"R7c authoring baseline matches manifest")
			for item:Dictionary in manifest.lods:
				check(expected[item.lod]==resource_path(item.candidate),"expected actual R9 LOD%d path"%int(item.lod))
				check(assets.get(resource_path(item.candidate),"")==item.candidateSha256,"R9 LOD%d SHA matches manifest"%int(item.lod))
				check(assets.get(resource_path(item.source),"")==item.sourceSha256,"R7c baseline LOD%d SHA matches manifest"%int(item.lod))
			check(assets.has("res://assets/textures/hero_fuchuan_r9/provenance.json") and assets.has(MANIFEST),"texture provenance and model manifest watched")
			var demo=Experiment.new()
			var setup:Dictionary=demo.configure({"model":"art_r9","shadows":"authored","animated":false})
			if check(setup.ok,"actual R9 experiment configures"):
				root.add_child(demo)
				var actual:Node=demo._ship.get_model()
				if check(is_instance_valid(actual),"R9 model loads"):
					for lod in 3:
						var node:Node=demo._ship.get_node_or_null("LOD%d"%lod)
						check(node!=null and node.get_meta("source_path","")==expected[lod],"loaded R9 LOD%d uses declared source"%lod)
					demo._rigid.compose({}, {"hero":demo._ship}, -demo._sun.global_basis.z,true,true)
					var caster:Dictionary=gate.caster_evidence(demo,"art_r9","authored")
					check(caster.ok and caster.casters.size()==5,"all five R9 authored proxy identities selected")
					var mast:=actual.find_child("mast_timber_0",true,false) as MeshInstance3D
					if check(mast!=null,"R9 has first mast caster"):
						mast.set_meta("target_rigid_shadow_caster",false)
						check(not gate.caster_evidence(demo,"art_r9","authored").ok,"missing any one of five R9 casters is rejected")
						mast.set_meta("target_rigid_shadow_caster",true)
					demo.set_parameter("animated",true)
					for step in [1.0/32.0,0.75,1.0]:
						demo.advance(step)
						check(gate.pose_evidence(demo,"art_r9",demo.inspection_snapshot().snapshot).ok,"actual R9 furl and rudder follow snapshot at "+str(demo.inspection_snapshot().time))
					var reference:=Image.new();reference.load_png_from_buffer(FileAccess.get_file_as_bytes(PNG))
					var point:=Vector2i(reference.get_width()/2,reference.get_height()/2)
					for health:float in [100.0,80.0,60.0,30.0]:
						var state:Dictionary=demo.inspection_snapshot().snapshot.duplicate(true)
						state.sail=health
						demo._ship.apply_snapshot(state,{"direction":{"x":1,"y":0},"speed":14},0)
						var count:=0;var matching:=true
						for entry:Dictionary in demo._ship.get("_damage").get("_materials"):
							if not entry.sail or not entry.node.is_visible_in_tree():continue
							var tex:Texture2D=entry.material.get_shader_parameter("original_albedo")
							if tex==null:matching=false;continue
							var image:Image=tex.get_image()
							if image.is_compressed():image.decompress()
							matching=matching and image.get_size()==reference.get_size() and image.get_pixelv(point).is_equal_approx(reference.get_pixelv(point))
							count+=1
						check(count>=3 and matching,"actual canvas shader retains R9 image at sail health "+str(health))
				demo.dispose();demo.free()
	print("HERO_GPU_R9_GATE assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
