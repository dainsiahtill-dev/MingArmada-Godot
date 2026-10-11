extends SceneTree
## Live runtime commands must reach native chart selection and tactical status UI.
const Runtime = preload("res://game/runtime/mingqi_runtime.gd")
const Interface = preload("res://game/ui/mingqi/mingqi_interface.gd")
var failures := 0
var assertions := 0
func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ",detail)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var runtime := Runtime.new()
	var height := func(_x: float,_z: float) -> float: return -24.0
	check(runtime.configure(height).ok,"actual opening configures")
	var packet: Dictionary = runtime.snapshot()
	check(runtime.command({"type":"accept-convoy","commandId":"live-accept","expectedRevision":packet.campaign.revision}).ok,"live native authority grants escort control")
	packet = runtime.snapshot()
	var fast: String = packet.campaign.campaignId+"-fast"
	check(runtime.command({"type":"select-ship","shipId":fast}).ok,"actual controllable escort becomes native player")
	packet = runtime.snapshot()
	check(packet.naval.playerId == fast and packet.runtime.get("selectedShipId") == fast,"runtime selection projection matches actual native player")
	var order := {"id":"live-protect","shipIds":[fast],"intent":{"kind":"protect","targetId":packet.campaign.campaignId+"-grain-a"},"issuedAt":packet.campaign.simulationSeconds}
	check(runtime.command({"type":"assign-order","commandId":order.id,"expectedRevision":packet.campaign.revision,"order":order}).ok,"actual escort receives protective order")
	packet = runtime.snapshot()
	var projected: Array = packet.runtime.get("orderStatuses",[])
	check(projected == runtime.simulation.encounter.orderStatus() and not projected.is_empty(),"live order states reach snapshot without invented history")
	if not projected.is_empty():
		projected[0].state = "external-mutation"
		check(runtime.simulation.encounter.orderStatus()[0].state == "active","projected order records remain detached from native authority")
	var ui := Interface.new(); root.add_child(ui); await process_frame
	ui.configure_chart(height); ui.apply_snapshot(runtime.snapshot()); ui.open_panel("convoy")
	var chart: Control = ui.find_child("fleet_chart",true,false)
	check(chart.selected_id == fast and chart.ship_marks().any(func(mark): return mark.id == fast and mark.selected),"real expanded chart selects the actual commanded escort")
	ui.open_panel("tactics")
	var label: Label = ui.find_child("orders",true,false)
	check(label.text.contains("进行中") and not label.text.contains("历史指令"),"actual active order displays current native state")
	ui.queue_free(); await process_frame; runtime.dispose()
	print("MINGQI_LIVE_PROJECTION_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
