extends SceneTree
# Frozen source geometry oracle. Ordinary/default hero entry remains covered separately.
const Reference=preload("res://modules/scene_engine/assets/ship_model_provider.gd")
const Sea = preload("res://game/presentation/world/naval_world_view.gd")
const Runtime = preload("res://game/runtime/mingqi_runtime.gd")
const Height = preload("res://modules/scene_engine/terrain/height_field.gd")
const Ship = preload("res://game/presentation/ships/ship_view.gd")
const WaterPacket = preload("res://game/presentation/world/source_water_packet.gd")
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
	for reason in runtime.presentation_pause_reasons():runtime.set_pause(reason,false)
	for i in 4:runtime.advance(0.25)
	var native:Dictionary=runtime.snapshot().naval
	var unchanged:=native.duplicate(true)
	var view:Node3D=Sea.new();root.add_child(view)
	check(view.configure(height.sample_height,ports,runtime.sample_water_height,native,{"resolution":8,"chunk_radius":0,"vegetation":false,"island_details":false}),"formal world configures")
	check(view.world.atmosphere.diagnostics().get("environmentRevision",-1)==native.environment.revision,"full accepted weather packet reaches atmosphere")
	var actor:Node3D=view.ships.values()[0]
	check(actor.has_method("source_water_attachment"),"live model exposes original wake/bow attachment")
	check(view.get("source_shadows")!=null,"formal world owns source shadow lifecycle")
	check(view.has_method("source_shadow_status"),"formal world diagnoses stencil availability and shadow-map fallback")
	if view.has_method("source_shadow_status"):
		check(view.source_shadow_status().presentationMode=="target_shadow_maps_fallback","headless uses explicit native shadow-map fallback")
	check(view.wakes.diagnostics().get("source_routes",{}).has("scene_30"),"formal sailing uses recovered scene wake route")
	check(native==unchanged,"presentation leaves caller snapshot untouched")
	if actor.has_method("source_water_attachment"):
		var attachment:Dictionary=actor.source_water_attachment()
		check(attachment.has_all(["wake","bow","sourceToWorld","sourceResourceName"]),"native markers include source units and family")
		check(attachment.wake is Vector3 and attachment.wake.is_finite(),"marker uses actual live world pose")
		var target:Dictionary=native.environment.lighting.target
		var sun:DirectionalLight3D=view.get("_sun")
		check(is_equal_approx(sun.light_energy,target.energy),"real directional light consumes source target energy")
		check((view.world.get_ocean().material_override as ShaderMaterial).get_shader_parameter("sun_position").normalized().is_equal_approx(Vector3(target.direction[0],target.direction[1],target.direction[2]).normalized()),"water receives same light direction without replacing blue water profile")
		var shadow_before:Dictionary=view.source_shadows.diagnostics()
		var held:RefCounted=view.wakes.take_source_state();check(held!=null,"wake history detaches without destruction");view.wakes.restore_source_state(held)
		var prior:Dictionary=view.wakes.diagnostics();view.apply_snapshot(native,[],0.0)
		check(view.wakes.diagnostics().source_updates==prior.source_updates,"paused packet preserves source wake call history")
		check(view.source_shadows.diagnostics().rebuildCount==shadow_before.rebuildCount,"paused actual rigid casters reuse source volume geometry")
		view.apply_settings({"quality":"high"})
		check(view.wakes.diagnostics().source_updates==prior.source_updates,"quality preserves wake history")
		check(view.world.atmosphere.diagnostics().get("environmentRevision",-1)==native.environment.revision,"quality forwards same environment history")
		check(is_equal_approx(sun.light_energy,target.energy),"quality rebind retains authoritative source lighting")
		runtime.advance(0.25);native=runtime.snapshot().naval
		# Exercise consumer route selection with an otherwise actual accepted packet.
		native.environment.route="battle"
		view.apply_snapshot(native,[],0.25)
		check(view.wakes.diagnostics().get("source_routes",{}).has("battle_90"),"formal battle uses original battle trail route")
		check(view.wakes.diagnostics().get("source_errors",{}).is_empty(),"actual model wake packets satisfy source contract")
		check(view.source_shadows.diagnostics().volumeCount>0,"real rigid ship geometry registers casters")
		check(view.get("_rigid_casters").diagnostics().errors.is_empty(),"actual hull and mast casters satisfy finite index scope")
		view.apply_settings({"quality":"low"})
		check(view.source_shadows.diagnostics().volumeCount==0,"paused low quality unregisters stencil without waiting for another snapshot")
		view.apply_settings({"quality":"balanced"})
		check(view.source_shadows.diagnostics().volumeCount>0,"paused restored quality registers current rigid casters")
		native.ships=[];view.apply_snapshot(native,[],0.0)
		check(view.source_shadows.diagnostics().volumeCount==0,"removed fleet unregisters all rigid volumes")
		check(view.wakes.diagnostics().get("source_routes",{}).is_empty(),"removed fleet releases source wake actors")
	view.dispose();view.dispose();view.free();runtime.dispose()
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/fidelity_naval/ships-manifest.json"))
	for kind:String in Ship.KINDS:
		var marker_actor:=Ship.new();root.add_child(marker_actor);check(marker_actor.configure(kind,null,Reference.new()),kind+" actual model configures")
		marker_actor.position=Vector3(123,4,-57);marker_actor.rotation=Vector3(0.1,0.7,-0.05)
		var attachment:Dictionary=marker_actor.source_water_attachment()
		var entry:Dictionary=manifest.mappings[kind]
		var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(entry.sourceJsonPath))
		for node:Dictionary in source.nativeNodes.lowend:
			if str(node.name).to_lower() not in ["dummy_wake","dummy_bowfroth"]:continue
			var point:Array=node.worldOrigin
			var expected:Vector3=marker_actor.get_model().global_transform*(Vector3(point[0],point[2],-point[1])*float(entry.uniformScale))
			var role:="wake" if str(node.name).to_lower()=="dummy_wake" else "bow"
			check(attachment[role].is_equal_approx(expected),kind+" "+role+" uses original native worldOrigin and manifest uniformScale")
		var input:={"time":1.0,"environment":{"route":"sailing","epoch":1,"sourceCallIndex":32},"ships":[{"id":"marker","hull":100,"sailDeployment":1.0,"visual":{"velocity":{"x":3.0,"z":0.0}}}]}
		var packet:Dictionary=WaterPacket.compose(input,{"marker":marker_actor},null).ships[0].sourceWake
		check(packet.sourceToWorld==entry.uniformScale and packet.modelScale==1.0,kind+" keeps source root scale separate from baked importer scale")
		check(packet.froth.enabled and not packet.froth.has("sourceSidePosition"),kind+" shared bow marker follows original attachment contract")
		input.ships[0].hull=0;check(not WaterPacket.compose(input,{"marker":marker_actor},null).ships[0].sourceWake.froth.enabled,kind+" sunk policy disables attached froth")
		marker_actor.dispose();marker_actor.free()
	await process_frame
	print("SOURCE_ENVIRONMENT_CONSUMERS_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
