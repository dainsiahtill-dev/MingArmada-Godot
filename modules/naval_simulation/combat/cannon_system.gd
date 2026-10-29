extends RefCounted
const Types = preload("res://modules/contracts/physics_types.gd")
const Sweep = preload("res://modules/naval_simulation/combat/projectiles.gd")
const GRAVITY := 9.81
const BALLISTICS = {
	"solid": {"speed": 65.0, "range": 250.0, "angle": 0.25, "ttl": 8.0, "damage": {"hull": 8.0, "sail": 1.0, "crew": 1.0}},
	"chain": {"speed": 55.0, "range": 190.0, "angle": 0.23, "ttl": 7.0, "damage": {"hull": 1.5, "sail": 12.0, "crew": 1.0}},
	"grape": {"speed": 42.0, "range": 80.0, "angle": 0.1, "ttl": 4.0, "damage": {"hull": 1.0, "sail": 1.0, "crew": 12.0}},
}
const ARC = 25.0 * PI / 180.0
const GRAPE_SPREAD := [[0.0, 0.0], [-0.036, -0.018], [-0.018, 0.018], [0.018, 0.018], [0.036, -0.018]]

static func reload_seconds(ship: Dictionary) -> float:
	var nominal: float = 7.0 * (1.0 + (1.0 - clampf(ship.crew / ship.maxCrew, 0.0, 1.0)) * 1.5) * ship.stats.reloadMultiplier
	# Extreme equipment bonuses still leave 0.35s after the last gun. This
	# prevents queued overlapping salvos without changing the saved cooldown.
	return maxf(nominal, (ship.cannonsPerSide - 1) * salvo_interval_ticks(ship) / 60.0 + 0.35)

static func salvo_interval_ticks(ship: Dictionary) -> int:
	# 3/4-gun batteries roll for 0.27/0.40s; an eight-gun heavy battery
	# takes 1.05s. Crew losses slow the same finite salvo, not its gun count.
	var healthy: int = 9 if ship.cannonsPerSide > 4 else 8
	return int(ceil(healthy * (1.0 + (1.0 - clampf(ship.crew / ship.maxCrew, 0.0, 1.0)))))

static func launch_solution(ship: Dictionary, side: String, ammo: String, cannon: int, target: Dictionary = {}) -> Dictionary:
	var ballistic: Dictionary = BALLISTICS[ammo]
	var position := muzzle(ship.visual, Types.ship_spec(ship.kind), side, cannon)
	var base_bearing: float = ship.visual.heading + (PI / 2.0 if side == "starboard" else -PI / 2.0)
	var bearing := base_bearing
	var elevation: float = ballistic.angle
	if not target.is_empty():
		var v: Dictionary = target.visual
		var x_distance: float = v.position.x - position.x
		var z_distance: float = v.position.z - position.z
		var travel: float = sqrt(x_distance*x_distance+z_distance*z_distance) / ballistic.speed
		var dx: float = v.position.x + v.velocity.x * travel - position.x
		var dz: float = v.position.z + v.velocity.z * travel - position.z
		bearing += clampf(atan2(sin(atan2(dz,dx)-base_bearing),cos(atan2(dz,dx)-base_bearing)), -ARC, ARC)
		var distance := maxf(1.0, sqrt(dx*dx+dz*dz))
		var aim_y: float = v.position.y + (11.0 if ammo == "chain" else Types.ship_spec(target.kind).freeboard + 0.5)
		var speed2: float = ballistic.speed * ballistic.speed
		var discriminant: float = speed2 * speed2 - GRAVITY * (GRAVITY * distance * distance + 2.0 * (aim_y - position.y) * speed2)
		if discriminant >= 0.0: elevation = atan((speed2 - sqrt(discriminant)) / (GRAVITY * distance))
	var velocities: Array = []
	for angles: Array in GRAPE_SPREAD if ammo == "grape" else [[0.0,0.0]]:
		var horizontal: float = ballistic.speed * cos(elevation + angles[1])
		velocities.append({"x":cos(bearing+angles[0])*horizontal,"y":ballistic.speed*sin(elevation+angles[1]),"z":sin(bearing+angles[0])*horizontal})
	return {"position":position,"velocities":velocities,"ttl":ballistic.ttl}

static func _flight(position: Dictionary, velocity: Dictionary, seconds: float) -> Dictionary:
	return {"x":position.x+velocity.x*seconds,"y":position.y+velocity.y*seconds-GRAVITY*seconds*seconds/2.0,"z":position.z+velocity.z*seconds}

static func _predicted(visual: Dictionary, seconds: float) -> Dictionary:
	return {"heading":visual.heading,"position":{"x":visual.position.x+visual.velocity.x*seconds,"y":visual.position.y,"z":visual.position.z+visual.velocity.z*seconds}}

static func corridor_clear(solution: Dictionary, protected_ships: Array) -> bool:
	# Read-only prediction of the actual launch velocities, with the same moving
	# box sweep as live collision. 0.1s chords have <0.013m gravity sag; a 0.2m
	# safety margin covers this error. No position, hit or clock is written here.
	for ship: Dictionary in protected_ships:
		if ship.hull <= 0: continue
		var spec := Types.ship_spec(ship.kind)
		var boxes := [{"length":spec.length+0.4,"width":spec.width+0.4,"bottom":-spec.draft-0.2,"top":spec.freeboard+2.2},
			{"length":spec.length*0.75+0.4,"width":spec.width*0.85+0.4,"bottom":spec.freeboard+1.8,"top":spec.length*0.65+0.2}]
		for velocity: Dictionary in solution.velocities:
			# Reject distant lanes analytically before the bounded 3D sweep. This
			# also keeps per-frame HUD advice cheap for clear opposite-side arcs.
			var rx: float = solution.position.x - ship.visual.position.x
			var rz: float = solution.position.z - ship.visual.position.z
			var vx: float = velocity.x - ship.visual.velocity.x
			var vz: float = velocity.z - ship.visual.velocity.z
			var speed2: float = vx*vx+vz*vz
			var nearest := clampf(-(rx*vx+rz*vz)/speed2,0.0,solution.ttl) if speed2 > 1.0e-12 else 0.0
			var radius: float = sqrt(spec.length*spec.length+spec.width*spec.width)/2.0+0.3
			if pow(rx+vx*nearest,2)+pow(rz+vz*nearest,2) > radius*radius: continue
			for index in int(ceil(solution.ttl * 10.0)):
				var t0 := index * 0.1
				var t1 := minf(solution.ttl, t0 + 0.1)
				var a := _flight(solution.position,velocity,t0)
				var b := _flight(solution.position,velocity,t1)
				for box: Dictionary in boxes:
					if Sweep.sweep_moving_box(a,b,_predicted(ship.visual,t0),_predicted(ship.visual,t1),box) != null: return false
	return true

static func _policy_enemy(a: Dictionary, b: Dictionary, policy: Dictionary) -> bool:
	# Same ordered classification as Encounter._enemy: captured ships are
	# protected before any explicit hostile target list overrides team labels.
	if a.id == b.id: return false
	if a.id in policy.get("capturedShipIds",[]) or b.id in policy.get("capturedShipIds",[]): return false
	if policy.get("hostileTargets",{}).has(a.id): return b.id in policy.hostileTargets[a.id]
	# Display projections can omit allegiance. Until policy establishes it,
	# treat that ship as protected, as a neutral canonical ship would be.
	var a_team: String = a.get("team","neutral")
	var b_team: String = b.get("team","neutral")
	return a_team != "neutral" and b_team != "neutral" and a_team != b_team

static func _advice_geometry_known(ship: Dictionary) -> bool:
	if Types.ship_spec(ship.get("kind","")).is_empty(): return false
	var visual: Dictionary = ship.get("visual",{})
	var position: Dictionary = visual.get("position",{})
	var velocity: Dictionary = visual.get("velocity",{})
	return Types.finite_number(visual.get("heading")) and ["x","y","z"].all(func(axis): return Types.finite_number(position.get(axis))) and ["x","z"].all(func(axis): return Types.finite_number(velocity.get(axis)))

static func broadside_status(native: Dictionary, ship_id: String, side: String, policy: Dictionary = {}) -> Dictionary:
	var ships: Array = native.get("ships",[])
	var matches := ships.filter(func(s): return s.id == ship_id)
	if matches.is_empty() or side not in ["port","starboard"]: return {"phase":"unavailable","label":"炮况不可用"}
	var ship: Dictionary = matches[0]
	var ammo: String = ship.get("ammoType","solid")
	var result := {"phase":"ready","label":"可齐射","rangeMeters":BALLISTICS[ammo].range,"arcDegrees":25.0,"targetId":"","reloadSeconds":ship.get("cooldownSeconds",{}).get(side,0.0)}
	if ship.get("cannonsPerSide",0) <= 0: result.phase="no-guns"; result.label="未配舰炮"; return result
	if ship.get("hull",0.0) <= 0 or ship.get("availableCrew",ship.get("crew",0.0)) <= 0: result.phase="not-operational"; result.label="炮组无法作战"; return result
	if result.reloadSeconds > 0.0: result.phase="reloading"; result.label="装填 %.1f秒" % result.reloadSeconds; return result
	if ship.get("ammo",{}).get(ammo,0) <= 0: result.phase="no-ammo"; result.label="弹药耗尽"; return result
	# A lean UI projection can show guns/reload/ammunition without physical
	# kind or height. It cannot verify a ballistic corridor; do not invent hull
	# geometry or claim a ready target. The live command still checks authority.
	if ships.any(func(s): return s.get("hull",0.0)>0.0 and not _advice_geometry_known(s)):
		result.phase="no-target"; result.label="射界待确认"; return result
	var bearing: float = ship.visual.heading + (PI/2.0 if side == "starboard" else -PI/2.0)
	var enemies := ships.filter(func(s): return s.hull > 0.0 and _policy_enemy(ship,s,policy))
	var in_arc: Array = []
	for target: Dictionary in enemies:
		var dx: float = target.visual.position.x - ship.visual.position.x
		var dz: float = target.visual.position.z - ship.visual.position.z
		if absf(atan2(sin(atan2(dz,dx)-bearing),cos(atan2(dz,dx)-bearing))) <= ARC: in_arc.append(target)
	in_arc.sort_custom(func(a,b): return Vector2(a.visual.position.x-ship.visual.position.x,a.visual.position.z-ship.visual.position.z).length_squared() < Vector2(b.visual.position.x-ship.visual.position.x,b.visual.position.z-ship.visual.position.z).length_squared())
	var target: Dictionary = in_arc[0] if not in_arc.is_empty() else {}
	if target.is_empty(): result.phase="out-of-arc" if not enemies.is_empty() else "no-target"; result.label="转船使敌舰进入舷侧 ±25°" if not enemies.is_empty() else "射界内无敌舰"
	elif Vector2(target.visual.position.x-ship.visual.position.x,target.visual.position.z-ship.visual.position.z).length() > result.rangeMeters: result.phase="out-of-range"; result.label="靠近至 %d米以内" % result.rangeMeters; target={}
	else: result.targetId=target.id; result.label="可齐射 · " + target.get("name",target.id)
	var protected := ships.filter(func(s): return s.id != ship.id and s.hull > 0.0 and not _policy_enemy(ship,s,policy))
	for cannon in int(ship.get("cannonsPerSide",0)):
		if not corridor_clear(launch_solution(ship,side,ammo,cannon,target),protected): result.phase="blocked"; result.label="友船遮挡，先调整航向"; return result
	return result
static func muzzle(visual: Dictionary, spec: Dictionary, side: String, cannon: int) -> Dictionary:
	var longitudinal = spec.length * (-0.138 + cannon * 0.092 if spec.guns == 4 else -0.23 + cannon * 0.46 / maxf(1, spec.guns - 1))
	var curve = pow(1.0 - pow(longitudinal / (spec.length / 2.0), 2.0), 0.64)
	var out = spec.width * 0.435 * curve + 0.87
	var sign_side = 1 if side == "starboard" else -1
	return {"x": visual.position.x + cos(visual.heading) * longitudinal - sin(visual.heading) * sign_side * out,
		"y": visual.position.y + spec.freeboard + 0.3, "z": visual.position.z + sin(visual.heading) * longitudinal + cos(visual.heading) * sign_side * out}
