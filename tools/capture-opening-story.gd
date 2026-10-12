extends SceneTree
## Real native controls and real Campaign transactions; isolated save slots.
const Router=preload("res://game/runtime/game_router.gd")
const Storage=preload("res://game/persistence/save_coordinator.gd")
const Settings=preload("res://game/persistence/user_settings.gd")
const Legacy=preload("res://game/runtime/legacy_runtime.gd")
var main: Node
var scene: Node
var assertions:=0
var failures:=0
var captures:=0
var directory:="res://docs/migration/evidence/opening-story/native"
func _initialize() -> void: run.call_deferred()
func check(value: bool,detail: String) -> void:
	assertions+=1
	if not value: failures+=1; printerr("FAIL: ",detail)
func frames(count: int=5) -> void:
	for index in count: await process_frame
func click(control: Control) -> void:
	var parent: Node=control.get_parent()
	while parent:
		if parent is ScrollContainer: parent.ensure_control_visible(control)
		parent=parent.get_parent()
	await frames(3)
	var event:=InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=true; event.position=control.get_global_rect().get_center()
	Input.parse_input_event(event); await process_frame
	event=event.duplicate(); event.pressed=false; Input.parse_input_event(event); await frames(3)
func button(id: String) -> bool:
	var control: Button=scene.interface.find_child(id,true,false)
	check(control!=null,"real native control exists: "+id)
	if control==null: return false
	check(not control.disabled,"real native control enabled: "+id)
	if control.disabled: return false
	await click(control)
	return true
func capture(label: String) -> void:
	await frames(6); await RenderingServer.frame_post_draw
	var pixels:=root.get_texture().get_image()
	var destination:=directory+"/"+label+".png"
	check(pixels.save_png(destination)==OK,"actual GPU screenshot "+label)
	var data: Dictionary=scene.runtime.snapshot()
	data.gpu=RenderingServer.get_video_adapter_name(); data.engine=Engine.get_version_info()
	data.imageSha256=FileAccess.get_sha256(destination); data.viewport=[pixels.get_width(),pixels.get_height()]
	data.route="Actual MainScene menu, native mouse buttons, Campaign command and live bridge. Isolated slots."
	data.scope="Opening choices, real money/routes/debt, save and departure. Does not claim the complete convoy was played or all historical chapters implemented."
	data.sourceHashes={}
	for path: String in ["game/domain/mingqi/opening_story.gd","game/domain/mingqi/campaign.gd","game/domain/persistence/save_codec.gd","game/runtime/mingqi_runtime.gd","game/runtime/near_field_bridge.gd","game/ui/mingqi/mingqi_interface.gd","game/scenes/mingqi/mingqi_scene.gd","modules/contracts/navigation_contract.gd","modules/naval_simulation/encounter.gd"]:
		data.sourceHashes[path]=FileAccess.get_sha256("res://"+path)
	var file:=FileAccess.open(directory+"/"+label+".json",FileAccess.WRITE)
	check(file!=null,"actual capture metadata "+label)
	if file: file.store_string(JSON.stringify(data,"\t")); file.close()
	captures+=1
func open_story() -> void:
	await button("nav_story")
	# The harness freezes automatic processing. Run the same ordinary present
	# pass after opening a panel so the minimap follows its real visibility rule.
	scene._present(0)
	check(not scene.minimap.chart.visible,"journal presentation hides the chart instead of covering dialogue")
	var panel: Control=scene.interface.find_child("panel_story",true,false)
	if panel:
		var node: Node=panel.get_parent()
		while node:
			if node is ScrollContainer: node.scroll_vertical=0
			node=node.get_parent()
	await frames(3)
func run() -> void:
	root.unresizable=true; root.size=Vector2i(1600,900); root.content_scale_size=root.size
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var prefix:="user://tests/opening-story-capture-%s" % OS.get_process_id()
	var packed: PackedScene=load(ProjectSettings.get_setting("application/run/main_scene"))
	main=packed.instantiate(); main.router=Router.new({"dev":true,"mingqi_storage":Storage.new(prefix+"-v2.json"),"legacy_storage":Storage.new(prefix+"-v1.json",Legacy.validate_save),"settings_storage":Settings.new(prefix+"-settings.json")})
	root.add_child(main); await frames(8)
	var entry: Button=main.menu._buttons.mingqi
	main.menu._scroll.ensure_control_visible(entry); await click(entry)
	for index in 240:
		if main.current_scene: break
		await process_frame
	check(main.current_scene!=null,"actual main menu enters the 1650 adventure")
	if not main.current_scene: finish(); return
	scene=main.current_scene; scene.set_process(false); scene.set_physics_process(false)
	scene.runtime.set_pause("blur",false); scene._present(0)
	await open_story(); await capture("01-old-ledger-1600")
	var before: Dictionary=scene.runtime.snapshot().campaign
	await button("story_choice_old-ledger_settle-wages")
	var paid: Dictionary=scene.runtime.snapshot().campaign
	check(paid.captain.silver==before.captain.silver-80 and paid.reputations.crewSupport==60,"mouse choice really pays wages and changes boarding support")
	await capture("02-wages-consequence")
	await button("nav_convoy"); await button("contract_accept_convoy-001")
	var accepted: Dictionary=scene.runtime.snapshot().campaign
	check(accepted.contracts["convoy-001"].status=="active" and accepted.captain.silver==paid.captain.silver-50,"mouse acceptance loads the original actual convoy")
	await open_story(); await capture("03-pilot-choice")
	await button("story_choice_pilot-plan_hire-pilot")
	var pilot: Dictionary=scene.runtime.snapshot().campaign
	check(pilot.captain.silver==accepted.captain.silver-45,"actual pilot expense is committed once")
	for id in pilot.contracts["convoy-001"].voyageIds: check(pilot.voyages[id].routeId=="xiamen-kinmen-shallow","pilot changes actual grain route "+id)
	await capture("04-pilot-consequence")
	root.size=Vector2i(1280,720); root.content_scale_size=root.size; await frames(8)
	await open_story(); await capture("05-journal-1280")
	var amount: SpinBox=scene.interface.find_child("debt_quantity",true,false)
	check(amount!=null,"native journal exposes debt payment input")
	if amount:
		amount.value=100; await frames(2)
		await button("repay_debt")
		var debt: Dictionary=scene.runtime.snapshot().campaign
		check(debt.debt.principal==300 and debt.captain.silver==pilot.captain.silver-100,"native repayment consumes real capital and reduces principal")
		await capture("06-debt-payment-1280")
	await button("nav_convoy")
	await button("depart")
	var underway: Dictionary=scene.runtime.snapshot().campaign
	check(underway.currentPortId==null,"native departure follows the chosen plan")
	scene.interface.close_panel()
	for tick in 60:
		scene.runtime.set_pause("blur",false); scene._physics_process(1.0/60.0)
		await process_frame
	await capture("07-next-objective-at-sea")
	await open_story()
	var repayment: Button=scene.interface.find_child("repay_debt",true,false)
	check(repayment!=null and repayment.disabled,"journal at sea cannot perform port repayment")
	await capture("08-at-sea-journal")
	root.size=Vector2i(1600,900); root.content_scale_size=root.size; await frames(6)
	scene.interface.close_panel(); scene._present(0)
	await capture("09-sailing-1600")
	var mirror: WeakRef=weakref(scene.sea.world.get_ocean().get_reflection_viewport())
	scene.main_menu_requested.emit(); await frames(6)
	check(main.current_scene==null and main.menu.visible,"actual return preserves normal menu route")
	check(mirror.get_ref()==null,"scene exit frees the existing reflection owner")
	finish()
func finish() -> void:
	if main: main.queue_free()
	await frames(4)
	print("OPENING_STORY_GPU_CAPTURE_COMPLETE captures=",captures," assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
