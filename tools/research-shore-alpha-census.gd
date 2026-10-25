extends SceneTree
## Read actual published shore uniforms in the public sail scene. Headless only.
## No shader, visibility, callback body, sampler, or production source is replaced.
const Main = preload("res://game/scenes/main/main_scene.gd")
const Router = preload("res://game/runtime/game_router.gd")
const Settings = preload("res://game/persistence/user_settings.gd")
const STEP := 1.0 / 60.0
const TICKS := 240
const WATCHED := ["res://tools/research-shore-alpha-census.gd", "res://game/scenes/naval_practice/naval_practice.gd", "res://game/runtime/naval_practice_runtime.gd", "res://game/presentation/world/naval_world_view.gd", "res://modules/scene_engine/world/world_view.gd", "res://modules/scene_engine/terrain/natural_shore_surf.gd", "res://modules/scene_engine/terrain/natural_shore_surf.gdshader", "res://modules/scene_engine/terrain/shore_view_bounds.gd", "res://assets/data/fidelity_island/shore-scene.json"]
var main: Node
var game: Node
var output := ""
var failures: Array[String] = []
var rows: Array = []
var patches: Array = []
var owners: Array = []
var topology: Array = []
var frozen_nodes := 0
var finished := false

class MemorySlot extends RefCounted:
	var writes := 0
	func read_checkpoint() -> Dictionary: return {"ok":false,"reason":"save-not-found"}
	func write_checkpoint(_raw: String) -> Dictionary:
		writes += 1
		return {"ok":false,"reason":"census-write-forbidden"}

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> bool:
	if not ok:
		failures.append(message)
		printerr("FAIL SHORE_ALPHA_CENSUS: ",message)
	return ok

func freeze_callbacks(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	node.set_process_internal(false)
	node.set_physics_process_internal(false)
	frozen_nodes += 1
	for child: Node in node.get_children(): freeze_callbacks(child)

func hashes() -> Dictionary:
	var values: Dictionary = {}
	for path: String in WATCHED: values[path] = FileAccess.get_sha256(path)
	return values

func f32(value: float) -> float:
	return float(PackedFloat32Array([value])[0])

func empty_counts() -> Dictionary:
	return {"patches":0,"zero":0,"strictBelowThreshold":0,"positive":0,"positiveBelowThreshold":0,"atOrAboveThreshold":0,"localVisible":0,"visibleInTree":0,"ownerFrustumMayDraw":0,"frustumAndTreeVisible":0,"zeroFrustumAndTreeVisible":0,"belowFrustumAndTreeVisible":0,"triangles":0,"zeroTriangles":0,"belowThresholdTriangles":0,"frustumTreeTriangles":0,"zeroFrustumTreeTriangles":0,"belowFrustumTreeTriangles":0}

func count_patch(counts: Dictionary, alpha: float, threshold: float, local_visible: bool, tree_visible: bool, owner_visible: bool, triangles: int) -> void:
	var zero := alpha == 0.0
	var below := alpha < threshold
	var observed_visible := owner_visible and tree_visible
	counts.patches += 1
	counts.zero += int(zero)
	counts.strictBelowThreshold += int(below)
	counts.positive += int(alpha > 0.0)
	counts.positiveBelowThreshold += int(alpha > 0.0 and below)
	counts.atOrAboveThreshold += int(not below)
	counts.localVisible += int(local_visible)
	counts.visibleInTree += int(tree_visible)
	counts.ownerFrustumMayDraw += int(owner_visible)
	counts.frustumAndTreeVisible += int(observed_visible)
	counts.zeroFrustumAndTreeVisible += int(zero and observed_visible)
	counts.belowFrustumAndTreeVisible += int(below and observed_visible)
	counts.triangles += triangles
	counts.zeroTriangles += triangles * int(zero)
	counts.belowThresholdTriangles += triangles * int(below)
	counts.frustumTreeTriangles += triangles * int(observed_visible)
	counts.zeroFrustumTreeTriangles += triangles * int(zero and observed_visible)
	counts.belowFrustumTreeTriangles += triangles * int(below and observed_visible)

func discover() -> void:
	var natural: Node3D = game.sea.world.get("_natural_world")
	for shore: Node3D in natural.get("_dynamic_shore"):
		var owner_index := owners.size()
		owners.append(shore)
		var materials: Array = shore.get("_materials")
		var nodes: Array = []
		for child: Node in shore.get_children():
			if child is MeshInstance3D: nodes.append(child)
		check(nodes.size() == materials.size(),"owner nodes match original material order")
		for index: int in materials.size():
			var node: MeshInstance3D = nodes[index]
			var material: ShaderMaterial = materials[index]
			check(node.material_override == material,"actual node material identity")
			var triangles := 0
			for surface: int in node.mesh.get_surface_count():
				triangles += int(node.mesh.surface_get_array_index_len(surface) / 3)
			var threshold: Variant = material.get_shader_parameter("source_alpha_threshold")
			check(threshold is float and is_finite(threshold) and threshold > 0.0,"finite positive actual source threshold")
			patches.append({"owner":owner_index,"node":node,"material":material,"triangles":triangles})
			topology.append({"index":topology.size(),"owner":owner_index,"name":str(node.name),"triangles":triangles,"vertices":node.mesh.surface_get_array_len(0),"surfaces":node.mesh.get_surface_count(),"shader":material.shader.resource_path,"shaderSHA256":FileAccess.get_sha256(material.shader.resource_path),"renderPriority":material.render_priority,"castShadow":node.cast_shadow,"threshold":threshold,"thresholdFloat32":f32(float(threshold))})
	check(owners.size() > 0 and patches.size() > 0,"actual production shore owners and patches exist")

func census(tick: int, accepted: float, source_call: int) -> void:
	var total := empty_counts()
	var owner_rows: Array = []
	var combinations: Dictionary = {}
	var alphas: Array = []
	var visibility_bits := ""
	var material_proof := HashingContext.new()
	material_proof.start(HashingContext.HASH_SHA256)
	for shore: Node3D in owners:
		var view: RefCounted = shore.get("_view_bounds")
		var existing_view: Dictionary = view.diagnostics()
		var staged: Dictionary = shore.get("_staged_materials")
		owner_rows.append({"path":str(shore.get_path()),"counts":empty_counts(),"existingFrustum":existing_view,"acceptedTime":shore.get("_accepted_time"),"evaluatedTime":shore.get("_time"),"submittedTime":shore.get("_submitted_time"),"hasAppliedTime":shore.get("_has_applied_time"),"hasSubmittedTime":shore.get("_has_submitted_time"),"stagedMaterials":staged.size(),"publicationPending":not bool(shore.get("_has_submitted_time")) or shore.get("_accepted_time") != shore.get("_submitted_time") or not staged.is_empty(),"samples":shore.get("_sampled_patches"),"materialWrites":shore.get("_material_writes"),"skippedFrames":shore.get("_skipped_frames")})
	for index: int in patches.size():
		var patch: Dictionary = patches[index]
		var material: ShaderMaterial = patch.material
		var node: MeshInstance3D = patch.node
		var raw_alpha: Variant = material.get_shader_parameter("controller_alpha")
		var raw_threshold: Variant = material.get_shader_parameter("source_alpha_threshold")
		if not check(raw_alpha is float and raw_threshold is float and is_finite(raw_alpha) and is_finite(raw_threshold),"finite published uniforms at patch %d" % index): continue
		var alpha := f32(float(raw_alpha))
		var threshold := f32(float(raw_threshold))
		check(alpha >= 0.0 and alpha <= 0.78,"actual published alpha in production envelope")
		check(threshold == topology[index].thresholdFloat32,"threshold unchanged")
		var local_visible := node.visible
		var tree_visible := node.is_visible_in_tree()
		var owner_visible: bool = owner_rows[patch.owner].existingFrustum.visible
		alphas.append(alpha)
		visibility_bits += "1" if tree_visible else "0"
		count_patch(total,alpha,threshold,local_visible,tree_visible,owner_visible,patch.triangles)
		count_patch(owner_rows[patch.owner].counts,alpha,threshold,local_visible,tree_visible,owner_visible,patch.triangles)
		var key := "%s|priority=%d|shadow=%d|thresholdF32=%.12f|localVisible=%s|treeVisible=%s|ownerFrustum=%s" % [material.shader.resource_path,material.render_priority,node.cast_shadow,threshold,local_visible,tree_visible,owner_visible]
		if not combinations.has(key): combinations[key] = empty_counts()
		count_patch(combinations[key],alpha,threshold,local_visible,tree_visible,owner_visible,patch.triangles)
		material_proof.update(var_to_bytes([raw_alpha,raw_threshold,material.get_shader_parameter("texture_matrix"),material.get_shader_parameter("packet_u_metres"),material.get_shader_parameter("simulation_time"),local_visible,tree_visible]))
	var packet: Dictionary = game.sea.get("_snapshot")
	rows.append({"tick":tick,"acceptedStep":accepted,"nativeTime":packet.get("time"),"sourceCallIndex":source_call,"environmentAcceptedTime":packet.get("environment",{}).get("acceptedTime"),"counts":total,"owners":owner_rows,"shaderCombinations":combinations,"publishedControllerAlphaFloat32ByPatchIndex":alphas,"visibleInTreeBitsByPatchIndex":visibility_bits,"publishedUniformAndVisibilitySHA256":material_proof.finish().hex_encode()})

func run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	if not check(not output.is_empty() and not FileAccess.file_exists(output),"fresh explicit output path"): quit(1); return
	if not check(DisplayServer.get_name() == "headless","headless-only census"): quit(1); return
	create_timer(110.0).timeout.connect(func():
		if not finished:
			printerr("SHORE_ALPHA_CENSUS watchdog expired")
			quit(1))
	root.size = Vector2i(1600,900)
	root.content_scale_size = root.size
	var career := MemorySlot.new()
	var legacy := MemorySlot.new()
	main = Main.new()
	main.router = Router.new({"mingqi_storage":career,"legacy_storage":legacy,"settings_storage":Settings.new("user://verification/shore-alpha-census-%d.json" % OS.get_process_id())})
	root.add_child(main)
	for frame: int in 5: await process_frame
	var sail: Button = main.menu.find_child("sail",true,false)
	if not check(sail != null and not sail.disabled,"actual public sail button"): main.free(); quit(1); return
	sail.pressed.emit()
	for frame: int in 400:
		await process_frame
		if is_instance_valid(main.current_scene) and main.current_scene.get("startup_receipt").get("ok",false): break
	if not check(is_instance_valid(main.current_scene),"actual sail scene initialized"): main.free(); quit(1); return
	game = main.current_scene
	freeze_callbacks(main)
	for reason: String in game.runtime.presentation_pause_reasons(): game.runtime.set_pause(reason,false)
	game._present(0.0)
	check(game.runtime.snapshot().runtime.mode == "sail","actual sail runtime mode")
	var source_before := hashes()
	var initial: Dictionary = game.runtime.snapshot()
	discover()
	var prior_source := int(game.sea.get("_snapshot").get("environment",{}).get("sourceCallIndex",-1))
	census(0,0.0,prior_source)
	var accepted_total := 0.0
	for tick: int in TICKS:
		var accepted: float = game.runtime.advance(STEP)
		accepted_total += accepted
		game._present(accepted)
		var source_call := int(game.sea.get("_snapshot").get("environment",{}).get("sourceCallIndex",-1))
		if source_call != prior_source: census(tick+1,accepted,source_call)
		prior_source = source_call
		await process_frame
	check(accepted_total >= 4.0 - 0.000000001,"at least four accepted seconds at production 1/60")
	check(career.writes == 0 and legacy.writes == 0,"no actual save-slot writes")
	check(source_before == hashes(),"watched production/tool sources unchanged during census")
	var ranges: Dictionary = {}
	for key: String in rows[0].counts:
		var values: Array = []
		for row: Dictionary in rows: values.append(row.counts[key])
		values.sort()
		var sum := 0.0
		for value: int in values: sum += value
		ranges[key] = {"min":values[0],"max":values[-1],"mean":sum/values.size()}
	var proof := {"schema":"ming-armada-shore-alpha-census-v1","recordType":"cpu-contract","scope":"Actual Main menu sail entry, production runtime seed1661, automatic script/internal callbacks frozen after startup; 240 production runtime.advance(1/60) calls and complete _present calls. Read every existing shore patch's published ShaderMaterial uniforms, local/tree visibility, original mesh triangles and existing cached frustum/publication state at every new sourceCallIndex. No visibility/material/shader/source changes, no full shore diagnostics evaluation, no GPU or drawcall/time/FPS claim.","headless":true,"engine":Engine.get_version_info(),"processor":OS.get_processor_name(),"processId":OS.get_process_id(),"seed":1661,"seedEvidence":"naval_practice_runtime.gd::_restart config seed is fixed1661; source hash below","stepSeconds":STEP,"manualAdvanceTicks":TICKS,"acceptedSeconds":accepted_total,"initialNativeTime":initial.naval.time,"finalNativeTime":game.runtime.snapshot().naval.time,"sourceRowsIncludingInitial":rows.size(),"shoreOwners":owners.size(),"patches":patches.size(),"frozenNodes":frozen_nodes,"sourceHashes":source_before,"topology":topology,"rangesAcrossSourceRows":ranges,"rows":rows,"saveWrites":{"career":career.writes,"legacy":legacy.writes},"limitations":["Published ShaderMaterial property values are CPU resource values; float32 normalization models uniform precision, not actual GPU upload verification in headless.","existingFrustum is the production owner's conservative whole-owner main/reflection union result, not per-patch frustum/occlusion nor true visible drawcalls.","Zero/strict-below counts include possibly stale published uniforms on offscreen owners; owner publicationPending and accepted/evaluated/submitted clocks identify this state.","Geometry triangles are original surface index counts; potential skipped triangles are not GPU rasterized primitives.","Four accepted seconds only; no full lifetime, alternate camera, GPU pixels, timing or improvement acceptance."],"failures":failures}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file := FileAccess.open(output,FileAccess.WRITE)
	if not check(file != null,"fresh census output opens"): main.free(); quit(1); return
	file.store_string(JSON.stringify(proof,"\t"))
	file.close()
	finished = true
	main.free()
	print("SHORE_ALPHA_CENSUS ",JSON.stringify({"failures":failures,"output":output,"rows":rows.size(),"patches":patches.size(),"ranges":ranges}))
	quit(0 if failures.is_empty() else 1)
