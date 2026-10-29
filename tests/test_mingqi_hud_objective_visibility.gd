extends SceneTree
## Reproduce the actual opening -> accept -> depart HUD with native Controls.
const Runtime=preload("res://game/runtime/mingqi_runtime.gd")
const Interface=preload("res://game/ui/mingqi/mingqi_interface.gd")
var assertions:=0
var failures:=0
var intents:Array=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,detail:String)->bool:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL objective HUD: ",detail)
	return ok
func settle()->void:
	for frame in 8:await process_frame
func inside(control:Control,bounds:Rect2)->bool:
	var box:=control.get_global_rect()
	return box.position.x>=bounds.position.x-1 and box.position.y>=bounds.position.y-1 and box.end.x<=bounds.end.x+1 and box.end.y<=bounds.end.y+1
func click(point:Vector2)->void:
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT
		event.position=point;event.global_position=point;event.pressed=pressed
		Input.parse_input_event(event);await process_frame
func inspect(ui:Node,packet:Dictionary,viewport:Vector2i,at_sea:bool)->void:
	root.size=viewport;root.content_scale_size=Vector2i.ZERO
	ui.apply_snapshot(packet);ui.close_panel();await settle()
	var scroll:=ui.find_child("hud_scroll",true,false) as ScrollContainer
	var hud:=ui.find_child("hud",true,false) as Control
	var dock:=ui.find_child("command_dock",true,false) as Control
	var text:=ui.find_child("current_objective",true,false) as Label
	var button:=ui.find_child("objective_open",true,false) as Button
	var broadside:=ui.find_child("broadside_status",true,false) as Label
	var expected:=str(packet.story.get("objective",{}).get("title",""))
	if not check(scroll!=null and hud!=null and dock!=null and text!=null and button!=null and broadside!=null,"HUD nodes exist"):return
	check(not expected.is_empty() and text.text.contains(expected) and text.is_visible_in_tree(),"actual projected objective visible at %s sea=%s"%[viewport,at_sea])
	check(inside(text,scroll.get_global_rect()),"objective text entirely in HUD scroll viewport at %s sea=%s text=%s scroll=%s"%[viewport,at_sea,text.get_global_rect(),scroll.get_global_rect()])
	check(inside(button,scroll.get_global_rect()),"objective button entirely in HUD scroll viewport at %s sea=%s button=%s scroll=%s"%[viewport,at_sea,button.get_global_rect(),scroll.get_global_rect()])
	check(hud.get_global_rect().end.y<dock.get_global_rect().position.y,"HUD does not collide with command dock at %s"%viewport)
	check(hud.size.x<=370 and (viewport.x<600 or hud.size.y<=330),"HUD remains bounded and leaves sea visible")
	check(ui.get("_screen").mouse_filter==Control.MOUSE_FILTER_IGNORE,"clear sea input passes through")
	check(broadside.is_visible_in_tree()==at_sea,"actual at-sea broadside appears only after depart")
	if at_sea and viewport.x>=600:check(inside(broadside,scroll.get_global_rect()),"both broadside lines entirely visible at %s"%viewport)
	if inside(button,scroll.get_global_rect()) and not button.disabled:
		await click(button.get_global_rect().get_center());await settle()
		check(ui.is_panel_open(),"native click on visible objective opens its page")
		check(ui.get("_panel")==str(packet.story.objective.panel),"objective click opens the projected target page")
		check(intents.is_empty(),"objective navigation emits no simulation command")
		ui.close_panel()
func run()->void:
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,720)
	var runtime:=Runtime.new()
	if not check(runtime.configure(func(_x:float,_z:float)->float:return -24.0).ok,"actual Mingqi opening configures"):quit(1);return
	var ui:=Interface.new();root.add_child(ui)
	ui.command_requested.connect(func(intent):intents.append(intent))
	var port:Dictionary=runtime.snapshot()
	check(port.campaign.currentPortId!=null,"opening packet is docked")
	for viewport:Vector2i in [Vector2i(1600,900),Vector2i(1280,720),Vector2i(320,480)]:await inspect(ui,port,viewport,false)
	var packet:Dictionary=runtime.snapshot()
	check(runtime.command({"type":"accept-convoy","contractId":"convoy-001","commandId":"hud-accept","expectedRevision":packet.campaign.revision}).ok,"actual convoy accepted")
	packet=runtime.snapshot()
	check(runtime.command({"type":"depart","commandId":"hud-depart","expectedRevision":packet.campaign.revision}).ok,"actual convoy departs")
	packet=runtime.snapshot()
	check(packet.campaign.currentPortId==null and not packet.naval.ships.is_empty(),"sea packet includes real naval ships")
	for viewport:Vector2i in [Vector2i(1600,900),Vector2i(1280,720),Vector2i(320,480)]:await inspect(ui,packet,viewport,true)
	# A later shipped narrative objective, substituted into the live packet to
	# test its longer caption at the narrow viewport without simulating a voyage.
	var long_packet:=packet.duplicate(true)
	long_packet.story.objective.title="核对第二趟的船上账册"
	await inspect(ui,long_packet,Vector2i(320,480),true)
	var no_objective:=packet.duplicate(true);no_objective.story.objective={}
	ui.apply_snapshot(no_objective);await settle()
	check(not ui.find_child("objective_row",true,false).visible,"empty objective hides action row")
	ui.apply_snapshot(packet);await settle()
	var manual:=ui.find_child("sailing_manual",true,false) as Button
	manual.pressed.emit();await settle()
	var scroll:=ui.find_child("hud_scroll",true,false) as ScrollContainer
	var keys:=ui.find_child("keys",true,false) as Control
	scroll.ensure_control_visible(keys);await settle()
	var position:=scroll.scroll_vertical
	check(position>0,"manual details remain reachable by HUD scrolling")
	ui.apply_snapshot(packet);await settle()
	check(scroll.scroll_vertical==position,"snapshot update preserves the user's deliberate HUD scroll")
	manual.pressed.emit();await settle()
	check(not keys.visible and intents.is_empty(),"manual closes locally without business intent")
	ui.free();runtime.dispose();await process_frame
	print("MINGQI_OBJECTIVE_HUD assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
