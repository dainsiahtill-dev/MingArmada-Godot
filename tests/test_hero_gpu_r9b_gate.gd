extends SceneTree
## Real R9b actor, generated texture, and provenance; headless only.
const Gate=preload("res://tools/research/hero_gpu_evidence_gate.gd")
const Experiment=preload("res://game/research/demos/hero_fuchuan_experiment.gd")
const MANIFEST="res://assets/models/hero_fuchuan_v3_r9b/manifest.json"
const PNG="res://assets/textures/hero_fuchuan_r9/sunfaded-cinnabar-hemp-sail.png"
const PRIOR_PNG="res://assets/textures/hero_fuchuan_r9/cinnabar-hemp-sail.png"
var assertions:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,detail:String)->bool:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: ",detail)
	return ok
func resource_path(value:String)->String:return "res://"+value.replace("\\","/")

func run()->void:
	var gate=Gate.new()
	var manifest:Variant=JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if check(manifest is Dictionary and manifest.asset=="hero-fuchuan-v3-r9b" and manifest.lods.size()==3,"R9b manifest is a real three-LOD candidate"):
		var expected:Array=gate.expected_source_paths("art_r9b")
		var assets:Dictionary=gate.r9_asset_hashes("r9b")
		var watched:Dictionary=gate.watched_source_hashes("art_r9b")
		check(expected.size()==3,"R9b has three expected model sources")
		check(not watched.values().has("MISSING"),"every R9b GPU source dependency exists")
		var all_watched:=true
		for path:String in assets:all_watched=all_watched and watched.get(path,"")==assets[path] and assets[path]!="MISSING"
		check(all_watched,"every candidate and baseline asset is watched")
		check(gate.r9_asset_evidence(assets,"r9b").ok,"current R9b provenance is accepted")
		for path:String in [PNG,PRIOR_PNG,"res://assets/textures/hero_fuchuan_r9/provenance.json","res://assets/textures/hero_fuchuan_r9/provenance-sunfaded.json",MANIFEST]:
			var removed:=assets.duplicate(true);removed.erase(path)
			check(not gate.r9_asset_evidence(removed,"r9b").ok,"missing texture-chain or metadata hash is rejected: "+path)
		var changed:=assets.duplicate(true);changed[PNG]="0".repeat(64)
		check(not gate.r9_asset_evidence(changed,"r9b").ok,"wrong generated PNG hash is rejected")
		check(assets.get(PNG,"")==manifest.pngSha256,"R9b generated sail PNG matches manifest")
		check(assets.get(resource_path(manifest.authorBlend),"")==manifest.authorBlendSha256,"R9b editable blend matches manifest")
		check(assets.get(resource_path(manifest.sourceBlend),"")==manifest.sourceBlendSha256,"R7c authoring baseline matches manifest")
		for entry:Dictionary in manifest.lods:
			check(expected[entry.lod]==resource_path(entry.candidate),"expected R9b LOD%d path"%int(entry.lod))
			check(assets.get(resource_path(entry.candidate),"")==entry.candidateSha256,"R9b LOD%d SHA matches manifest"%int(entry.lod))
			check(assets.get(resource_path(entry.source),"")==entry.sourceSha256,"R7c LOD%d SHA matches manifest"%int(entry.lod))
		var demo=Experiment.new()
		if check(demo.configure({"model":"art_r9b","shadows":"authored","animated":false}).ok,"real R9b research scene configures"):
			root.add_child(demo)
			var actual:Node=demo._ship.get_model()
			if check(is_instance_valid(actual),"actual R9b model loads"):
				for lod in 3:
					var node:Node=demo._ship.get_node_or_null("LOD%d"%lod)
					check(node!=null and node.get_meta("source_path","")==expected[lod],"loaded R9b LOD%d source is correct"%lod)
				demo._rigid.compose({}, {"hero":demo._ship}, -demo._sun.global_basis.z,true,true)
				var casters:Dictionary=gate.caster_evidence(demo,"art_r9b","authored")
				check(casters.ok and casters.casters.size()==5,"all five real R9b authored proxies are selected")
				var mast:=actual.find_child("mast_timber_0",true,false) as MeshInstance3D
				if check(mast!=null,"R9b first mast caster exists"):
					mast.set_meta("target_rigid_shadow_caster",false)
					check(not gate.caster_evidence(demo,"art_r9b","authored").ok,"missing one of five R9b casters is rejected")
					mast.set_meta("target_rigid_shadow_caster",true)
				demo.set_parameter("animated",true)
				for step in [1.0/32.0,0.75,1.0]:
					demo.advance(step)
					check(gate.pose_evidence(demo,"art_r9b",demo.inspection_snapshot().snapshot).ok,"real R9b sail/rudder pose matches snapshot")
				var reference:=Image.new();reference.load_png_from_buffer(FileAccess.get_file_as_bytes(PNG))
				var point:=Vector2i(reference.get_width()/2,reference.get_height()/2)
				for health:float in [100.0,80.0,60.0,30.0]:
					var state:Dictionary=demo.inspection_snapshot().snapshot.duplicate(true)
					state.sail=health
					demo._ship.apply_snapshot(state,{"direction":{"x":1,"y":0},"speed":14},0)
					var count:=0;var matching:=true
					for entry:Dictionary in demo._ship.get("_damage").get("_materials"):
						if not entry.sail or not entry.node.is_visible_in_tree():continue
						var texture:Texture2D=entry.material.get_shader_parameter("original_albedo")
						if texture==null:matching=false;continue
						var pixels:Image=texture.get_image()
						if pixels.is_compressed():pixels.decompress()
						matching=matching and pixels.get_size()==reference.get_size() and pixels.get_pixelv(point).is_equal_approx(reference.get_pixelv(point))
						count+=1
					check(count>=3 and matching,"actual canvas shader retains sunfaded texture at sail health "+str(health))
			demo.dispose();demo.free()
	print("HERO_GPU_R9B_GATE assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
