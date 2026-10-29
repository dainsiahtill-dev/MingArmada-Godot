extends SceneTree
## Read-only accepted-time atmosphere contracts; real GPU appearance is separate.
const SCRIPT_PATH := "res://game/presentation/combat/combat_atmosphere.gd"
var assertions := 0
var failures := 0
var layer_script: Script
var anchor := {"position": Vector3(4.0, 5.0, 6.0), "time": 10.0, "shipId": "wreck"}

func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		printerr("FAIL COMBAT ATMOSPHERE: ", label)

func _initialize() -> void: run.call_deferred()

func water(_x: float, _z: float, _seconds: float) -> float: return 0.0
func resolve_anchor(id: String) -> Dictionary: return anchor.duplicate(true) if id == "wreck" else {}
func wire(point: Vector3) -> Dictionary: return {"x": point.x, "y": point.y, "z": point.z}
func packet(seconds: float, wind_x: float = 1.0, epoch: String = "battle") -> Dictionary:
	return {"time": seconds, "battleId": epoch, "wind": {"direction": {"x": wind_x, "y": 0.0}, "speed": 8.0}, "ships": [], "projectiles": []}
func event(id: String, kind: String = "fire", seconds: float = 10.0) -> Dictionary:
	return {"id": id, "type": kind, "time": seconds, "shipId": "wreck", "targetId": "target", "position": wire(Vector3(2.0, 5.0, 3.0)), "velocity": wire(Vector3(0.0, 0.0, 80.0)), "damage": {"hull": 8.0, "sail": 1.0, "crew": 0.0}}
func make(options: Dictionary = {}) -> Node3D:
	var layer: Node3D = layer_script.new()
	root.add_child(layer)
	var configured: Dictionary = layer.configure(options, null, water, resolve_anchor)
	check(bool(configured.get("ok", false)), "configure owns ready texture/render resources")
	return layer
func release(layer: Node3D) -> void:
	layer.dispose()
	var data: Dictionary = layer.diagnostics()
	check(data.particles.is_empty() and data.draw_calls == 0 and layer.get_child_count() == 0, "dispose releases every particle and render carrier immediately")
	layer.free()
func particles(layer: Node3D, kind: String) -> Array:
	return layer.diagnostics().particles.filter(func(p: Dictionary) -> bool: return p.kind == kind)
func point(p: Dictionary) -> Vector3: return Vector3(float(p.position[0]), float(p.position[1]), float(p.position[2]))
func by_id(rows: Array, id: String) -> Dictionary:
	for row: Dictionary in rows:
		if row.id == id: return row
	return {}

func clock_and_events() -> void:
	var layer := make()
	var native := packet(10.0)
	var original := native.duplicate(true)
	layer.apply_snapshot(native)
	check(native == original and layer.diagnostics().particles.is_empty(), "peaceful snapshot does not emit or mutate authority")
	var shot := event("shot")
	shot.source_muzzle_position = wire(Vector3(12.0, 7.0, -3.0))
	var receipt := shot.duplicate(true)
	layer.apply_events([shot, shot])
	var born: Dictionary = layer.diagnostics()
	check(shot == receipt and born.seen_events == 1, "deduplicates a real fire without editing its payload")
	check(born.active_smoke > 0 and born.active_flames > 0, "real muzzle produces smoke and brief fire")
	for p: Dictionary in born.particles:
		check(point(p).distance_to(Vector3(12.0, 7.0, -3.0)) < 1.0, "initial muzzle particles use captured drawn muzzle rather than physics root")
	layer.apply_snapshot(native)
	layer.apply_events([shot])
	layer.refresh_anchors()
	check(layer.diagnostics().particles == born.particles, "same accepted time and duplicate receipt freeze particle positions sizes and opacity")
	layer.apply_events([event("future", "fire", 12.0)])
	check(layer.diagnostics().seen_events == 1, "future event is rejected before dedupe so its later accepted delivery remains available")
	layer.apply_snapshot(packet(12.0))
	layer.apply_events([event("future", "fire", 12.0)])
	check(layer.diagnostics().seen_events == 2, "previously future event becomes valid at its accepted time")
	var seen: int = layer.diagnostics().seen_events
	var malformed := event("malformed")
	malformed.position = {"x": NAN, "y": 1.0, "z": 2.0}
	layer.apply_events([malformed, {"id": "missing", "type": "fire", "time": 12.0}, event("ignored", "victory", 12.0)])
	check(layer.diagnostics().seen_events == seen, "malformed positions and non-effect event kinds create no state")
	layer.apply_snapshot(packet(30.0))
	layer.apply_events([shot, event("expired", "fire", 10.0)])
	check(layer.diagnostics().particles.is_empty(), "expired historical receipts cannot resurrect particles")
	layer.apply_snapshot(packet(2.0))
	check(layer.diagnostics().seen_events == 0 and layer.diagnostics().particles.is_empty(), "accepted rewind clears the old timeline")
	layer.apply_events([event("new-shot", "fire", 2.0)])
	layer.apply_snapshot(packet(2.0, 1.0, "next-battle"))
	check(layer.diagnostics().seen_events == 0 and layer.diagnostics().particles.is_empty() and layer.diagnostics().epoch == "next-battle", "new battle clears particles and event identity even at identical time")
	release(layer)

func wind_and_history() -> void:
	var from_east := make()
	var from_west := make()
	var shot := event("same-seed")
	for layer: Node3D in [from_east, from_west]:
		layer.apply_snapshot(packet(10.0, 1.0 if layer == from_east else -1.0))
		layer.apply_events([shot])
		layer.apply_snapshot(packet(11.5, 1.0 if layer == from_east else -1.0))
	var east := particles(from_east, "smoke")
	var west := particles(from_west, "smoke")
	check(not east.is_empty() and east.size() == west.size(), "opposite wind retains the same deterministic plume inventory")
	for p: Dictionary in east:
		var other := by_id(west, p.id)
		check(not other.is_empty() and point(p).x < point(other).x - 1.0 and is_equal_approx(point(p).y, point(other).y), "wind FROM positive X drifts toward negative X while preserving identical vertical motion")
	var before: Array = from_east.diagnostics().particles
	from_east.apply_snapshot(packet(11.5, -1.0))
	check(before == from_east.diagnostics().particles, "changing wind at a paused instant cannot teleport already born world smoke")
	var delayed := make()
	delayed.apply_snapshot(packet(11.5))
	delayed.apply_events([shot])
	check(particles(delayed, "smoke") == east, "delayed event reconstructs the same finite smoke age from actual event birth")
	var hit_layer := make()
	hit_layer.apply_snapshot(packet(10.0))
	hit_layer.apply_events([event("impact", "hit")])
	check(hit_layer.diagnostics().active_smoke > 0 and hit_layer.diagnostics().active_embers > 0 and hit_layer.diagnostics().active_flames == 0, "ordinary hit emits dust and brief embers without inventing live ship fire")
	for layer: Node3D in [from_east, from_west, delayed, hit_layer]: release(layer)

func wreck_attachment() -> void:
	var layer := make()
	anchor = {"position": Vector3(4.0, 5.0, 6.0), "time": 10.0, "shipId": "wreck"}
	layer.apply_snapshot(packet(10.0))
	var destruction := event("destruction", "destruction-explosion")
	destruction.source_effect_position = wire(Vector3(-20.0, 6.0, -30.0))
	layer.apply_events([destruction])
	layer.refresh_anchors()
	check(layer.diagnostics().active_flames > 0, "actual destruction event enables attached wreck flame")
	for p: Dictionary in particles(layer, "smoke"):
		check(point(p).distance_to(Vector3(-20.0, 6.0, -30.0)) < 1.0, "initial wreck smoke uses captured historical destruction point")
	layer.apply_snapshot(packet(10.5))
	anchor.position = Vector3(40.0, 8.0, 60.0); anchor.time = 10.5
	layer.refresh_anchors()
	for p: Dictionary in particles(layer, "flame"):
		check(point(p).distance_to(anchor.position) < 5.0, "flames follow actual current sinking deck anchor")
	var smoke: Array = particles(layer, "smoke")
	anchor.position = Vector3(140.0, 8.0, 160.0)
	layer.refresh_anchors()
	check(smoke == particles(layer, "smoke"), "released smoke does not move with its ship")
	layer.apply_snapshot(packet(10.75))
	layer.refresh_anchors()
	check(layer.diagnostics().active_flames == 0, "stale drawn anchor cannot place ongoing flame at a newer accepted time")
	anchor.time = 10.75; anchor.position = Vector3(140.0, -1.0, 160.0)
	layer.refresh_anchors()
	check(layer.diagnostics().active_flames == 0 and layer.diagnostics().underwater_stopped == 1, "submerged actual deck latches wreck fire off")
	anchor.position.y = 5.0
	layer.refresh_anchors()
	check(layer.diagnostics().active_flames == 0 and layer.diagnostics().active_smoke > 0, "wave recovery never reignites extinguished wreck while released smoke survives")
	for p: Dictionary in layer.diagnostics().particles:
		check(float(p.expires) <= 19.0 and point(p).is_finite(), "whole wreck smoke envelope expires within event plus nine seconds")
	layer.apply_snapshot(packet(19.0))
	check(layer.diagnostics().particles.is_empty(), "wreck resources expire before ten-second terminal tail freezes")
	release(layer)

func capacity_materials_and_disable() -> void:
	var layer := make({"quality": "low"})
	layer.apply_snapshot(packet(10.0))
	var shots: Array = []
	for index in 80: shots.append(event("barrage-%d" % index))
	layer.apply_events(shots)
	var state: Dictionary = layer.diagnostics()
	check(state.capacity == 192 and state.particles.size() <= 192 and state.particles.size() > 0, "low quality enforces a real bounded sprite capacity under barrage")
	check(state.draw_calls > 0 and state.draw_calls <= 3, "barrage shares at most three render batches")
	var carriers := 0
	for child: Node in layer.get_children():
		if not child is MultiMeshInstance3D: continue
		carriers += 1
		var material: StandardMaterial3D = child.material_override
		check(child.multimesh != null and child.multimesh.mesh is QuadMesh and child.multimesh.use_colors, "sprites are actual colored quad MultiMeshes")
		check(material != null and material.albedo_texture != null and material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "render carriers use actual alpha texture materials")
		check(material.billboard_mode == BaseMaterial3D.BILLBOARD_ENABLED and material.billboard_keep_scale, "camera-facing particles retain their authored size")
		check(not material.no_depth_test and material.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED and child.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "smoke tests opaque depth without writing transparent depth or casting quad shadows")
	check(carriers > 0 and carriers <= 3, "bounded rendering uses actual batch nodes")
	layer.configure({"enabled": false}, null, water, resolve_anchor)
	layer.apply_snapshot(packet(10.0))
	layer.apply_events(shots)
	state = layer.diagnostics()
	check(not state.enabled and state.particles.is_empty() and state.draw_calls == 0, "disabled baseline owns no live atmosphere or draw calls")
	release(layer)

func run() -> void:
	check(FileAccess.file_exists(SCRIPT_PATH), "independent combat atmosphere implementation exists")
	if FileAccess.file_exists(SCRIPT_PATH):
		layer_script = load(SCRIPT_PATH)
		if layer_script != null:
			clock_and_events()
			wind_and_history()
			wreck_attachment()
			capacity_materials_and_disable()
	print("COMBAT_ATMOSPHERE_TESTS assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures else 0)
