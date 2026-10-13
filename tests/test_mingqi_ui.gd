extends SceneTree
## Real Control tree and canonical intent boundary. Fixture is saved web data.
var assertions := 0
var failures := 0
var emitted: Array = []

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if not ResourceLoader.exists("res://game/ui/mingqi/mingqi_interface.gd"):
		check(false, "native five-panel interface exists")
		_finish()
		return
	var Interface = load("res://game/ui/mingqi/mingqi_interface.gd")
	if not Interface or not Interface.can_instantiate():
		check(false, "interface parses before Control test")
		_finish()
		return
	var ui = Interface.new()
	root.add_child(ui)
	await process_frame
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/web-save-v2.json"))
	var state: Dictionary = envelope.state
	var packet := {"campaign": state, "naval": {"ships": []}, "runtime": {"generation": 1, "paused": false, "canSave": false, "saveReason": "save-safe-port-required", "status": "ready"}}
	var untouched := packet.duplicate(true)
	ui.command_requested.connect(func(intent): emitted.append(intent))
	ui.apply_snapshot(packet)
	check(ui is CanvasLayer, "interface uses native CanvasLayer")
	var heading = ui.find_child("panel_heading", true, false)
	var titles := {"ship": "旗舰与操船", "convoy": "船队与海图", "port": "靠港与贸易", "boarding": "接舷与俘获", "tactics": "船队战术"}
	for panel in ["ship", "convoy", "port", "boarding", "tactics"]:
		ui.open_panel(panel)
		check(ui.find_child("panel_" + panel, true, false) is Control, "real panel built: " + panel)
		check(heading.text == titles[panel], "heading follows selected panel immediately: " + panel)
		check(ui.find_child("panel_heading", true, false) == heading, "panel selection preserves actual Control tree: " + panel)
	check(ui.find_child("identity", true, false).text.contains("林船长"), "identity shows canonical captain")
	check(ui.find_child("silver", true, false).text.contains("563"), "silver comes from snapshot")
	check(ui.find_child("port_dock_xiamen", true, false).disabled, "absent dock eligibility cannot offer safe docking")
	ui.open_menu()
	check(ui.find_child("save", true, false).disabled, "unsafe save stays disabled")
	check(ui.find_child("save_reason", true, false).text.contains("安全港口"), "save displays human reason")
	check(packet == untouched, "display never mutates packet")
	ui.close_menu()
	ui.open_panel("ship")
	check(ui.find_child("ship_fire_port", true, false).disabled, "no native guns means no claimed broadside readiness")
	var ids: Array = state.vessels.keys()
	var ships: Array = []
	for id in ids:
		var v: Dictionary = state.vessels[id]
		ships.append({"id": id, "name": v.name, "visual": {"position": v.pose.position.duplicate(), "velocity": {"x": 2, "z": 0}, "heading": 0}, "hull": v.damage.hull, "maxHull": 100, "sail": v.damage.sail, "maxSail": 100, "crew": v.crew.able, "maxCrew": 80, "cannonsPerSide": 4, "rudder": 0, "sailDeployment": 0, "sailAngle": 0.4, "autoTrim": true, "ammoType": "solid", "ammo": {"solid": 40, "chain": 24, "grape": 24}, "cooldownSeconds": {"port": 0, "starboard": 0}})
	packet.naval = {"ships": ships, "playerId": state.flagshipId, "wind": {"direction": {"x": 0, "y": -1}, "speed": 8}}
	packet.runtime.merge({"controllableShipIds": [state.flagshipId, "fixture-1650-heritage"], "selectedShipId": state.flagshipId, "canDock": {"xiamen": false, "kinmen": true, "forward-supply": false}, "dockReason": {"xiamen": "unsafe-port", "forward-supply": "unsafe-port"}, "canDepart": true, "canSave": true, "saveReason": "", "eligibility": {"repair": {"ok": true}, "refit": {"ok": true}, "treat-wounded": {"ok": true}, "release-prisoners": {"ok": true}, "start-boarding": {"ok": true}, "allocate-prize": {"ok": true}, "take-prize-cargo": {"ok": true}, "resolve-prize": {"ok": true}, "sell-prize": {"ok": true}, "incorporate-prize": {"ok": true}}}, true)
	ui.apply_snapshot(packet)
	check(not ui.find_child("ship_fire_port", true, false).disabled, "actual native broadside becomes available")
	var before_fire := emitted.size()
	_press(ui, "ship_fire_port")
	check(emitted.back().type == "controls" and emitted.back().firePort == true, "port broadside submits native controls intent")
	_press(ui, "ship_fire_port")
	check(emitted.size() == before_fire + 1, "same snapshot double click emits once")
	packet.campaign.revision += 1
	ui.apply_snapshot(packet)
	_press(ui, "ship_fire_port")
	check(emitted.size() == before_fire + 1, "rapid duplicate still blocked after synchronous acknowledgement")
	var stale = ui.find_child("ship_fire_starboard", true, false)
	packet.runtime.generation = 2
	ui.apply_snapshot(packet)
	stale.pressed.emit()
	check(emitted.size() == before_fire + 1, "old generation cannot command new world")
	ui.open_panel("port")
	check(not ui.find_child("port_dock_kinmen", true, false).disabled, "dock reads eligibility of specific port")
	_press(ui, "port_dock_kinmen")
	check(emitted.back().type == "dock" and emitted.back().portId == "kinmen", "real catalog port used")
	check(emitted.back().expectedRevision == state.revision and not emitted.back().commandId.is_empty(), "campaign intent carries fresh envelope")
	var quantity = ui.find_child("trade_quantity", true, false)
	quantity.get_line_edit().grab_focus()
	await process_frame
	check(ui.captures_keyboard(), "numeric field captures sailing keyboard")
	quantity.get_line_edit().text = "7"
	packet.campaign.revision += 1
	ui.apply_snapshot(packet)
	check(quantity.get_line_edit().has_focus() and quantity.get_line_edit().text == "7", "snapshot refresh preserves focused draft")
	quantity.get_line_edit().release_focus()
	ui.open_panel("convoy")
	check(ui.find_child("voyage_route_fixture-1650-grain-a-voyage", true, false) is OptionButton, "voyage has actual route choice")
	ui.open_panel("tactics")
	check(ui.find_child("tactics_kind", true, false).item_count == 6, "all six tactical intents provided")
	ui.open_menu()
	check(not ui.find_child("save", true, false).disabled, "safe save enabled from runtime")
	_press(ui, "save")
	check(emitted.back().type == "save", "save routed as intent")
	check(packet.campaign.vessels == untouched.campaign.vessels, "commands do not change crew cargo or pose")
	await _verify_review_regressions(ui)
	_verify_resolution_gates(ui)
	_verify_recorded_commands(ui)
	ui.free()
	await process_frame
	await _verify_layout_lifecycle(Interface)
	_finish()

func _press(ui, id: String) -> void:
	var control = ui.find_child(id.validate_node_name(), true, false)
	check(control is Button and not control.disabled, "enabled native button: " + id)
	if control is Button and not control.disabled: control.pressed.emit()

func _choose(ui, id: String, value: String) -> void:
	var option = ui.find_child(id, true, false)
	check(option is OptionButton, "actual selector: " + id)
	if not option is OptionButton: return
	for index in option.item_count:
		if str(option.get_item_metadata(index)) == value:
			option.select(index)
			option.item_selected.emit(index)
			return
	check(false, "selector contains canonical ID: " + value)

func _verify_review_regressions(ui) -> void:
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/mingqi-reference.json"))
	# Original accepted buy after-state has actual grain to sell and spare capacity.
	var packet := {"campaign": reference.steps[0].state, "naval": {"ships": []}, "runtime": {"generation": 30, "paused": false, "status": "ready"}}
	ui.close_menu()
	ui.apply_snapshot(packet)
	ui.open_panel("port")
	check(ui.find_child("trade_buy", true, false).disabled, "resource quote cannot enable buy without native eligibility")
	check(ui.find_child("trade_sell", true, false).disabled, "resource quote cannot enable sell without native eligibility")
	packet.runtime.eligibility = {"buy": {"ok": false, "reason": "unsafe-port"}, "sell": {"ok": false, "reason": "unsafe-port"}}
	ui.apply_snapshot(packet)
	check(ui.find_child("trade_buy", true, false).disabled and ui.find_child("trade_sell", true, false).disabled, "explicit unsafe native trade fact overrides valid price quote")
	var reason = ui.find_child("trade_native_reason", true, false)
	check(reason is Label and reason.text.contains("停稳") if reason is Label else false, "native trade refusal has visible human reason")
	packet.runtime.eligibility = {"buy": {"ok": true}, "sell": {"ok": true}}
	ui.apply_snapshot(packet)
	check(not ui.find_child("trade_buy", true, false).disabled and not ui.find_child("trade_sell", true, false).disabled, "valid quote and actual native eligibility enable trade")
	ui.find_child("pause", true, false).grab_focus()
	await process_frame
	check(root.gui_get_focus_owner() == ui.find_child("pause", true, false), "real pause button obtains GUI focus")
	check(not ui.captures_keyboard(), "button focus permits continuous steering keys")
	ui.open_panel("tactics")
	ui.find_child("tactics_kind", true, false).grab_focus()
	await process_frame
	check(not ui.captures_keyboard(), "dropdown focus is navigation, not text editing")
	ui.open_panel("ship")
	ui.find_child("ship_sail", true, false).grab_focus()
	await process_frame
	check(not ui.captures_keyboard(), "slider focus does not suppress sailing keyboard")
	ui.open_menu()
	var editor = ui.find_child("import_json", true, false)
	editor.grab_focus()
	await process_frame
	check(ui.captures_keyboard(), "editable JSON text captures sailing keyboard")
	editor.editable = false
	check(not ui.captures_keyboard(), "read-only text does not claim typing focus")
	editor.editable = true
	ui.close_menu()
	for width in [1600, 1100]:
		root.size = Vector2i(width, 900)
		root.content_scale_size = Vector2i.ZERO
		for frame in 8: await process_frame
		var hud = ui.find_child("hud", true, false)
		print("HUD_LAYOUT viewport=", root.get_visible_rect().size, " size=", hud.size, " minimum=", hud.get_combined_minimum_size())
		check(hud.size.x <= 430 and hud.size.y <= 390, "compact HUD at " + str(width) + " preserves sea view")
		var operation = ui.find_child("operation", true, false)
		check(operation.position.x >= hud.position.x + hud.size.x + 16, "right operation remains independent at " + str(width))
		ui.close_panel()
		await process_frame
		check(not operation.visible and hud.size.y <= 390, "collapsed panel leaves no full-height opaque block at " + str(width))
		ui.open_panel("port")
	for width in [900, 800]:
		root.size = Vector2i(width, 900)
		for frame in 8: await process_frame
		var hud = ui.find_child("hud", true, false)
		var operation = ui.find_child("operation", true, false)
		check(operation.position.y >= hud.position.y + hud.size.y + 16, "narrow operation clears actual HUD bottom at " + str(width))
		check(operation.position.y + operation.size.y <= 882, "narrow operation fits remaining viewport height at " + str(width))

func _verify_layout_lifecycle(Interface) -> void:
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/mingqi-reference.json"))
	root.size = Vector2i(1600, 900)
	root.content_scale_size = Vector2i.ZERO
	var ui = Interface.new()
	root.add_child(ui)
	var packet := {"campaign": reference.initial, "naval": {"ships": []}, "runtime": {"generation": 40, "status": "ready", "paused": false}}
	# Scene startup applies once, then lets native containers settle without refresh.
	ui.apply_snapshot(packet)
	for frame in 8: await process_frame
	var hud = ui.find_child("hud", true, false)
	print("HUD_FIRST_PACKET size=", hud.size, " minimum=", hud.get_combined_minimum_size())
	# 44feae1 added mouse-course and camera instructions. Use this suite's
	# established 390px compact limit and additionally reject lifecycle growth.
	var initial_height: float = hud.size.y
	check(hud.size.x <= 430 and initial_height <= 390, "single initial snapshot settles to compact HUD without manual layout")
	ui.open_panel("convoy")
	for frame in 8: await process_frame
	check(is_equal_approx(hud.size.y,initial_height), "panel selection preserves settled HUD height without new snapshot")
	ui.open_menu()
	for frame in 8: await process_frame
	var picker = ui.find_child("import_file_picker", true, false)
	picker.popup_centered_ratio(0.7)
	await process_frame
	picker.hide()
	picker.canceled.emit()
	ui.close_menu()
	for frame in 8: await process_frame
	check(not ui.find_child("voyage_menu", true, false).visible and not picker.visible and is_equal_approx(hud.size.y,initial_height), "closing actual file dialog and menu preserves settled HUD height")
	ui.close_panel()
	var old_operation = ui.find_child("operation", true, false)
	packet.campaign = reference.steps[-1].state
	ui.apply_snapshot(packet)
	var operation = ui.find_child("operation", true, false)
	check(operation != old_operation, "recorded campaign structural change rebuilds operation controls")
	for frame in 8: await process_frame
	hud = ui.find_child("hud", true, false)
	check(not operation.visible, "closed operation stays closed across structural snapshot rebuild")
	check(is_equal_approx(hud.size.y,initial_height), "rebuilt HUD returns to original settled height without repeated snapshots")
	ui.open_panel("tactics")
	packet.runtime.generation = 41
	ui.apply_snapshot(packet)
	for frame in 8: await process_frame
	check(ui.find_child("operation", true, false).visible and ui.find_child("panel_tactics", true, false).visible and ui.find_child("panel_heading", true, false).text == "船队战术", "visible active panel choice survives structural rebuild")
	ui.free()
	await process_frame

func _verify_resolution_gates(ui) -> void:
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/mingqi-reference.json"))
	var state: Dictionary = reference.rescueSteps[-2].state
	var accepted: Dictionary = reference.rescueSteps[-1].command
	var target: String = accepted.targetId
	var receiver: String = accepted.toShipId
	var base_key := "resolve-prize:" + target
	var pair_key := base_key + ":" + receiver
	var packet := {"campaign": state, "naval": {"ships": []}, "runtime": {"generation": 31, "status": "ready", "paused": false, "controllableShipIds": [receiver], "eligibility": {base_key: {"ok": true}}}}
	var untouched := state.duplicate(true)
	ui.apply_snapshot(packet)
	ui.open_panel("boarding")
	_choose(ui, "prize_target", target)
	_choose(ui, "prize_receiver", receiver)
	check(not ui.find_child("prize_release", true, false).disabled, "release needs target readiness without receiving-ship fact")
	check(ui.find_child("prize_abandon", true, false).disabled, "rescue cannot inherit release readiness when pair fact absent")
	packet.runtime.eligibility[pair_key] = {"ok": false, "reason": "prize-not-close"}
	ui.apply_snapshot(packet)
	check(not ui.find_child("prize_release", true, false).disabled, "distant selected receiver cannot disable valid release")
	check(ui.find_child("prize_abandon", true, false).disabled, "actual receiver distance refusal disables rescue")
	_press(ui, "prize_release")
	check(emitted.back().type == "resolve-prize" and emitted.back().choice == "release" and emitted.back().targetId == target and not emitted.back().has("toShipId"), "release intent has no receiver dependency")
	packet.runtime.eligibility[pair_key] = {"ok": true}
	ui.apply_snapshot(packet)
	check(not ui.find_child("prize_release", true, false).disabled and not ui.find_child("prize_abandon", true, false).disabled, "actual pair readiness enables rescue while release stays available")
	check(state == untouched, "resolution controls leave recorded crew and prize state untouched")

func _verify_recorded_commands(ui) -> void:
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/mingqi-reference.json"))
	var seen: Dictionary = {}
	var generation := 10
	for sequence in [["initial", "steps"], ["", "businessSteps"], ["careInitial", "careSteps"], ["", "convoySteps"], ["portInitial", "portSteps"], ["heldInitial", "heldSteps"], ["", "ordersSteps"], ["saleInitial", "saleSteps"], ["rescueInitial", "rescueSteps"]]:
		var previous: Dictionary = reference.get(sequence[0], {})
		var native: Dictionary = {}
		for step in reference[sequence[1]]:
			if step.get("native") is Dictionary: native = step.native
			var command: Dictionary = step.get("command", {})
			if previous.is_empty() or command.is_empty() or not step.get("result", {}).get("ok", false) or seen.has(command.type):
				previous = step.state
				continue
			generation += 1
			var controlled: Array = []
			for id in previous.vessels:
				if previous.vessels[id].ownerId != "enemy": controlled.append(id)
			# A recorded accepted command supplies eligibility for this boundary test;
			# this test never claims these fixtures are a live runtime or executes rules.
			var runtime := {"generation": generation, "status": "ready", "paused": false, "controllableShipIds": controlled, "canDepart": command.type == "depart", "canDock": {}, "eligibility": {command.type: {"ok": true}}}
			if command.type == "dock": runtime.canDock[command.portId] = {"ok": true, "reason": ""}
			var packet := {"campaign": previous, "naval": native, "runtime": runtime}
			var untouched := packet.duplicate(true)
			ui.apply_snapshot(packet)
			var count := emitted.size()
			var button := ""
			match command.type:
				"buy", "sell":
					ui.find_child("trade_quantity", true, false).value = command.quantity
					button = "trade_" + command.type
				"accept-convoy": button = "contract_accept_" + command.get("contractId", "convoy-001")
				"claim-convoy": button = "contract_claim_" + command.contractId
				"depart": button = "depart"
				"dock": button = "port_dock_" + command.portId
				"choose-route": _choose(ui, "voyage_route_" + command.voyageId, command.routeId)
				"repair", "refit", "release-prisoners", "treat-wounded":
					_choose(ui, "service_ship", command.shipId)
					if command.type == "treat-wounded": ui.find_child("treatment_quantity", true, false).value = command.quantity
					button = "service_" + command.type.replace("-", "_")
				"start-boarding":
					_choose(ui, "boarding_source", command.fromShipId)
					_choose(ui, "boarding_target", command.targetId)
					button = "board_start"
				"board-action": button = "board_action_" + command.encounterId + "_" + command.point + "_" + command.action
				"allocate-prize":
					_choose(ui, "prize_target", command.targetId)
					_choose(ui, "boarding_source", command.fromShipId)
					ui.find_child("prize_crew", true, false).value = command.crew
					button = "prize_allocate"
				"take-prize-cargo":
					_choose(ui, "prize_target", command.targetId)
					_choose(ui, "prize_receiver", command.toShipId)
					var good: String = command.cargo.keys()[0]
					_choose(ui, "prize_good", good)
					ui.find_child("prize_quantity", true, false).value = command.cargo[good]
					button = "prize_take_cargo"
				"resolve-prize":
					_choose(ui, "prize_target", command.targetId)
					if command.choice == "abandon": _choose(ui, "prize_receiver", command.toShipId)
					button = "prize_release" if command.choice == "release" else "prize_abandon"
				"sell-prize", "incorporate-prize":
					_choose(ui, "prize_target", command.shipId)
					if command.type == "sell-prize":
						_choose(ui, "prize_sale_receiver", command.crewToShipId)
						check(ui.find_child("prize_sale_value", true, false).text.contains(str(int(step.result.receipt.details.silver)) + "两"), "ship valuation agrees with actual recorded sale")
					button = "prize_sell" if command.type == "sell-prize" else "prize_incorporate"
				"assign-order":
					for id in command.order.shipIds: ui.find_child("tactics_ship_" + id, true, false).button_pressed = true
					_choose(ui, "tactics_kind", command.order.intent.kind)
					if command.order.intent.has("targetId"): _choose(ui, "tactics_target", command.order.intent.targetId)
					button = "tactics_submit"
			if not button.is_empty(): _press(ui, button)
			check(emitted.size() == count + 1, "recorded command has real UI action: " + command.type)
			if emitted.size() == count + 1:
				var actual: Dictionary = emitted.back().duplicate(true)
				check(actual.expectedRevision == previous.revision and not actual.commandId.is_empty(), "fresh canonical envelope: " + command.type)
				actual.erase("commandId")
				actual.erase("expectedRevision")
				var expected := command.duplicate(true)
				expected.erase("commandId")
				expected.erase("expectedRevision")
				if command.type == "assign-order":
					actual.order.erase("id")
					expected.order.erase("id")
					expected.order.issuedAt = previous.simulationSeconds
				if command.type == "accept-convoy" and not expected.has("contractId"): expected.contractId = "convoy-001"
				check(JSON.parse_string(JSON.stringify(actual)) == JSON.parse_string(JSON.stringify(expected)), "payload matches original command: " + command.type)
				seen[command.type] = true
			check(packet == untouched, "command leaves recorded snapshot untouched: " + command.type)
			previous = step.state
	check(seen.size() == 19, "all nineteen campaign intents exercised through controls; saw " + str(seen.keys()))

func _finish() -> void:
	print("MINGQI_UI_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
