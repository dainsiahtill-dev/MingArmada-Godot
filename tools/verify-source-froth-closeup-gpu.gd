extends SceneTree
## Diagnostic actual-model/production-packet GPU regression. No player entry.
## --phase=before reproduces the frozen UV-only and over-wide carrier symptom;
## --phase=after verifies the current production implementation.
const Ship=preload("res://game/presentation/ships/ship_view.gd")
const Crew=preload("res://game/presentation/crew/crew_view.gd")
const Packet=preload("res://game/presentation/world/source_water_packet.gd")
var failures:Array=[]
func _initialize()->void:run.call_deferred()
func water(_x:float,_z:float,_time:float)->float:return 0.0
func frames(n:int)->void:for _i in n:await process_frame
func run()->void:
	var phase:="after"
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):phase=arg.trim_prefix("--phase=")
	var output:="res://docs/migration/evidence/froth-closeup-2026-10-14/"+phase
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output));root.size=Vector2i(1200,900);root.content_scale_size=Vector2i(1200,900)
	var world:=Node3D.new();root.add_child(world)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.01,.27,.46);environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.55;world.add_child(environment)
	var sun:=DirectionalLight3D.new();world.add_child(sun);sun.rotation_degrees=Vector3(-60,-35,0);sun.light_energy=1.0
	var ship:=Ship.new();world.add_child(ship);if not ship.configure("fuchuan"):printerr("SHIP CONFIG FAIL");quit(1);return
	var state:={"id":"player","kind":"fuchuan","name":"定海","time":0.0,"hull":100.0,"maxHull":100.0,"sail":100.0,"maxSail":100.0,"crew":24,"sailDeployment":1.0,"visual":{"position":{"x":0.0,"y":0.0,"z":0.0},"heading":.45,"velocity":{"x":3.0,"z":0.0},"pitch":0.0,"heel":0.0}}
	ship.apply_snapshot(state,{"speed":14.0,"direction":{"x":-1.0,"y":0.0}},0.0)
	var crew:=Crew.new();world.add_child(crew);crew.global_transform=ship.get_model().global_transform;crew.configure("fuchuan",ship.get_model());crew.apply_snapshot(state,{},0.0)
	var camera:=Camera3D.new();world.add_child(camera);camera.fov=45.0;camera.position=Vector3(23,33,20);camera.look_at(Vector3(0,1,0));camera.current=true
	var mesh:=PlaneMesh.new();mesh.size=Vector2(1000,1000);var sea:=MeshInstance3D.new();sea.mesh=mesh;world.add_child(sea);sea.position.y=-.1
	var mat:=ShaderMaterial.new();var shader:=Shader.new();shader.code="shader_type spatial;render_mode unshaded;void fragment(){ALBEDO=vec3(.02,.25,.42);}";mat.shader=shader;sea.material_override=mat
	var impl:Script=load("res://docs/migration/evidence/froth-closeup-2026-10-14/baseline/source_froth.gd") if phase=="before" else load("res://modules/scene_engine/water/source_froth.gd")
	var froth:RefCounted=impl.new();froth.configure(world,3,17)
	var images:Array=[];var samples:Array=[];var footprint_pixels:=0
	for now:float in [0.0,24.0,26.0,27.0,30.0,31.0]:
		var native:={"time":now,"environment":{"acceptedTime":now,"sourceCallIndex":int(now*32),"route":"sailing"},"ships":[state]}
		var packet:Dictionary=Packet.compose(native,{"player":ship},camera).ships[0].sourceWake
		var attached:=packet.duplicate();attached.merge(packet.froth,true);froth.apply_snapshot(attached,now,water,Callable())
		# Isolate the reported side sheet; no particle/ship pose/water animation
		# can create a false positive in the temporal texture check.
		for key:String in froth._surface.nodes:froth._surface.nodes[key].visible=key.begins_with("side_")
		await frames(4);await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image();image.save_png(output+"/t%02d.png"%int(now));images.append(image)
		samples.append({"time":now,"sideUV":Array(froth.diagnostics().side_uv),"packet":packet.froth,"diagnostics":froth.diagnostics()})
		if now==24.0:
			ship.visible=false;crew.visible=false;await frames(4);await RenderingServer.frame_post_draw
			var mask:=root.get_texture().get_image();mask.save_png(output+"/t24-foam-only.png")
			for y in range(0,mask.get_height(),2):
				for x in range(0,mask.get_width(),2):
					var pixel:=mask.get_pixel(x,y)
					if pixel.r>.6 and pixel.g>.7 and pixel.b>.75:footprint_pixels+=1
			ship.visible=true;crew.visible=true
	var a:Image=images[-2];var b:Image=images[-1];var changed:=0;var mean:=0.0
	for y in range(0,a.get_height(),2):
		for x in range(0,a.get_width(),2):
			var ca:=a.get_pixel(x,y);var cb:=b.get_pixel(x,y);var difference:=absf(ca.r-cb.r)+absf(ca.g-cb.g)+absf(ca.b-cb.b);mean+=difference
			if difference>.03:changed+=1
	if changed<100:failures.append("side foam texture freezes after 25s on actual GPU")
	if phase=="after":
		var baseline:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/migration/evidence/froth-closeup-2026-10-14/before/VERIFICATION.json"))
		if footprint_pixels>int(baseline.get("footprintPixels",0))*.65:failures.append("attached side foam still covers too much sea at the same source texture phase")
	var report:={"failures":failures,"changedPixels":changed,"differenceSum":mean,"footprintPixels":footprint_pixels,"samples":samples,"scope":"Actual source model and production packet/froth, fixed pose and flat sea; same24s source texture phase for footprint, after25s temporal motion. Not FPS/original GPU parity."};var file:=FileAccess.open(output+"/VERIFICATION.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	froth.dispose();crew.dispose();ship.dispose();world.free();await frames(2);print("FROTH_CLOSEUP_GPU failures=",failures.size()," changedPixels=",changed);quit(0 if failures.is_empty() else 1)
