extends SceneTree
## Production route with real model/crew. This camera probe has no game menu.
const Ship=preload("res://game/presentation/ships/ship_view.gd")
const Crew=preload("res://game/presentation/crew/crew_view.gd")
const Packet=preload("res://game/presentation/world/source_water_packet.gd")
var failures:Array=[]
func _initialize()->void:run.call_deferred()
func water(_x:float,_z:float,_t:float)->float:return 0.0
func frames(n:int)->void:for _i in n:await process_frame
func run()->void:
	var phase:="before";var angle:="low-front";var layer:="all";var speed:=3.086;var heave:=false;var isolated:=false
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):phase=arg.trim_prefix("--phase=")
		if arg.begins_with("--camera="):angle=arg.trim_prefix("--camera=")
		if arg.begins_with("--layer="):layer=arg.trim_prefix("--layer=")
		if arg.begins_with("--speed="):speed=float(arg.trim_prefix("--speed="))
		if arg=="--heave":heave=true
		if arg=="--isolated":isolated=true
	var output:="res://docs/migration/evidence/hull-contact-redesign-2026-10-14/"+phase+"/"+angle+("-heave" if heave else "")+"/"+layer+("-isolated" if isolated else "")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size=Vector2i(1200,900);root.content_scale_size=root.size
	var world:=Node3D.new();root.add_child(world)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.01,.27,.46);environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.55;world.add_child(environment)
	var sun:=DirectionalLight3D.new();world.add_child(sun);sun.rotation_degrees=Vector3(-60,-35,0)
	var ship:=Ship.new();world.add_child(ship);if not ship.configure("fuchuan"):printerr("SHIP CONFIG FAIL");quit(1);return
	var crew:=Crew.new();world.add_child(crew);crew.configure("fuchuan",ship.get_model())
	var camera:=Camera3D.new();world.add_child(camera);camera.fov=45.0;camera.current=true
	var offset:=Vector3(13,5.6,19);var focus:=Vector3(6.0,1.1,3.3)
	if angle=="low-side":offset=Vector3(25,5.5,8);focus=Vector3(0,1,0)
	elif angle=="high":offset=Vector3(23,33,20);focus=Vector3(0,1,0)
	var mesh:=PlaneMesh.new();mesh.size=Vector2(1000,1000)
	var ocean:=MeshInstance3D.new();world.add_child(ocean);ocean.mesh=mesh
	var mat:=ShaderMaterial.new();var shader:=Shader.new()
	shader.code="shader_type spatial; render_mode unshaded,depth_draw_always; varying vec2 pos; void vertex(){pos=VERTEX.xz;} void fragment(){ float n=sin(pos.x*1.3+pos.y*0.37)*sin(pos.y*0.86)*0.007; ALBEDO=vec3(.025,.27,.43)+n; ALPHA=1.0;}"
	mat.shader=shader;mat.render_priority=1;ocean.material_override=mat
	var renderer:RefCounted=(load("res://docs/migration/evidence/hull-contact-redesign-2026-10-14/baseline-source/source_wake_renderer.gd") if phase=="before" else load("res://modules/scene_engine/water/source_wake_renderer.gd")).new(world)
	var samples:Array=[];var images:Array=[]
	for tick in 257:
		var now:=float(tick)/32.0
		var position:=Vector3(cos(.45),0,sin(.45))*speed*now
		var float_y:=.45*sin(now*2.7) if heave else 0.0
		var state:={"id":"player","kind":"fuchuan","name":"定海","time":now,"hull":100.0,"maxHull":100.0,"sail":100.0,"maxSail":100.0,"crew":24,"sailDeployment":1.0,"visual":{"position":{"x":position.x,"y":float_y,"z":position.z},"heading":.45,"velocity":{"x":cos(.45)*speed,"z":sin(.45)*speed},"pitch":.10*sin(now*1.9) if heave else 0.0,"heel":.14*cos(now*1.3) if heave else 0.0}}
		ship.apply_snapshot(state,{},0.0);crew.global_transform=ship.get_model().global_transform;crew.apply_snapshot(state,{},0.0)
		camera.position=position+offset;camera.look_at(position+focus)
		var native:=Packet.compose({"time":now,"environment":{"acceptedTime":now,"sourceCallIndex":tick,"route":"sailing","epoch":0},"ships":[state]},{"player":ship},camera)
		renderer.apply_snapshot(native,water,Callable())
		if tick%16==0:await process_frame
		if tick in [64,72,80,88,96,192,256]:
			ship.visible=not isolated;crew.visible=not isolated
			for node:Node in renderer._actors.player.node.find_children("*","MeshInstance3D",true,false):
				var mesh_name:=str(node.name)
				node.visible=layer=="all" or (layer=="foam" and (mesh_name.begins_with("Flow") or mesh_name.begins_with("bow_") or mesh_name.begins_with("side_"))) or (layer=="spray" and (mesh_name=="ContactSpray" or mesh_name.begins_with("ParticleSystem_")))
			await frames(3);await RenderingServer.frame_post_draw
			var img:=root.get_texture().get_image();var name:="t%03d.png"%tick;img.save_png(output+"/"+name);images.append(img)
			samples.append({"seconds":now,"image":name,"diagnostics":renderer.diagnostics()})
	var changed:=0
	if images.size()>2:
		for y in range(0,images[0].get_height(),2):
			for x in range(0,images[0].get_width(),2):
				var a:Color=images[0].get_pixel(x,y);var b:Color=images[1].get_pixel(x,y)
				if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)>.025:changed+=1
	var file:=FileAccess.open(output+"/VERIFICATION.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"phase":phase,"camera":angle,"layer":layer,"speed":speed,"changedPixels":changed,"samples":samples,"scope":"real model/crew/production route; controlled flat transparent depth-writing sea; visual comparison, not aesthetic pass/fail"},"\t"));file.close()
	renderer.dispose();crew.dispose();ship.dispose();world.free();await frames(2)
	print("HULL_CONTACT_GPU phase=",phase," camera=",angle," layer=",layer," changedPixels=",changed);quit(0)
