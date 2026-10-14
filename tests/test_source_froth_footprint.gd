extends SceneTree
const Froth=preload("res://modules/scene_engine/water/source_froth.gd")
var assertions:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL froth footprint: ",label)
func water(_x:float,_z:float,_time:float)->float:return 0.0
func hull_edge(z:float)->float:
	return 2.5 if absf(z)<=4.0 else lerpf(2.5,.7,clampf((absf(z)-4.0)/6.0,0,1))
func run()->void:
	var owner:=Node3D.new();root.add_child(owner);var effect:=Froth.new();check(effect.configure(owner,3,17).ok,"real barque source configured")
	var sections:Array=[]
	for z:float in [-10.0,-8.0,-4.0,0.0,4.0,8.0,10.0]:sections.append({"z":z,"left":-hull_edge(z),"right":hull_edge(z)})
	var profile:={"sections":sections,"worldToHull":Transform3D.IDENTITY,"hullToWorld":Transform3D.IDENTITY,"beam":5.0,"targetOuterWidth":.75,"intensity":.65}
	var packet:={"sourcePosition":[0.0,0.0,0.0],"sourceBowPosition":[0.0,0.0,0.0],"sourceHeading":0.0,"modelScale":1.0,"sourceToWorld":.021353528480495498,"controllerAppTime":24.0,"enabled":true,"surfaceProfile":profile}
	effect.apply_snapshot(packet,24.0,water,Callable())
	var side_colors:PackedColorArray;var side_uvs:PackedVector2Array;var points:PackedVector3Array;var intensity:=1.0
	for key:String in effect._surface.nodes:
		if not key.begins_with("side_"):continue
		var node:MeshInstance3D=effect._surface.nodes[key];var arrays:Array=node.mesh.surface_get_arrays(0);points=arrays[Mesh.ARRAY_VERTEX];side_colors=arrays[Mesh.ARRAY_COLOR];side_uvs=arrays[Mesh.ARRAY_TEX_UV]
		var tint:Variant=node.material_override.get_shader_parameter("display_tint");intensity=tint.a if tint is Color else 1.0
		for i in points.size():
			var p:Vector3=points[i]
			check(p.is_finite(),"finite fitted vertex")
			if side_colors[i].a>=.99:
				check(absf(p.x)<=hull_edge(p.z)+.8,"solid side foam stays within requested hull-contact band i=%d point=%s edge=%f"%[i,p,hull_edge(p.z)])
	check(is_equal_approx(intensity,.65),"target intensity is an independent material factor")
	# Opting into target fitting must preserve original colors and UV playback.
	var raw:=Froth.new();raw.configure(owner,3,17);packet.erase("surfaceProfile");raw.apply_snapshot(packet,24.0,water,Callable())
	for key:String in raw._surface.nodes:
		if not key.begins_with("side_"):continue
		var arrays:Array=raw._surface.nodes[key].mesh.surface_get_arrays(0)
		check(arrays[Mesh.ARRAY_COLOR]==side_colors,"authored source RGBA remains intact")
		check(arrays[Mesh.ARRAY_TEX_UV]==side_uvs,"authored source UV remains intact")
	# Reuse the same material with a different speed: no stale full strength.
	profile.intensity=.12;packet.surfaceProfile=profile;packet.controllerAppTime=24.2;effect.apply_snapshot(packet,24.2,water,Callable())
	for key:String in effect._surface.nodes:
		if key.begins_with("side_"):
			var tint:Variant=effect._surface.nodes[key].material_override.get_shader_parameter("display_tint")
			check(tint is Color and is_equal_approx(tint.a,.12),"reused side material receives current speed strength")
	# The public outer adapter can override only the side scale. The prepared
	# carrier must follow the scale that actually produced these vertices.
	var carrier_key:String=effect._footprint_carriers.keys()[0]
	var prior:Dictionary=effect._footprint_carriers[carrier_key].shape.duplicate(true)
	packet.sideScale=2.0;packet.controllerAppTime=24.3;effect.apply_snapshot(packet,24.3,water,Callable())
	var resized:Dictionary=effect._footprint_carriers[carrier_key].shape
	check(is_equal_approx(float(resized.low),float(prior.low)*2.0) and is_equal_approx(float(resized.high),float(prior.high)*2.0),"explicit sideScale override invalidates carrier even when modelScale is unchanged")
	var cached_shape:=var_to_bytes(resized)
	packet.sideScale=2.0+0.0000001;packet.controllerAppTime=24.4;effect.apply_snapshot(packet,24.4,water,Callable())
	check(var_to_bytes(effect._footprint_carriers[carrier_key].shape)==cached_shape and effect._footprint_carriers.size()==1,"scale ulp jitter reuses one bounded carrier")
	effect.dispose();raw.dispose();owner.free();print("SOURCE_FROTH_FOOTPRINT assertions=",assertions," failures=",failures);quit(0 if failures==0 else 1)
