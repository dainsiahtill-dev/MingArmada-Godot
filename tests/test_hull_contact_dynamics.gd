extends SceneTree
## Relative bow/sea closure must produce bounded contact impulses, never clock artifacts.
const Contact=preload("res://modules/scene_engine/water/hull_contact_froth.gd")
var assertions:=0
var failures:=0
var sea_height:=0.0
func _initialize()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: ",message)
func water(_x:float,_z:float,_time:float)->float:return sea_height
func packet(height:float=0.1,yaw:float=0.0)->Dictionary:
	var pose:=Transform3D(Basis(Vector3.UP,yaw),Vector3(0,height,0))
	var sections:=[{"z":-6.0,"left":-.2,"right":.2},{"z":-4.0,"left":-1.0,"right":1.0},{"z":4.0,"left":-1.0,"right":1.0},{"z":6.0,"left":-.2,"right":.2}]
	var rings:=[{"height":-1.0,"sections":sections},{"height":1.0,"sections":sections}]
	var tip:Vector3=pose*Vector3(0,0,6)
	var forward:Vector3=pose.basis.z*3.0
	return {"enabled":true,"targetSpeed":3.0,"targetVelocity":[forward.x,0.0,forward.z],"sourceToWorld":1.0,"worldOrigin":[0.0,0.0,0.0],"sourceBowPosition":[tip.x,-tip.z,tip.y],"epoch":1,"surfaceProfile":{"sections":sections,"verticalSections":rings,"hullToWorld":pose,"worldToHull":pose.affine_inverse()}}
func fixture()->Array:
	var owner:=Node3D.new();root.add_child(owner)
	var effect:=Contact.new();effect.configure(owner,0,83)
	return [effect,owner]
func release(pair:Array)->void:pair[0].dispose();pair[1].free()
func state(effect:RefCounted)->PackedByteArray:
	return var_to_bytes({"drops":effect._droplets,"flow":effect.diagnostics().flow_distance,"births":effect.diagnostics().target_births,"impact":effect.diagnostics().get("impact_strength",0.0),"turn":effect.diagnostics().get("turn_bias",0.0)})
func run()->void:
	for mode:String in ["rising sea","descending hull","common heave"]:
		sea_height=0.0
		var pair:=fixture();var effect:RefCounted=pair[0]
		effect.apply_snapshot(packet(),0.0,water,Callable())
		check(effect.diagnostics().get("impact_strength",0.0)==0.0,mode+" initial sample has no invented impact")
		var next_height:=.1
		if mode=="rising sea":sea_height=.15
		elif mode=="descending hull":next_height=-.05
		else:sea_height=.15;next_height=.25
		effect.apply_snapshot(packet(next_height),.025,water,Callable())
		var impact:=float(effect.diagnostics().get("impact_strength",0.0))
		if mode=="common heave":check(impact<.00001,"same hull/sea displacement does not create relative impact")
		else:
			check(impact>.3 and impact<=1.0,mode+" creates finite bounded bow-entry pulse")
			check(absf(float(effect.diagnostics().get("closing_speed",0.0))-6.0)<.001,mode+" measures six metres/second relative closure")
			var peak_crest:=0.0
			for side:String in ["FlowPort","FlowStarboard"]:
				# Dummy headless RenderingServer does not apply region bytes to readback.
				# These are the real retained vertices encoded in this frame's upload.
				for vertex:Vector3 in effect._buffers[side].vertices:peak_crest=maxf(peak_crest,vertex.y-sea_height-.045)
			check(peak_crest>.17 and peak_crest<=.22001,"entry pulse raises small localized crest without wall")
			check(float(effect._nodes.FlowPort.material_override.get_shader_parameter("impact_strength"))>.3,"contact shader receives localized impact strength")
			var before:=state(effect)
			effect.apply_snapshot(packet(next_height-.1),.025,water,Callable())
			effect.redraw_camera({"right":[0.0,1.0,0.0],"up":[0.0,0.0,1.0]})
			check(state(effect)==before,"duplicate accepted time freezes bow pulse and all droplet owners")
			for tick in range(2,26):effect.apply_snapshot(packet(next_height),float(tick)*.025,water,Callable())
			check(float(effect.diagnostics().get("impact_strength",0.0))<impact*.2,"entry pulse decays in less than one second without repeated closure")
			var crest_max:=0.0
			for side:String in ["FlowPort","FlowStarboard"]:
				var arrays:Array=effect._nodes[side].mesh.surface_get_arrays(0)
				for vertex:Vector3 in arrays[Mesh.ARRAY_VERTEX]:crest_max=maxf(crest_max,vertex.y-sea_height-.045)
			check(crest_max<=.22001,"impact crest remains below22cm")
		release(pair)
	for artifact:String in ["rewind","epoch","teleport","long elapsed","missing contact","disabled"]:
		sea_height=0.0
		var pair:=fixture();var effect:RefCounted=pair[0]
		effect.apply_snapshot(packet(),.1,water,Callable())
		sea_height=.2
		var next:=packet(-.1);var time:=.125
		match artifact:
			"rewind":time=.05
			"epoch":next.epoch=2
			"teleport":next.surfaceProfile.hullToWorld.origin.x=100.0;next.surfaceProfile.worldToHull=next.surfaceProfile.hullToWorld.affine_inverse();next.sourceBowPosition[0]=100.0
			"long elapsed":time=2.0
			"missing contact":next=packet(2.0)
			"disabled":next.enabled=false
		effect.apply_snapshot(next,time,water,Callable())
		check(float(effect.diagnostics().get("impact_strength",0.0))==0.0,artifact+" suppresses spurious impact")
		release(pair)
	for yaw:float in [-.04,.04]:
		sea_height=0.0
		var pair:=fixture();var effect:RefCounted=pair[0]
		effect.apply_snapshot(packet(),0.0,water,Callable())
		effect.apply_snapshot(packet(.1,yaw),.025,water,Callable())
		var bias:=float(effect.diagnostics().get("turn_bias",0.0))
		check(absf(bias)>.005 and absf(bias)<=.18001,"accepted yaw creates modest signed side bias")
		check(signf(bias)==signf(yaw),"turn bias preserves physical turn direction")
		var port:Variant=effect._nodes.FlowPort.material_override.get_shader_parameter("turn_bias")
		var starboard:Variant=effect._nodes.FlowStarboard.material_override.get_shader_parameter("turn_bias")
		check(port!=null and starboard!=null and absf(float(port)+float(starboard))<.00001 and absf(float(port))>.005,"side shaders receive opposing outside/inside gains")
		var before:=state(effect);effect.apply_snapshot(packet(.1,-yaw),.025,water,Callable())
		check(state(effect)==before,"same-time pose redraw does not create turning impulse")
		release(pair)
	# A held positive closure emits one impulse; separating and entering re-arms it.
	sea_height=0.0
	var pair:=fixture();var effect:RefCounted=pair[0]
	effect.apply_snapshot(packet(),0.0,water,Callable())
	effect.apply_snapshot(packet(-.05),.025,water,Callable())
	var first_peak:=float(effect.diagnostics().get("impact_strength",0.0))
	for tick in range(2,5):effect.apply_snapshot(packet(.1-float(tick)*.15),float(tick)*.025,water,Callable())
	check(float(effect.diagnostics().get("impact_strength",0.0))<first_peak*.85,"held closing velocity produces one decaying pulse rather than sustained impact wall")
	effect.apply_snapshot(packet(.1),.125,water,Callable())
	effect.apply_snapshot(packet(-.05),.15,water,Callable())
	check(float(effect.diagnostics().get("impact_strength",0.0))>.9,"opening then re-entering water re-arms bow pulse")
	release(pair)
	sea_height=0.0;pair=fixture();effect=pair[0]
	var negative:=packet();negative.sourceBowPosition[1]=6.0;negative.targetVelocity=[0.0,0.0,-3.0]
	effect.apply_snapshot(negative,0.0,water,Callable())
	negative.surfaceProfile.hullToWorld.origin.y=-.05;negative.surfaceProfile.worldToHull=negative.surfaceProfile.hullToWorld.affine_inverse();negative.sourceBowPosition[2]=-.05
	effect.apply_snapshot(negative,.025,water,Callable())
	check(float(effect.diagnostics().get("impact_strength",0.0))>.3,"negative hull-axis bow still measures accepted world entry")
	var small_drops:=true
	for drop:Dictionary in effect._droplets:
		if drop.active:small_drops=small_drops and float(drop.radius)*2.0<=.20001 and float(drop.bow_distance)>=.3 and float(drop.bow_distance)<=1.3
	check(small_drops,"impact spray remains centimetre-size and directly behind selected bow")
	release(pair)
	var base:=fixture();var entry:=fixture()
	for tick in 3:
		base[0].apply_snapshot(packet(),float(tick)*.025,water,Callable())
		entry[0].apply_snapshot(packet(.1 if tick==0 else -.05),float(tick)*.025,water,Callable())
	check(entry[0].diagnostics().target_births>base[0].diagnostics().target_births,"bow-entry pulse increases actual short spray birth rate")
	var lifted:=false
	for drop:Dictionary in entry[0]._droplets:
		if drop.active:lifted=lifted or float(drop.velocity.y)>1.3
	check(lifted,"impact newborn gets additional bounded upward speed")
	release(base);release(entry)
	# Exact cached ring heights use that ring's extents, not a neighbouring ring.
	pair=fixture();effect=pair[0]
	var exact:=packet(0.0)
	var shortened:=[{"z":-3.0,"left":-1.0,"right":1.0},{"z":3.0,"left":-1.0,"right":1.0}]
	exact.surfaceProfile.verticalSections=[{"height":-1.0,"sections":shortened},{"height":0.0,"sections":exact.surfaceProfile.sections},{"height":1.0,"sections":shortened}]
	effect.apply_snapshot(exact,0.0,water,Callable())
	var forebody:=false
	var buffer:RefCounted=effect._buffers.FlowPort
	for index:int in buffer.indices:
		if buffer.uv[index].x<1.3 and buffer.colors[index].a>.1:forebody=true
	check(forebody,"exact vertical ring preserves its own full forebody contact extent")
	release(pair)
	print("HULL_CONTACT_DYNAMICS_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
