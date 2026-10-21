extends SceneTree
const Sampler=preload("res://modules/scene_engine/fidelity_fx/cloud_curve_sampler.gd")
const Native=preload("res://modules/scene_engine/fidelity_fx/cloud_native.gd")
const Compiler=preload("res://modules/scene_engine/fidelity_fx/cloud_render_compiler.gd")
var assertions:=0
var failures:=0
func check(ok:bool,reason:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL cloud curve sampler: ",reason)
func _initialize()->void:
	var groups:Array=[
		{},
		{"keys":[],"interpolation":1},
		{"keys":[{"time":0.0,"value":.123456789}],"interpolation":2},
		{"keys":[{"time":-.3,"value":-.123456789},{"time":1.0000001192092896,"value":16777217.0},{"time":2.1,"value":-0.0}],"interpolation":1},
		{"keys":[{"time":0.0,"value":.2,"backward":.3,"forward":-.6},{"time":1.0000001192092896,"value":.8,"backward":.05,"forward":.7},{"time":2.1,"value":.1,"backward":-.2,"forward":.15}],"interpolation":2},
		{"keys":[{"time":0.0,"value":.2},{"time":1.0,"value":.8}],"interpolation":0},
		{"keys":[{"time":0.0,"value":{"x":.123456789012345,"y":-0.0,"z":16777217.0}},{"time":1.0000001192092896,"value":{"x":-1.33333333333333,"y":2.55555555555555,"z":.7}},{"time":2.1,"value":{"x":-0.0,"y":.123456789012345,"z":-16777217.0}}],"interpolation":1}
	]
	for group:Dictionary in groups:
		var bytes:=var_to_bytes(group);var sampler:=Sampler.new(group);var peer:=Sampler.new(group)
		var held:Variant=sampler.sample(-2.0);var held_bytes:=var_to_bytes(held)
		for time:float in [-INF,-2.0,-.3,-.2,0.0,pow(2.0,-149),.1,.3333333,.9999999,1.0,1.0000001192092896,1.25,2.0,2.1,INF,.1,0.0]:
			check(var_to_bytes(sampler.sample(time))==var_to_bytes(Native._sample(group,time)),"source scalar/vector/endpoint bytes "+str([group,time]))
			peer.sample(19.7)
			check(var_to_bytes(sampler.sample(time))==var_to_bytes(peer.sample(time)),"independent owner-local stores "+str(time))
		check(var_to_bytes(group)==bytes,"private compilation and sampling leave immutable input unchanged")
		check(var_to_bytes(held)==held_bytes,"later same-owner or peer samples leave published endpoint arrays unchanged")
		if held is Array:
			held[0]=123456.0
			check(var_to_bytes(sampler.sample(-2.0))==var_to_bytes(Native._sample(group,-2.0)),"consumer edits to endpoint output cannot alter precompiled vector keys")
	var source:Dictionary={"keys":[{"time":0.0,"value":{"x":.123456789012345,"y":-0.0,"z":2.0}},{"time":1.0,"value":{"x":3.0,"y":4.0,"z":5.0}}]}
	var detached:=Sampler.new(source);var detached_bytes:=var_to_bytes(detached.sample(.3))
	source.keys[0].value.x=900.0;source.keys[0].time=-2.0
	check(var_to_bytes(detached.sample(.3))==detached_bytes,"compiled key snapshot is isolated from later edits to raw authored dictionary")
	var compiler:=Compiler.new();var empty:Dictionary=compiler._controller({"fields":{}},{})
	check(empty.sampler.sample(.3)==null,"absent keys retain null alpha/UV sample rather than missing sampler")
	var graph:Dictionary={"roots":[{"local":{"rotation":Native.identity(),"translation":[0.0,0.0,0.0],"scale":1.0},"keyframes":[],"children":[],"billboard":false,"leaf":{"source":{"alpha":1.0},"hasTransform":true,"desc":{"transform_type":0},"alphaControllers":[empty],"uvControllers":[]}}]}
	check(compiler.render_states(graph,.3,{},true)[0].alpha==null,"actual renderer retains empty alpha-controller null output")
	print("CLOUD_CURVE_SAMPLER_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
