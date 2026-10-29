extends SceneTree
## Real practice authority and natural native simulation; no direct ship-state edits.

const Practice = preload("res://game/runtime/naval_practice_runtime.gd")
const STEP := 1.0 / 60.0
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL fire skirmish: ", label)
	return ok

func near(actual: float, wanted: float, label: String) -> void:
	check(absf(actual - wanted) < 0.000001, label + " actual=" + str(actual) + " wanted=" + str(wanted))

func ship(runtime: RefCounted, id: String) -> Dictionary:
	for value: Dictionary in runtime.snapshot().naval.ships:
		if value.id == id:
			return value
	return {}

func start(mode: String) -> RefCounted:
	var runtime = Practice.new()
	var result: Dictionary = runtime.configure(func(_x: float, _z: float) -> float: return -24.0, {"mode":mode})
	if not check(result.get("ok",false), "real practice mode configures: " + mode):
		runtime.dispose()
		return null
	return runtime

func extension_guard(runtime: RefCounted) -> bool:
	var packet: Dictionary = runtime.snapshot()
	if not check(packet.get("naval",{}).get("ships",[]).size() == 2, "fire mode has exactly two real ships"):
		return false
	for id: String in ["player","enemy-1"]:
		var vessel: Dictionary = ship(runtime,id)
		if not check(not vessel.is_empty() and vessel.get("fireControl") is Dictionary and vessel.get("fireLauncher") is Dictionary, "real fire mode declares both extensions: " + id):
			return false
	return true

func initial_contract(runtime: RefCounted, label: String) -> void:
	var packet: Dictionary = runtime.snapshot()
	check(packet.runtime.mode == "fire" and not packet.runtime.paused, label + ": actual runtime reports active fire mode")
	for id: String in ["player","enemy-1"]:
		var vessel: Dictionary = ship(runtime,id)
		check(vessel.kind == "fuchuan" and vessel.team == ("player" if id == "player" else "hostile"), label + ": real Fuchuan identity and team: " + id)
		var fire: Dictionary = vessel.fireControl
		var launcher: Dictionary = vessel.fireLauncher
		check(fire.version == "ship-fire-r1" and fire.supplies == 24 and fire.heat == 0.0 and fire.fuelSeconds == 0.0 and fire.crewDamageCarry == 0.0 and fire.workCarry == 0.0, label + ": finite fresh fire budget without active heat or carry: " + id)
		check(fire.assignedFirefighters == 0 and fire.pendingFirefighters == 0 and fire.transferTicks == 0, label + ": no worker inherited from previous training: " + id)
		check(launcher.ammo == {"fire-ball":2,"thorn-ball":2} and launcher.cooldownSeconds == 0.0 and launcher.operationSeconds == 0.0, label + ": only the declared fresh auxiliary loadout: " + id)
	var player: Dictionary = ship(runtime,"player")
	var enemy: Dictionary = ship(runtime,"enemy-1")
	near(Vector2(player.visual.position.x-enemy.visual.position.x,player.visual.position.z-enemy.visual.position.z).length(), 60.0, label + ": initial horizontal separation is 60 metres")
	check(packet.naval.projectiles.is_empty(), label + ": fresh epoch contains no inherited projectile")

func run() -> void:
	var runtime: RefCounted = start("fire")
	if runtime == null:
		finish()
		return
	if not extension_guard(runtime):
		runtime.dispose()
		finish()
		return
	initial_contract(runtime,"first start")
	_source_pin(runtime)
	_launch_and_natural_hit(runtime)
	_restart(runtime)
	runtime.dispose()
	_pause_discards_pending()
	_staffing()
	_legacy_modes()
	finish()

func _source_pin(runtime: RefCounted) -> void:
	var before: Dictionary = runtime.snapshot().naval
	var forged_launch: Dictionary = runtime.command({"type":"launch-fire","shipId":"enemy-1","payload":"fire-ball","targetId":"player"})
	var forged_team: Dictionary = runtime.command({"type":"fire-control","shipId":"enemy-1","crew":8})
	check(not forged_launch.get("ok",false) and not forged_team.get("ok",false), "UI cannot forge another ship as launcher or work-team source")
	check(runtime.snapshot().naval == before and not runtime.simulation.has_pending_input(), "rejected forged sources change neither native state nor action queue")

func _launch_and_natural_hit(runtime: RefCounted) -> void:
	var before: Dictionary = runtime.snapshot().naval
	var ordinary_ammo: Dictionary = ship(runtime,"player").ammo.duplicate(true)
	var ordinary_reload: Dictionary = ship(runtime,"player").cooldownSeconds.duplicate(true)
	var queued: Dictionary = runtime.command({"type":"launch-fire","payload":"fire-ball","targetId":"enemy-1"})
	if not check(queued.get("ok",false), "public fire launch enters original action queue"):
		return
	check(runtime.snapshot().naval == before and runtime.simulation.has_pending_input(), "accepting queued intent cannot debit stock or create an early projectile")
	check(runtime.advance(STEP) > 0.0, "first real fixed step consumes queued launch")
	var player: Dictionary = ship(runtime,"player")
	check(player.fireLauncher.ammo == {"fire-ball":1,"thorn-ball":2}, "one real launch consumes exactly one selected payload")
	check(player.ammo == ordinary_ammo and player.cooldownSeconds == ordinary_reload, "auxiliary launch preserves ordinary cannon ammunition and reload")
	check(player.fireControl.supplies == 24 and player.fireControl.workCarry == 0.0, "launcher operation does not spend firefighting preparations")
	near(player.fireLauncher.cooldownSeconds,12.0-STEP,"shared auxiliary reload starts on accepted launch tick")
	near(player.fireLauncher.operationSeconds,2.0-STEP,"launcher workers remain occupied after accepted launch tick")
	var events: Array = runtime.drain_events()
	var launched: Dictionary = {}
	for event: Dictionary in events:
		if event.get("type") == "fire-payload-launched" and event.get("shipId") == "player":
			launched = event
	if not check(not launched.is_empty() and launched.get("targetId") == "enemy-1" and launched.get("payload") == "fire-ball" and not str(launched.get("projectileId","")).is_empty(), "native launch receipt binds fixed source, real target, payload and projectile"):
		return
	var found_projectile := false
	for projectile: Dictionary in runtime.snapshot().naval.projectiles:
		if projectile.id == launched.projectileId:
			found_projectile = projectile.get("kind") == "fire-payload" and projectile.shipId == "player" and projectile.payload == "fire-ball"
	check(found_projectile, "accepted payload exists as actual moving native projectile")
	var hits: Array = []
	var splashes: Array = []
	for tick in range(300):
		runtime.advance(STEP)
		var batch: Array = runtime.drain_events()
		events.append_array(batch)
		for event: Dictionary in batch:
			if event.get("projectileId") != launched.projectileId:
				continue
			if event.get("type") == "fire-payload-hit":
				hits.append(event)
			elif event.get("type") == "fire-payload-splash":
				splashes.append(event)
		if not hits.is_empty() or not splashes.is_empty():
			break
	if check(hits.size() == 1 and splashes.is_empty(), "natural simulation produces one real hit within payload flight budget"):
		check(hits[0].get("shipId") == "player" and hits[0].get("targetId") == "enemy-1" and hits[0].get("payload") == "fire-ball", "collision receipt retains original fixed source and intended enemy")
		var enemy: Dictionary = ship(runtime,"enemy-1")
		check(enemy.fireControl.heat > 0.0 and enemy.fireControl.fuelSeconds > 0.0, "only actual native collision creates authoritative enemy fire")
		var hull_before: float = enemy.hull
		for i in range(12):
			runtime.advance(STEP)
		var later: Dictionary = ship(runtime,"enemy-1")
		check(later.hull < hull_before and later.fireControl.fuelSeconds < enemy.fireControl.fuelSeconds, "burning target takes real subsequent DOT while fuel accepts time")
	var launch_count := 0
	for event: Dictionary in events:
		if event.get("type") == "fire-payload-launched" and event.get("shipId") == "player":
			launch_count += 1
	check(launch_count == 1 and ship(runtime,"player").fireLauncher.ammo["fire-ball"] == 1, "natural advancement cannot replay the one queued purchase-free training shot")

func _restart(runtime: RefCounted) -> void:
	var before: Dictionary = runtime.snapshot()
	check(runtime.command({"type":"fire-control","crew":8}).get("ok",false), "old training may have a queued work command before restart")
	if not check(runtime.command({"type":"restart"}).get("ok",false), "real restart rebuilds fire training"):
		return
	if not extension_guard(runtime):
		return
	initial_contract(runtime,"restart")
	check(runtime.snapshot().runtime.generation > before.runtime.generation and runtime.snapshot().naval.battleId != before.naval.battleId, "restart allocates a fresh generation and native battle identity")
	runtime.advance(STEP)
	var player: Dictionary = ship(runtime,"player")
	check(player.fireControl.pendingFirefighters == 0 and player.fireControl.transferTicks == 0 and player.fireLauncher.ammo == {"fire-ball":2,"thorn-ball":2}, "restart discards old queued staffing and restores finite training stock")
	check(runtime.command({"type":"launch-fire","payload":"thorn-ball","targetId":"enemy-1"}).get("ok",false), "second payload uses the same real command seam")
	runtime.advance(STEP)
	check(ship(runtime,"player").fireLauncher.ammo == {"fire-ball":2,"thorn-ball":1}, "thorn launch debits only its own finite two-shot stock")
	check(runtime.command({"type":"restart"}).get("ok",false), "restart after thorn launch succeeds")
	initial_contract(runtime,"restart after thorn")

func _pause_discards_pending() -> void:
	var runtime: RefCounted = start("fire")
	if runtime == null:
		return
	var initial: Dictionary = runtime.snapshot().naval
	check(runtime.command({"type":"launch-fire","payload":"fire-ball","targetId":"enemy-1"}).get("ok",false), "queue launch before pause")
	check(runtime.command({"type":"fire-control","crew":4}).get("ok",false), "queue work assignment before pause")
	check(runtime.simulation.has_pending_input() and runtime.snapshot().naval == initial, "both pending actions are unaccepted before physics")
	check(runtime.set_pause("player",true).get("ok",false), "pause reaches real simulation owner")
	var paused: Dictionary = runtime.snapshot().naval
	check(not runtime.simulation.has_pending_input(), "pausing clears original pending action queue")
	check(runtime.advance(60.0) == 0.0 and runtime.snapshot().naval == paused, "paused wall time cannot advance fire clocks or consume stock")
	check(not runtime.command({"type":"launch-fire","payload":"thorn-ball","targetId":"enemy-1"}).get("ok",false) and not runtime.command({"type":"fire-control","crew":8}).get("ok",false), "pause rejects new launch and work intents")
	check(runtime.snapshot().naval == paused and not runtime.simulation.has_pending_input(), "rejected paused intents cannot leave deferred side effects")
	check(runtime.command({"type":"resume"}).get("ok",false), "real resume reopens accepted time")
	runtime.advance(STEP)
	var player: Dictionary = ship(runtime,"player")
	check(player.fireLauncher.ammo == {"fire-ball":2,"thorn-ball":2} and player.fireLauncher.cooldownSeconds == 0.0 and player.fireLauncher.operationSeconds == 0.0, "resume cannot resurrect canceled queued launch or spend inventory")
	check(player.fireControl.assignedFirefighters == 0 and player.fireControl.pendingFirefighters == 0 and player.fireControl.transferTicks == 0 and player.fireControl.supplies == 24, "resume cannot resurrect canceled queued assignment")
	var player_launches := 0
	for event: Dictionary in runtime.drain_events():
		if event.get("type") == "fire-payload-launched" and event.get("shipId") == "player":
			player_launches += 1
	check(player_launches == 0, "pause-canceled launch emits no real native launch receipt")
	runtime.dispose()

func _staffing() -> void:
	for workers: int in [2,4,8]:
		var runtime: RefCounted = start("fire")
		if runtime == null:
			return
		var initial: Dictionary = runtime.snapshot().naval
		var population: float = ship(runtime,"player").crew
		check(runtime.command({"type":"fire-control","crew":workers}).get("ok",false), "public assignment accepts requested team: " + str(workers))
		check(runtime.snapshot().naval == initial, "assignment remains queued until accepted tick: " + str(workers))
		runtime.advance(STEP)
		var traveling: Dictionary = ship(runtime,"player")
		check(traveling.fireControl.pendingFirefighters == workers and traveling.fireControl.assignedFirefighters == 0 and traveling.fireControl.transferTicks == 119, "first tick schedules real 120-tick transfer: " + str(workers))
		check(traveling.crew == population and traveling.availableCrew == int(population)-workers, "reserved team leaves total population intact: " + str(workers))
		for tick in range(119):
			runtime.advance(STEP)
		var arrived: Dictionary = ship(runtime,"player")
		check(arrived.fireControl.assignedFirefighters == workers and arrived.fireControl.pendingFirefighters == workers and arrived.fireControl.transferTicks == 0, "real simulation completes exactly 120 travel ticks: " + str(workers))
		check(arrived.availableCrew == maxi(0,int(floor(arrived.crew))-workers), "arrived team remains unavailable to other stations: " + str(workers))
		check(arrived.fireControl.heat == 0.0 and arrived.fireControl.supplies == 24 and arrived.fireControl.workCarry == 0.0, "explicit cold standby reserves people without free fire or preparation spending: " + str(workers))
		runtime.dispose()

func _legacy_modes() -> void:
	for mode: String in ["duel","fleet","sail"]:
		var runtime: RefCounted = start(mode)
		if runtime == null:
			continue
		var packet: Dictionary = runtime.snapshot()
		check(packet.runtime.mode == mode, "legacy mode keeps its original runtime identity: " + mode)
		for vessel: Dictionary in packet.naval.ships:
			check(not vessel.has("fireControl") and not vessel.has("fireLauncher") and not vessel.has("availableCrew"), "legacy ship remains without optional fire extension: " + mode + ":" + vessel.id)
		if mode == "duel":
			var fire_runtime: RefCounted = start("fire")
			if fire_runtime != null:
				var old_player: Dictionary = ship(runtime,"player")
				var fire_player: Dictionary = ship(fire_runtime,"player")
				check(old_player.ammo == fire_player.ammo and old_player.ammoType == fire_player.ammoType and old_player.cooldownSeconds == fire_player.cooldownSeconds, "fire fixture retains ordinary duel cannon loadout and reload contract")
				fire_runtime.dispose()
		runtime.dispose()

func finish() -> void:
	print("FIRE_SKIRMISH_RUNTIME_TEST_COMPLETE checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
