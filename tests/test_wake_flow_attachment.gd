extends SceneTree
# Frozen source geometry oracle. Ordinary/default hero entry remains covered separately.
const Reference=preload("res://modules/scene_engine/assets/ship_model_provider.gd")
const Ship = preload("res://game/presentation/ships/ship_view.gd")
var assertions := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL wake attachment: ",message)
func run() -> void:
	for kind: String in ["fuchuan","fisherman","merchant","heavy"]:
		var ship := Ship.new();root.add_child(ship)
		check(ship.configure(kind,null,Reference.new()),"actual ship configured: "+kind)
		ship.position = Vector3(30,0,40);ship.rotation.y = .6
		var attachment: Dictionary = ship.source_water_attachment()
		check(attachment.get("flowStern") is Vector3,"actual hull stern distinct from original Dummy_Wake: "+kind)
		if not attachment.get("flowStern") is Vector3: ship.dispose();ship.free();continue
		var profile: Dictionary = attachment.surfaceProfile
		var local: Vector3 = profile.worldToHull * attachment.flowStern
		var first: Dictionary = profile.sections[0]
		var last: Dictionary = profile.sections[-1]
		var local_bow: Vector3 = profile.worldToHull * attachment.bow
		var stern: Dictionary = last if absf(local_bow.z-first.z)<absf(local_bow.z-last.z) else first
		check(absf(local.z-stern.z)<.002,"born at farthest actual waterline end: "+kind)
		check(absf(local.x-(stern.left+stern.right)*.5)<.002,"born on waterline center: "+kind)
		var point: Vector3 = attachment.flowStern
		var old_marker: Vector3 = attachment.trail
		if kind=="fuchuan":check(point.distance_to(old_marker)>5.0,"regression: near-center source marker is not treated as physical stern")
		ship.position.y=2.0;ship.rotation.x=.2;ship.rotation.z=-.15
		var lifted: Dictionary = ship.source_water_attachment()
		check(lifted.flowStern.distance_to(point)<.001,"heave/roll/pitch do not move horizontal birth history: "+kind)
		check(lifted.trail.distance_to(old_marker)<.001,"original yaw-only marker contract retained: "+kind)
		ship.dispose();ship.free()
	print("WAKE_FLOW_ATTACHMENT_TESTS assertions=",assertions," failures=",failures)
	quit(0 if failures==0 else 1)
