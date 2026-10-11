extends Node3D
## Presentation only: source projectiles and deduplicated fire/hit/splash events.
var _balls: Dictionary = {}
var _puffs: Array = []
var _seen: Dictionary = {}
var _velocities: Dictionary = {}
var _time := 0.0
var _ball_material: StandardMaterial3D
func _ready() -> void:
	_ball_material = StandardMaterial3D.new(); _ball_material.albedo_color = Color("302e26")
static func _vector(value: Dictionary) -> Vector3: return Vector3(value.get("x",0),value.get("y",0),value.get("z",0))
func observe_projectiles(native: Dictionary) -> void:
	for projectile: Dictionary in native.get("projectiles",[]): _velocities[projectile.id] = {"velocity":projectile.velocity.duplicate(),"time":native.time}
func presentation_events(events: Array) -> Array:
	var result := events.duplicate(true)
	for event: Dictionary in result:
		if event.get("type") == "fire": _velocities[event.projectileId] = {"velocity":event.velocity.duplicate(),"time":event.time}
		if event.get("type") == "hit" and _velocities.has(event.get("projectileId")):
			var observed: Dictionary = _velocities[event.projectileId]; event.velocity = observed.velocity.duplicate()
			event.velocity.y -= 9.81*maxf(0,event.time-observed.time)
	return result
func apply_snapshot(native: Dictionary,consumed: float) -> void:
	_time = native.time
	var present: Array = []
	for projectile: Dictionary in native.get("projectiles",[]):
		present.append(projectile.id)
		if not _balls.has(projectile.id):
			var ball := MeshInstance3D.new(); var shape := SphereMesh.new(); shape.radius = 0.18; shape.height = 0.36
			ball.mesh = shape; ball.material_override = _ball_material; add_child(ball); _balls[projectile.id] = ball
		_balls[projectile.id].position = _vector(projectile.position)
	for id in _balls.keys():
		if not id in present: _balls[id].queue_free(); _balls.erase(id)
	for index in range(_puffs.size()-1,-1,-1):
		var puff: Dictionary = _puffs[index]; var age: float = _time-puff.time
		if age >= puff.duration: puff.node.queue_free(); _puffs.remove_at(index); continue
		puff.node.position = puff.origin+puff.velocity*age
		puff.node.scale = Vector3.ONE*(puff.size+age*puff.growth)
		puff.material.albedo_color.a = (1-age/puff.duration)*puff.alpha
	for id in _velocities.keys():
		if _time-_velocities[id].time > 10: _velocities.erase(id)
func _puff(position: Vector3,color: Color,size: float,duration: float,velocity: Vector3,growth: float) -> void:
	if _puffs.size() >= 160: return
	var mesh := MeshInstance3D.new(); var sphere := SphereMesh.new(); sphere.radius = 0.5; sphere.height = 1
	var material := StandardMaterial3D.new(); material.albedo_color = color; material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.mesh = sphere; mesh.material_override = material; mesh.position = position; mesh.scale = Vector3.ONE*size; add_child(mesh)
	_puffs.append({"node":mesh,"material":material,"origin":position,"velocity":velocity,"size":size,"growth":growth,"time":_time,"duration":duration,"alpha":color.a})
func apply_events(events: Array) -> void:
	for event: Dictionary in events:
		if _seen.has(event.id): continue
		_seen[event.id] = true
		var point := _vector(event.get("position",{}))
		match event.type:
			"fire":
				var velocity := _vector(event.velocity).normalized()
				_puff(point,Color(1,0.75,0.27,0.95),1.1,0.12,velocity*3,2)
				for i in 6: _puff(point-velocity*i*0.4,Color(0.76,0.74,0.67,0.5),1.0+i*0.3,2.5,Vector3(-0.8,0.7,0.3),1.3)
			"hit":
				for i in 6: _puff(point,Color(0.55,0.35,0.15,0.95),0.12,0.9,Vector3(sin(i*2.1)*3,1.5+i*0.3,cos(i*2.1)*3),0.1)
			"splash":
				for i in 7: _puff(point,Color(0.8,0.97,1,0.7),0.65,0.8,Vector3(sin(i*0.9)*1.4,1.8,cos(i*0.9)*1.4),0.8)
	while _seen.size() > 512: _seen.erase(_seen.keys()[0])
func diagnostics() -> Dictionary: return {"projectiles":_balls.size(),"puffs":_puffs.size(),"events":_seen.size()}
