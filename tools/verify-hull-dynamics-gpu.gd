extends SceneTree
## Real five-wave ocean and native sailing physics; no player-facing entry.
const Ship=preload("res://game/presentation/ships/ship_view.gd")
const Crew=preload("res://game/presentation/crew/crew_view.gd")
const Packet=preload("res://game/presentation/world/source_water_packet.gd")
const Ocean=preload("res://modules/scene_engine/ocean/projected_ocean.gd")
const Runtime=preload("res://game/runtime/sailing_runtime.gd")
var _runtime:RefCounted
var failures:Array=[]
func _initialize()->void:run.call_deferred()
func ground(_x:float,_z:float)->float:return -20.0
func water(x:float,z:float,t:float)->float:return _runtime.sample_water_height(x,z,t)
func frames(n:int)->void:for _i in n:await process_frame
func run()->void:
	var phase:="baseline";var angle:="front";var scenario:="cruise";var kind:="fuchuan";var layer:="all";var hide_hull:=false;var solid_diagnostic:=false
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):phase=arg.trim_prefix("--phase=")
		if arg.begins_with("--camera="):angle=arg.trim_prefix("--camera=")
		if arg.begins_with("--case="):scenario=arg.trim_prefix("--case=")
		if arg.begins_with("--kind="):kind=arg.trim_prefix("--kind=")
		if arg.begins_with("--layer="):layer=arg.trim_prefix("--layer=")
		if arg=="--hide-hull":hide_hull=true
		if arg=="--solid-diagnostic":solid_diagnostic=true
	var output:="res://docs/migration/evidence/hull-dynamics-2026-10-14/"+("diagnostics" if hide_hull or solid_diagnostic else "final")+"/"+phase+"/"+kind+"/"+scenario+"/"+angle+"/"+layer
	if hide_hull:output+="-hidden-hull"
	if solid_diagnostic:output+="-solid-diagnostic"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output));root.size=Vector2i(1200,900);root.content_scale_size=root.size
	var world:=Node3D.new();root.add_child(world)
	var environment:=WorldEnvironment.new();var env:=Environment.new();environment.environment=env
	env.background_mode=Environment.BG_COLOR;env.background_color=Color("87ceeb");env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("a0c8ff");env.ambient_light_energy=.65;world.add_child(environment)
	var sun:=DirectionalLight3D.new();world.add_child(sun);sun.rotation_degrees=Vector3(-60,-35,0);sun.light_energy=1.5;sun.shadow_enabled=true
	var ship:=Ship.new();world.add_child(ship);if not ship.configure(kind):printerr("SHIP CONFIG FAIL");quit(1);return
	var crew:=Crew.new();world.add_child(crew);crew.configure(kind,ship.get_model());crew.set_environment(water)
	_runtime=Runtime.new()
	if not _runtime.configure(ground,{"kind":kind,"position":{"x":0.0,"z":0.0},"heading":.45,"speed":.8 if scenario=="slow" else 3.086,"wind":{"direction":{"x":-1.0,"z":.3},"speed":14.0},"sailDeployment":.2 if scenario=="slow" else 1.0}):printerr("RUNTIME CONFIG FAIL");quit(1);return
	var camera:=Camera3D.new();world.add_child(camera);camera.current=true;camera.fov=45;camera.far=3000;camera.near=.1
	var offset:=Vector3(13,5.6,19);var focus:=Vector3(6,1.1,3.3)
	if angle=="side":offset=Vector3(25,5.5,8);focus=Vector3(0,1,0)
	elif angle=="high":offset=Vector3(23,33,20);focus=Vector3(0,1,0)
	var ocean:=Ocean.new();world.add_child(ocean)
	camera.position=offset;camera.look_at(focus)
	ocean.configure(camera,load("res://assets/textures/waternormals.jpg"),96,3000.0);ocean.set_visual_style(1);ocean.set_surface_quality("balanced")
	ocean.set_projection_padding(.18)
	ocean.enable_surface_optics(true);ocean.configure_reflection(camera)
	# Uniform carrier avoids the projected grid's near-frustum coverage limit
	# at a 22-degree waterline camera. Keep the production material, waves,
	# reflection and depth; actual game projection is observed separately.
	var validation_plane:=PlaneMesh.new();validation_plane.size=Vector2(1200,1200);validation_plane.subdivide_width=512;validation_plane.subdivide_depth=512;ocean.mesh=validation_plane
	var sky_material:ShaderMaterial=ocean.get_sky_material()
	if sky_material!=null:
		var sky:=Sky.new();sky.sky_material=sky_material;env.sky=sky;env.background_mode=Environment.BG_SKY
	var script_path:="res://docs/migration/evidence/hull-dynamics-2026-10-14/baseline-source/source_wake_renderer.gd" if phase=="baseline" else "res://modules/scene_engine/water/source_wake_renderer.gd"
	var renderer:RefCounted=load(script_path).new(world)
	var samples:Array=[];var timeline:Array=[];var max_impact:=0.0;var peak_tick:=0;var closing_min:=INF;var closing_max:=-INF;var region_readback:Array=[]
	for tick in 321:
		if tick>0:_runtime.advance(1.0/32.0)
		var snapshot:Dictionary=_runtime.snapshot();var now:=float(snapshot.time)
		if scenario=="turn":_runtime.command({"type":"turn","value":.45 if tick>=128 else 0.0})
		if scenario=="stop" and tick==128:_runtime.command({"type":"sail","value":0.0})
		var state:Dictionary=snapshot.ship.duplicate(true);state.id="player";state.time=now;state.crew=24
		if scenario=="reentry":
			# Explicit stress overlay on native physics, marked in the receipt.
			state.position.y+=2.0*smoothstep(2.0,2.5,now)*(1.0-smoothstep(3.85,4.30,now))
		ship.apply_snapshot(state,snapshot.wind,0.0);crew.global_transform=ship.get_model().global_transform;crew.apply_snapshot(state,snapshot.wind,0.0)
		ship.visible=not hide_hull;crew.visible=not hide_hull
		var p:=Vector3(float(state.position.x),float(state.position.y),float(state.position.z))
		# Name views by the actual current heading, so sails cannot turn a side
		# diagnostic into a second bow view. Aim at the lower forebody contact.
		var attachment:Dictionary=ship.source_water_attachment();var profile:Dictionary=attachment.surfaceProfile
		var local_marker:Vector3=profile.worldToHull*attachment.bow
		var first:=float(profile.sections[0].z);var last:=float(profile.sections[-1].z)
		var at_first:=absf(local_marker.z-first)<absf(local_marker.z-last)
		var sign_forward:=-1.0 if at_first else 1.0
		var forward:Vector3=profile.hullToWorld.basis.z*sign_forward;forward.y=0.0;forward=forward.normalized()
		var right:=Vector3(-forward.z,0.0,forward.x)
		var near_bow:Vector3=profile.hullToWorld*Vector3(0.0,0.0,(first if at_first else last)-sign_forward*.8/profile.hullToWorld.basis.z.length())
		near_bow.y=water(near_bow.x,near_bow.z,now)+.08
		if angle=="side":offset=right*10.0+forward*2.0+Vector3.UP*4.0
		elif angle=="high":offset=right*15.0+Vector3.UP*25.0
		else:offset=forward*12.0+right*2.0+Vector3.UP*4.0
		camera.position=near_bow+offset;camera.look_at(near_bow)
		ocean.position=Vector3(near_bow.x,0.0,near_bow.z)
		ocean.set_simulation_time(now)
		var native:=Packet.compose({"time":now,"environment":{"acceptedTime":now,"sourceCallIndex":tick,"route":"sailing","epoch":0},"ships":[state]},{"player":ship},camera)
		renderer.apply_snapshot(native,water,Callable())
		if solid_diagnostic and tick==0:
			for carrier:String in ["FlowPort","FlowStarboard"]:
				var material:ShaderMaterial=renderer._actors.player.froth._nodes[carrier].material_override
				var shader:=Shader.new()
				shader.code=material.shader.code.replace("ALBEDO=mix(vec3(0.60,0.80,0.86),vec3(0.88,0.96,0.98),fine);","ALBEDO=vec3(1.0,0.0,1.0);").replace("clamp(foam*cross_fade*COLOR.a*strength*(1.0+turn_bias),0.0,0.74)","1.0")
				material.shader=shader
		var detail:Dictionary=renderer._actors.player.froth.diagnostics()
		var impact:=float(detail.get("impact_strength",0.0));var closing:=float(detail.get("closing_speed",0.0))
		var new_peak:bool=phase=="candidate" and impact>max_impact and impact>.01
		if impact>max_impact:max_impact=impact;peak_tick=tick
		closing_min=minf(closing_min,closing);closing_max=maxf(closing_max,closing)
		timeline.append({"tick":tick,"time":now,"speed":Vector2(state.velocity.x,state.velocity.z).length(),"y":p.y,"pitch":state.pitch,"heel":state.heel,"impact":impact,"closing":closing,"gap":renderer._actors.player.froth.get("_last_gap") if phase=="candidate" else null,"turnBias":detail.get("turn_bias",0.0),"droplets":detail.target_droplets,"waterSamples":detail.water_samples,"detail":detail.get("detail_level","baseline")})
		if tick%8==0:await process_frame
		if new_peak or tick in [64,72,80,88,96,128,136,144,152,160,192,256,320]:
			for node:Node in renderer._actors.player.node.find_children("*","MeshInstance3D",true,false):
				var name:=str(node.name)
				if layer!="all":node.visible=node.visible and ((layer=="foam" and name.begins_with("Flow")) or (layer=="spray" and name=="ContactSpray"))
			await frames(3);await RenderingServer.frame_post_draw
			var name:="t%03d.png"%tick;var image:=root.get_texture().get_image();image.save_png(output+"/"+name)
			samples.append({"tick":tick,"time":now,"image":name,"state":state,"contact":detail,"ocean":ocean.get_projection_work_diagnostics()})
			if phase=="candidate":
				for carrier:String in ["FlowPort","FlowStarboard","ContactSpray"]:
					var contact:RefCounted=renderer._actors.player.froth
					var node:MeshInstance3D=contact._nodes[carrier]
					if node.mesh.get_surface_count()==0:continue
					var vertices:PackedVector3Array=node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
					var expected:PackedVector3Array=contact._buffers[carrier].vertices
					var maximum:=0.0
					if vertices.size()!=expected.size():maximum=INF
					else:
						for i in vertices.size():maximum=maxf(maximum,vertices[i].distance_to(expected[i]))
					var attrs:Array=node.mesh.surface_get_arrays(0)
					var uv:PackedVector2Array=attrs[Mesh.ARRAY_TEX_UV];var colors:PackedColorArray=attrs[Mesh.ARRAY_COLOR]
					var uv_error:=0.0;var alpha_error:=0.0;var max_alpha:=0.0
					for i in uv.size():uv_error=maxf(uv_error,uv[i].distance_to(contact._buffers[carrier].uv[i]))
					for i in colors.size():alpha_error=maxf(alpha_error,absf(colors[i].a-contact._buffers[carrier].colors[i].a));max_alpha=maxf(max_alpha,colors[i].a)
					region_readback.append({"tick":tick,"carrier":carrier,"visible":node.visible,"submittedIndices":attrs[Mesh.ARRAY_INDEX].size(),"maximumError":maximum,"UVerror":uv_error,"alphaError":alpha_error,"maximumAlpha":max_alpha,"regionSupported":contact._buffers[carrier].supported})
	# For a dynamic candidate keep an explicit link to the maximum sampled pulse.
	if phase=="candidate" and scenario=="reentry" and max_impact<.5:failures.append("No strong relative-entry response observed in explicit reentry stress")
	var report:={"phase":phase,"case":scenario,"kind":kind,"camera":angle,"layer":layer,"hiddenHullDiagnostic":hide_hull,"carrier":"uniform 1200m PlaneMesh 512 subdivisions; unchanged production Ocean material/waves/optics/depth","failures":failures,"maximumImpact":max_impact,"peakTick":peak_tick,"closingMin":closing_min,"closingMax":closing_max,"samples":samples,"timeline":timeline,"regionReadback":region_readback,"scope":"Production five-wave Ocean MATERIAL on a uniform validation carrier plus native SailingRuntime physics and real Ship/Crew/WaterPacket/wake renderer; deep open water. Uniform carrier avoids existing projected-grid near-frustum gaps at low waterline views; normal game projection is separately observed through the actual entry. Reentry case adds an explicit 2m lift overlay, others use native physics poses. Hidden hull/solid material are diagnostic variants only. This is controlled GPU evidence, not live-input or full-game FPS proof."}
	var file:=FileAccess.open(output+"/VERIFICATION.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	renderer.dispose();crew.dispose();ship.dispose();world.free();await frames(2)
	print("HULL_DYNAMICS_GPU phase=",phase," case=",scenario," kind=",kind," maximumImpact=",max_impact," failures=",failures.size());quit(0 if failures.is_empty() else 1)
