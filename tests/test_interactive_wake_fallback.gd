extends SceneTree
const Wakes = preload("res://game/presentation/water/wake_trails.gd")
var assertions := 0
var failures := 0
var _sea_wet := true
func _initialize() -> void: run.call_deferred()
func check(value: bool,reason: String) -> void:
	assertions+=1
	if not value:failures+=1;printerr("FAIL field fallback: ",reason)
func packet(index: int) -> Dictionary:
	return {"time":index*.1,"wake":{"route":"scene_30","epoch":1,"sourceCallIndex":index},"ships":[{"id":"ship","hull":100.0,"sourceWake":{"route":"scene_30","sourceCallIndex":index,"sourceClock":index*.1,"sourcePosition":[100+index*4,100,0],"markerId":"Dummy_Wake","modelScale":.1,"sourceToWorld":.01,"froth":{"family":0,"seed":7,"controllerAppTime":index*.1,"sourceBowPosition":[120+index*4,100,0],"enabled":true}}}]}
func run() -> void:
	var wakes := Wakes.new();root.add_child(wakes)
	wakes.configure(func(_x,_z,_t):return .35)
	check(wakes.has_method("set_interactive_coverage"),"production route exposes field coverage selection")
	if failures:wakes.free();finish();return
	for index in 60:wakes.apply_snapshot(packet(index))
	var source: RefCounted=wakes.get("_source_wakes")
	var actor: Dictionary=source.get("_actors").ship
	var strip: MeshInstance3D=actor.surface.nodes.SceneStrip
	var before: Dictionary=wakes.diagnostics()
	var froth: RefCounted=actor.froth
	check(strip.visible,"original baseline visible before valid field")
	wakes.call("set_interactive_coverage",["ship"])
	check(not strip.visible,"only covered original tail is hidden")
	check(wakes.diagnostics().source_updates==before.source_updates and actor.froth==froth,"selection retains source history and local froth")
	wakes.apply_snapshot(packet(60));wakes.call("set_interactive_coverage",["ship"])
	check(not strip.visible and wakes.diagnostics().source_updates==61,"hidden original history continues advancing")
	wakes.call("set_interactive_coverage",[])
	check(strip.visible,"pending/error/field exit restores baseline")
	wakes.call("set_interactive_coverage",["missing"])
	check(strip.visible,"distant or absent ID cannot suppress this ship")
	var battle:=packet(61);battle.wake.route="battle_90";battle.ships[0].sourceWake.route="battle_90"
	battle.ships[0].sourceWake.battle={"type":0,"tick":7,"x":8000,"y":4000,"heading":0,"map_origin_x":100,"map_origin_y":100,"sine_boundary":0,"hold_history":false}
	wakes.apply_snapshot(battle)
	actor=source.get("_actors").ship
	wakes.call("set_interactive_coverage",["ship"])
	var hidden:=0
	for key: String in actor.surface.nodes:
		if key.begins_with("BattleDraw_") and not actor.surface.nodes[key].visible:hidden+=1
	check(hidden==21,"all selected battle tail layers hidden together")
	wakes.call("set_interactive_coverage",[])
	var restored:=0
	for key: String in actor.surface.nodes:
		if key.begins_with("BattleDraw_") and actor.surface.nodes[key].visible:restored+=1
	check(restored==21,"battle source draw layers recover intact")
	wakes.dispose();wakes.free()
	coastal_fallback("scene_30")
	coastal_fallback("battle_90")
	flow_and_coverage()
	finish()

func route_packet(index: int,route: String) -> Dictionary:
	var value:=packet(index)
	value.wake.route=route;value.ships[0].sourceWake.route=route
	if route=="battle_90":
		value.ships[0].sourceWake.battle={"type":0,"tick":index+7,"x":8000+index*4,"y":4000,"heading":0,"map_origin_x":100,"map_origin_y":100,"sine_boundary":0,"hold_history":false}
	return value

func sea(_x: float,_z: float) -> bool:return _sea_wet

func visible_tails(actor: Dictionary) -> int:
	var count:=0
	for key: String in actor.surface.nodes:
		if (key=="SceneStrip" or key.begins_with("BattleDraw_")) and actor.surface.nodes[key].visible:count+=1
	return count

func coastal_fallback(route: String) -> void:
	_sea_wet=true
	var wakes:=Wakes.new();root.add_child(wakes)
	wakes.configure(func(_x,_z,_t):return .35);wakes.configure_surface_filter(sea)
	for index in 60:wakes.apply_snapshot(route_packet(index,route))
	var source: RefCounted=wakes.get("_source_wakes")
	var actor: Dictionary=source.get("_actors").ship
	var expected:=1 if route=="scene_30" else 21
	check(visible_tails(actor)==expected,route+": real wet source geometry starts visible")
	var meshes: Dictionary={}
	for key: String in actor.surface.nodes:meshes[key]=actor.surface.nodes[key].mesh
	_sea_wet=false
	wakes.apply_snapshot(route_packet(60,route))
	check(visible_tails(actor)==0,route+": actual sea clipping produces no visible current submission")
	var retained:=true
	for key: String in meshes:retained=retained and actor.surface.nodes[key].mesh==meshes[key]
	check(retained,route+": empty submission intentionally keeps the old cached GPU mesh")
	wakes.set_interactive_coverage([])
	check(visible_tails(actor)==0,route+": releasing coverage must not resurrect sea-clipped cached triangles")
	wakes.set_interactive_coverage(["ship"]);wakes.set_interactive_coverage([])
	check(visible_tails(actor)==0,route+": coverage round trip cannot replace current source eligibility")
	wakes.apply_snapshot(route_packet(60,route));wakes.set_interactive_coverage([])
	check(visible_tails(actor)==0,route+": repeated source call retains dry current eligibility")
	_sea_wet=true
	wakes.apply_snapshot(route_packet(61,route));wakes.set_interactive_coverage([])
	check(visible_tails(actor)==expected,route+": new wet submission restores source tail normally")
	wakes.set_interactive_coverage(["ship"])
	wakes.apply_snapshot(route_packet(61,route))
	check(visible_tails(actor)==0,route+": duplicate source snapshot preserves active external suppression")
	wakes.apply_snapshot(route_packet(62,route))
	check(visible_tails(actor)==0,route+": fresh source geometry also preserves active external suppression")
	wakes.set_interactive_coverage([])
	check(visible_tails(actor)==expected,route+": releasing suppression restores eligible current geometry")
	# Surface's normal unused-node path also hides retained geometry.
	actor.surface.hide_unused({})
	wakes.set_interactive_coverage([])
	check(visible_tails(actor)==0,route+": unused source surfaces stay hidden when coverage releases")
	wakes.apply_snapshot(route_packet(63,route))
	check(visible_tails(actor)==expected,route+": a later submission re-enables an unused surface")
	wakes.dispose();wakes.free()

func flow_and_coverage() -> void:
	_sea_wet=true
	var wakes:=Wakes.new();root.add_child(wakes)
	wakes.configure(func(_x,_z,_t):return .35);wakes.configure_surface_filter(sea)
	for index in 60:wakes.apply_snapshot(packet(index))
	var source: RefCounted=wakes.get("_source_wakes")
	var actor: Dictionary=source.get("_actors").ship
	var candidate:=packet(60)
	candidate.ships[0].sourceWake.targetTrail={"enabled":true,"position":Vector3(0,0,-3),"forward":Vector3(0,0,-1),"speed":4.8,"beam":9.0,"length":32.0,"hullAlive":true}
	wakes.set_interactive_coverage(["ship"]);wakes.apply_snapshot(candidate)
	check(actor.flow!=null and visible_tails(actor)==0,"target flow and external coverage both suppress source strip")
	wakes.apply_snapshot(packet(60))
	check(actor.flow==null and visible_tails(actor)==0,"same-call flow disable cannot release external coverage")
	wakes.set_interactive_coverage([])
	check(visible_tails(actor)==1,"flow-disabled eligible strip returns when external coverage releases")
	wakes.apply_snapshot(candidate);wakes.set_interactive_coverage([])
	check(visible_tails(actor)==0,"coverage release cannot bypass an enabled target flow")
	_sea_wet=false
	var dry:=packet(61);dry.ships[0].sourceWake.targetTrail=candidate.ships[0].sourceWake.targetTrail.duplicate()
	wakes.apply_snapshot(dry);wakes.apply_snapshot(packet(61));wakes.set_interactive_coverage([])
	check(actor.flow==null and visible_tails(actor)==0,"dry source submission remains hidden after same-call flow disable")
	_sea_wet=true;wakes.apply_snapshot(packet(62));wakes.set_interactive_coverage([])
	check(visible_tails(actor)==1,"wet geometry returns after flow and coverage are both released")
	wakes.dispose();wakes.free()
func finish() -> void:
	print("INTERACTIVE_WAKE_FALLBACK_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
