extends "res://tools/capture-reference-water.gd"
## Same real career commands as the first pass, plus volume/view/lifetime checks.

func _initialize() -> void:
	directory = "res://docs/migration/evidence/reference-implementation"
	super._initialize()

func capture(label: String) -> void:
	await super.capture(label)
	if label == "sailing-turn":
		scene.interface.visible = true
		await super.capture("sailing-controls-ui")
		scene.interface.visible = false
	if label == "real-cannon-splash-peak":
		var water = scene.sea.effects.get_node("WaterSplashes")
		var p: Vector2 = water._splashes[0].origin
		scene.sea.camera.position = Vector3(p.x+14,6,p.y-17)
		scene.sea.camera.look_at(Vector3(p.x,1.0,p.y)); scene.sea.world.get_ocean().update_projection()
		await super.capture("splash-low-angle")
		scene.sea.camera.position = Vector3(p.x+2,35,p.y-1)
		scene.sea.camera.look_at(Vector3(p.x,0,p.y)); scene.sea.world.get_ocean().update_projection()
		await super.capture("splash-overhead")
		splash_camera(p)
	if label == "real-cannon-splash-fading":
		var water = scene.sea.effects.get_node("WaterSplashes")
		var p: Vector2 = water._splashes[0].origin
		await advance(12); splash_camera(p)
		await super.capture("splash-0-7-seconds")
		await advance(135); splash_camera(p)
		await super.capture("splash-expired")
