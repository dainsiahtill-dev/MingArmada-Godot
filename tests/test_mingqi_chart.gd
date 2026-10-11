extends SceneTree
## Saved source campaign/native data; real Control click and canonical intent boundary.
var assertions := 0
var failures := 0
var emitted: Array = []
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures += 1; printerr("FAIL: ", message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var ui = load("res://game/ui/mingqi/mingqi_interface.gd").new()
	root.add_child(ui)
	await process_frame
	check(ui.has_method("configure_chart"), "interface accepts real terrain authority for antique chart")
	if not ui.has_method("configure_chart"): ui.free(); finish(); return
	var geography: Array = JSON.parse_string(FileAccess.get_file_as_string("res://game/data/mingqi_geography.json"))
	var height = load("res://modules/scene_engine/terrain/height_field.gd").new()
	check(height.configure_ports(geography), "production Mingqi geography configures actual height source")
	check(ui.configure_chart(height.sample_height), "injected real height configures mounted chart")
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/mingqi-reference.json"))
	var source: Dictionary = reference.businessSteps[2]
	var packet := {"campaign":source.state.duplicate(true),"naval":source.native.duplicate(true),"runtime":{"generation":61,"status":"ready","paused":false,"controllableShipIds":[source.state.flagshipId]}}
	var flag: String = packet.campaign.flagshipId
	packet.campaign.vessels[flag].pose.position = {"x":99999,"z":99999}
	var untouched := packet.duplicate(true)
	ui.command_requested.connect(func(intent): emitted.append(intent))
	ui.apply_snapshot(packet)
	ui.open_panel("convoy")
	for frame in 4: await process_frame
	var chart = ui.find_child("fleet_chart",true,false)
	chart.size = Vector2(640,420)
	check(not chart._coast_segments.is_empty(), "Mingqi chart samples terrain including real island coast")
	var marks: Array = chart.ship_marks()
	check(not marks.is_empty() and marks[0].position==Vector2.ZERO and marks[0].flagship, "near-field contacts use recorded native pose despite stale campaign vessel pose")
	check(chart.view_bounds().size.x<2000, "stale distant campaign vessel cannot stretch canonical chart bounds")
	check(chart._overlays.get("routes",[]).size()==reference.routes.size(), "source campaign route geometry reaches antique presentation")
	check(chart._ports.size()==3 and absf(chart._ports[0].x+306.2570958447386)<0.0001, "port glyphs use real native geography coordinates")
	var pixel: Vector2 = chart.projected({"x":123.4,"z":-84.7})
	click(chart,pixel)
	check(emitted.is_empty(), "expanded chart click edits draft without issuing war or sail order")
	check(ui.find_child("point_x",true,false).value==123 and ui.find_child("point_z",true,false).value==-85, "actual chart click fills canonical X/Z form draft")
	ui.open_panel("tactics")
	var navigate = ui.find_child("navigate",true,false)
	check(not navigate.disabled, "actual controllable native flagship enables Navigate")
	navigate.pressed.emit()
	check(emitted.size()==1 and emitted[0]=={"type":"navigate","shipId":flag,"point":{"x":123.0,"z":-85.0}}, "only Navigate submits canonical sailing intent from edited point")
	check(packet==untouched, "chart editing and navigation leave authoritative campaign/native packet untouched")
	click(chart,Vector2(2,2))
	check(ui.find_child("point_x",true,false).value==123 and ui.find_child("point_z",true,false).value==-85, "non-navigable antique frame cannot overwrite draft")
	packet.runtime.paused=true
	ui.apply_snapshot(packet)
	check(ui.find_child("navigate",true,false).disabled, "paused runtime retains native navigation authority gate")
	packet.runtime.paused=false
	packet.runtime.generation=62
	ui.apply_snapshot(packet)
	chart.point_requested.emit({"x":777,"z":888})
	check(ui.find_child("point_x",true,false).value==0 and ui.find_child("point_z",true,false).value==0, "retired chart mount/generation callback cannot edit new world draft")
	var fresh = ui.find_child("fleet_chart",true,false)
	check(not fresh._coast_segments.is_empty(), "rebuild retains caller terrain injection")
	packet.naval={"ships":[]}
	ui.apply_snapshot(packet)
	check(fresh.ship_marks().is_empty(), "absent native contact never falls back to stale campaign vessel")
	check(source.native.ships[0].visual.position.x==0 and source.state.vessels[flag].pose.position.x!=99999, "saved source fixture remains detached from packet mutations")
	ui.close_panel(); check(not ui.is_panel_open(), "Root can hide compact chart only while operation panel open")
	ui.open_panel("convoy"); check(ui.is_panel_open(), "opening convoy updates Root visibility gate")
	ui.open_menu(); check(ui.is_menu_open(), "Root can hide compact chart while menu open")
	ui.close_menu(); check(not ui.is_menu_open(), "menu close restores Root visibility gate")
	check(not ui.configure_chart(Callable()), "missing terrain authority rejects configuration")
	check(fresh.ship_marks().is_empty() and not fresh._height.is_valid(), "rejected authority releases mounted sampler and contacts")
	ui.free()
	await process_frame
	finish()
func click(chart, position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position=position; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=true
	chart._gui_input(event)
func finish() -> void:
	print("MINGQI_CHART_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
