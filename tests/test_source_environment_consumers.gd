extends SceneTree
const Sea = preload("res://game/presentation/world/naval_world_view.gd")
const Runtime = preload("res://game/runtime/mingqi_runtime.gd")
const Height = preload("res://modules/scene_engine/terrain/height_field.gd")
const Weather = preload("res://modules/environment_engine/weather_state.gd")
var assertions := 0
var failures := 0
func check(ok:bool,detail:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL environment consumers: ",detail)
func _initialize()->void:_run.call_deferred()
func _run()->void:
	var ports:Array=JSON.parse_string(FileAccess.get_file_as_string("res://game/data/mingqi_geography.json"))
	var height:=Height.new();height.configure_ports(ports)
	var runtime:=Runtime.new();runtime.configure(height.sample_height)
	var native:Dictionary=runtime.snapshot().naval
	var weather:=Weather.new();weather.configure();native.environment=weather.advance(1.0)
	native.time=1.0
	var unchanged:=native.duplicate(true)
	var view:Node3D=Sea.new();root.add_child(view)
	check(view.configure(height.sample_height,ports,runtime.sample_water_height,native,{"resolution":8,"chunk_radius":0,"vegetation":false,"island_details":false}),"formal world configures")
	check(view.world.atmosphere.diagnostics().get("sourceCallIndex",-1)==native.environment.sourceCallIndex,"full accepted weather packet reaches atmosphere")
	var actor:Node3D=view.ships.values()[0]
	check(actor.has_method("source_water_attachment"),"live model exposes original wake/bow attachment")
	check(view.get("source_shadows")!=null,"formal world owns source shadow lifecycle")
	check(view.wakes.diagnostics().get("source_routes",{}).has("scene_30"),"formal sailing uses recovered scene wake route")
	check(native==unchanged,"presentation leaves caller snapshot untouched")
	if actor.has_method("source_water_attachment"):
		var attachment:Dictionary=actor.source_water_attachment()
		check(attachment.has_all(["wake","bow","sourceToWorld","sourceResourceName"]),"native markers include source units and family")
		check(attachment.wake is Vector3 and attachment.wake.is_finite(),"marker uses actual live world pose")
		var held:RefCounted=view.wakes.take_source_state();check(held!=null,"wake history detaches without destruction");view.wakes.restore_source_state(held)
		var prior:Dictionary=view.wakes.diagnostics();view.apply_snapshot(native,[],0.0)
		check(view.wakes.diagnostics().source_updates==prior.source_updates,"paused packet preserves source wake call history")
		view.apply_settings({"quality":"high"})
		check(view.wakes.diagnostics().source_updates==prior.source_updates,"quality preserves wake history")
		check(view.world.atmosphere.diagnostics().get("sourceCallIndex",-1)==native.environment.sourceCallIndex,"quality forwards same environment history")
		native.environment=weather.advance(1.25,{"route":"battle"});native.time=1.25
		view.apply_snapshot(native,[],0.25)
		check(view.wakes.diagnostics().get("source_routes",{}).has("battle_90"),"formal battle uses original battle trail route")
		check(view.wakes.diagnostics().get("source_errors",{}).is_empty(),"actual model wake packets satisfy source contract")
		check(view.source_shadows.diagnostics().volumeCount>0,"real rigid ship geometry registers casters")
	view.dispose();view.dispose();view.free();runtime.dispose()
	await process_frame
	print("SOURCE_ENVIRONMENT_CONSUMERS_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
