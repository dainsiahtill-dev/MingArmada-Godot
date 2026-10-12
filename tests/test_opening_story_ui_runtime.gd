extends SceneTree
## Real Interface -> _send -> Runtime.command -> Campaign, not an intent spy.
const Runtime = preload("res://game/runtime/mingqi_runtime.gd")
const Interface = preload("res://game/ui/mingqi/mingqi_interface.gd")
const SaveCodec = preload("res://game/domain/persistence/save_codec.gd")
const Campaign = preload("res://game/domain/mingqi/campaign.gd")
var assertions := 0
var failures := 0
var results: Array = []
var commands: Array = []

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL story UI runtime: ", message)

func _initialize() -> void:
	_run.call_deferred()

func _press(ui, name: String) -> void:
	var button = ui.find_child(name, true, false)
	check(button is Button and not button.disabled, "actual enabled UI " + name)
	if button is Button and not button.disabled:
		button.pressed.emit()

func _select(ui, name: String, id: String) -> void:
	var field = ui.find_child(name, true, false)
	for index in field.item_count:
		if str(field.get_item_metadata(index)) == id:
			field.select(index)
			field.item_selected.emit(index)
			return
	check(false, "real selector contains " + id)

func _service(type: String, fixture: Dictionary = {}) -> void:
	var session := Campaign.new()
	if not fixture.is_empty():
		check(session.restore(SaveCodec.encode(fixture)), "care fixture restores through strict codec")
	var runtime := Runtime.new()
	check(runtime.configure(func(_x: float, _z: float) -> float: return -24.0, session).ok, "service runtime configured")
	var ui = Interface.new()
	root.add_child(ui)
	await process_frame
	var service_results: Array = []
	var service_commands: Array = []
	ui.command_requested.connect(func(input: Dictionary):
		service_commands.append(input.duplicate(true))
		service_results.append(runtime.command(input))
		ui.apply_snapshot(runtime.snapshot()))
	var packet: Dictionary = runtime.snapshot()
	var ship_id := str(packet.campaign.campaignId) + "-heritage"
	var before: Dictionary = packet.campaign
	ui.apply_snapshot(packet)
	ui.open_panel("port")
	_select(ui, "service_ship", ship_id)
	if type == "treat-wounded": ui.find_child("treatment_quantity", true, false).value = 3
	_press(ui, "service_" + type.replace("-", "_"))
	check(service_results.size() == 1 and service_results[0].ok, "real legal port " + type + " accepted")
	if not service_commands.is_empty():
		check(SaveCodec.command_data(service_commands[0]), "strict pure-data " + type + " payload")
		var fields := {}
		for key in service_commands[0]: fields[str(key)] = type_string(typeof(key)) + ":" + type_string(typeof(service_commands[0][key]))
		print("SERVICE_UI_RUNTIME_WIRE ", JSON.stringify({"intent": service_commands[0], "field_types": fields, "result": service_results[0]}))
	var state: Dictionary = runtime.snapshot().campaign
	var matching: Array = state.works.values().filter(func(work: Dictionary) -> bool: return work.shipId == ship_id and work.kind == ("treatment" if type == "treat-wounded" else type))
	check(matching.size() == 1, "actual " + type + " work created")
	check(state.captain.silver == before.captain.silver - (12 if type == "treat-wounded" else 150), "actual service quote deducted")
	if matching.size() == 1:
		check(matching[0].status == "active", "service waits for actual simulation completion")
		if type == "treat-wounded": check(matching[0].quantity == 3, "actual treatment work holds requested wounded count")
	ui.free()
	runtime.dispose()
	await process_frame

func _run() -> void:
	var runtime := Runtime.new()
	check(runtime.configure(func(_x: float, _z: float) -> float: return -24.0).ok, "real runtime configured")
	var ui = Interface.new()
	root.add_child(ui)
	await process_frame
	ui.command_requested.connect(func(input: Dictionary):
		commands.append(input.duplicate(true))
		results.append(runtime.command(input))
		ui.apply_snapshot(runtime.snapshot()))
	var before: Dictionary = runtime.snapshot().campaign
	ui.apply_snapshot(runtime.snapshot())
	ui.open_panel("story")
	_press(ui, "story_choice_old-ledger_settle-wages")
	check(not results.is_empty() and results.back().ok, "real UI wages accepted by runtime")
	var fields := {}
	if not commands.is_empty():
		for key in commands.back(): fields[str(key)] = type_string(typeof(key)) + ":" + type_string(typeof(commands.back()[key]))
	print("STORY_UI_RUNTIME_WIRE ", JSON.stringify({"intent": commands.back() if not commands.is_empty() else {}, "field_types": fields, "result": results.back() if not results.is_empty() else {}}))
	check(not commands.is_empty() and SaveCodec.command_data(commands.back()), "actual emitted command satisfies pure-data boundary")
	var state: Dictionary = runtime.snapshot().campaign
	check(state.captain.silver == before.captain.silver - 80 and state.reputations.crewSupport == 60, "actual wages/currency/crew support changed")
	check(runtime.snapshot().story.scenes[0].status == "completed", "real committed story projected completed")
	ui.open_panel("convoy")
	_press(ui, "contract_accept_convoy-001")
	check(not results.is_empty() and results.back().ok, "existing convoy UI accepted by real runtime")
	check(runtime.snapshot().campaign.contracts["convoy-001"].status == "active", "actual convoy contract activated")
	ui.open_panel("story")
	_press(ui, "story_choice_pilot-plan_hire-pilot")
	check(not results.is_empty() and results.back().ok, "real UI hires pilot")
	for voyage_id in runtime.snapshot().campaign.contracts["convoy-001"].voyageIds:
		check(runtime.snapshot().campaign.voyages[voyage_id].routeId == "xiamen-kinmen-shallow", "real route changed")
	var quantity = ui.find_child("debt_quantity", true, false)
	quantity.value = 100
	before = runtime.snapshot().campaign
	_press(ui, "repay_debt")
	check(not results.is_empty() and results.back().ok, "real UI partial payment accepted")
	state = runtime.snapshot().campaign
	check(state.debt.principal == before.debt.principal - 100 and state.captain.silver == before.captain.silver - 100, "actual debt and silver reduced")
	# Same pure-data failure class also occurs in the old tactical payload builder.
	ui.open_panel("tactics")
	var id: String = state.flagshipId
	ui.find_child("tactics_ship_" + id, true, false).button_pressed = true
	var kinds = ui.find_child("tactics_kind", true, false)
	for index in kinds.item_count:
		if str(kinds.get_item_metadata(index)) == "rally":
			kinds.select(index)
			kinds.item_selected.emit(index)
			break
	_press(ui, "tactics_submit")
	check(results.back().ok and SaveCodec.command_data(commands.back()), "real tactical nested fields use String keys")
	for command in commands:
		check(SaveCodec.command_data(command), "every UI business command crosses strict schema")
	ui.free()
	runtime.dispose()
	await process_frame
	await _service("refit")
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/mingqi-reference.json"))
	await _service("treat-wounded", fixtures.careInitial)
	print("OPENING_STORY_UI_RUNTIME_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
