extends SceneTree
## Frozen oracle, real compiler calls, no cache-layout assumptions.
const Native=preload("res://modules/scene_engine/fidelity_fx/cloud_native.gd")

class BaselineProbe extends "res://game/research/fixtures/cloud_billboard_baseline.gd":
	var transpose_calls:=0
	var transpose_rotations:Array=[]
	func _transform_transpose(matrix:Array,vector:Array)->Array:
		transpose_calls+=1
		transpose_rotations.append(var_to_bytes(matrix))
		return super._transform_transpose(matrix,vector)
	func reset_probe()->void:
		transpose_calls=0;transpose_rotations.clear()

class CandidateProbe extends "res://game/research/demos/architecture_billboard_candidate.gd":
	var transpose_calls:=0
	var transpose_rotations:Array=[]
	func _transform_transpose(matrix:Array,vector:Array)->Array:
		transpose_calls+=1
		transpose_rotations.append(var_to_bytes(matrix))
		return super._transform_transpose(matrix,vector)
	func reset_probe()->void:
		transpose_calls=0;transpose_rotations.clear()

var assertions:=0
var failures:=0
var baseline_ring_calls:=0
var candidate_ring_calls:=0
var cameras:Array=[
	{"direction":[0.0,-1.0,0.0],"up":[0.0,0.0,1.0],"right":[1.0,0.0,0.0]},
	{"direction":[0.0,0.0,-1.0],"up":[0.0,1.0,0.0],"right":[1.0,0.0,0.0]},
	{"direction":[.36085122,-.43081242,.82719978],"up":[.17228565,.90244198,.3949131],"right":[-.91659197,0.0,.39982493]}
]

func check(ok:bool,message:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL cloud billboard reuse: ",message)

func json(path:String)->Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func local_inputs(compiled:Dictionary)->PackedByteArray:
	var result:Array=[]
	var pending:Array=compiled.roots.duplicate()
	while not pending.is_empty():
		var node:Dictionary=pending.pop_back()
		if node.is_empty():continue
		result.append([node.local,node.staticBillboardRelative])
		pending.append_array(node.children)
	return var_to_bytes(result)

func distinct_rotations(rotations:Array)->Array:
	var result:Array=[]
	for bytes:PackedByteArray in rotations:
		if not result.has(bytes):result.append(bytes)
	return result

func fixture_graph(rotations:Array)->Dictionary:
	var roots:Array=[]
	for rotation:Array in rotations:
		roots.append({"local":{"rotation":rotation.duplicate(),"translation":[0.0,0.0,0.0],"scale":1.0},"billboard":true,"keyframes":[],"children":[],"staticBillboardRelative":{"rotation":Native.identity(),"translation":[0.0,0.0,0.0],"scale":1.0},"leaf":{"source":{"localVertices":[[1.0,-2.0,3.0],[-4.0,5.0,-6.0]],"alpha":1.0},"hasTransform":false,"desc":{},"alphaControllers":[],"uvControllers":[]}})
	return {"roots":roots}

func _initialize()->void:run.call_deferred()

func make_candidate()->RefCounted:return CandidateProbe.new()

func run()->void:
	var baseline:=BaselineProbe.new();var candidate:=make_candidate()
	var assets:Dictionary={}
	for entry:Dictionary in json("res://assets/data/fidelity_fx/manifest.json").atmosphere.assets:
		assets[entry.file]=json(entry.data_path)
	# Encounter seed1661 seeds weather CRT; sky CRT remains production default1.
	var ring:Dictionary=Native.create_cloud_ring(1)
	var ring_bytes:=var_to_bytes(ring)
	var camera_bytes:=var_to_bytes(cameras)
	check(ring.nodes.size()==30,"actual seed1661 ring retains all 30 source clouds")
	var baseline_graphs:Dictionary={};var candidate_graphs:Dictionary={}
	var asset_bytes:Dictionary={};var old_locals:Dictionary={};var new_locals:Dictionary={}
	for name:String in assets:
		asset_bytes[name]=var_to_bytes(assets[name])
		baseline_graphs[name]=baseline.compile_asset(assets[name])
		candidate_graphs[name]=candidate.compile_asset(assets[name])
		old_locals[name]=local_inputs(baseline_graphs[name]);new_locals[name]=local_inputs(candidate_graphs[name])
	var seen:Dictionary={}
	for clone:Dictionary in ring.nodes:
		seen[clone.prototype]=true
		var outer:Dictionary={"rotation":clone.rotation,"translation":Native.transform_vector(clone.rotation,[0,1,0]),"scale":1.0}
		var outer_bytes:=var_to_bytes(outer)
		for camera:Dictionary in cameras:
			baseline.reset_probe();candidate.reset_probe()
			var expected:Array=baseline.render_minimum_states(baseline_graphs[clone.prototype],outer,camera)
			var actual:Array=candidate.render_minimum_states(candidate_graphs[clone.prototype],outer,camera)
			check(var_to_bytes(actual)==var_to_bytes(expected),"complete 30-cloud minimum-state bytes "+str([clone.name,clone.prototype,camera]))
			baseline_ring_calls+=baseline.transpose_calls;candidate_ring_calls+=candidate.transpose_calls
		check(var_to_bytes(outer)==outer_bytes,"ring clone outer TRS remains byte-identical "+clone.name)
	check(seen.size()==5,"seed1661 fixture exercises every authored domecloud prototype")
	check(baseline_ring_calls>0,"ring baseline performs real billboard transpose work")
	check(candidate_ring_calls<baseline_ring_calls,"30-cloud minimum path reduces underlying transpose work baseline=%d candidate=%d"%[baseline_ring_calls,candidate_ring_calls])
	var nontrivial:Dictionary={"rotation":Native.multiply_matrix(Native.rotation_x(.17),Native.rotation_z(.55)),"translation":[-.123456789,17.25,-9.75],"scale":1.15}
	var outer_before:=var_to_bytes(nontrivial)
	for name:String in seen:
		for camera:Dictionary in cameras+[{}]:
			var expected:Array=baseline.render_minimum_states(baseline_graphs[name],nontrivial,camera)
			var actual:Array=candidate.render_minimum_states(candidate_graphs[name],nontrivial,camera)
			check(var_to_bytes(actual)==var_to_bytes(expected),"all five assets retain full states under nontrivial outer TRS "+name)
	for name:String in assets:
		check(var_to_bytes(assets[name])==asset_bytes[name],"authored asset input bytes remain unchanged "+name)
		check(local_inputs(baseline_graphs[name])==old_locals[name],"frozen compiled local input bytes remain unchanged "+name)
		check(local_inputs(candidate_graphs[name])==new_locals[name],"candidate compiled local input bytes remain unchanged "+name)
	check(var_to_bytes(ring)==ring_bytes,"every original ring byte, seed-derived rotation and counter remains unchanged")
	check(var_to_bytes(nontrivial)==outer_before and var_to_bytes(cameras)==camera_bytes,"camera arrays and nontrivial caller TRS remain unchanged")
	test_published_rotation_ownership()
	test_invocation_and_owner_boundaries()
	test_signed_zero_keys()
	test_degenerate_threshold()
	test_unoptimized_render_and_controllers(assets,nontrivial)
	finish()

func finish()->void:
	print("CLOUD_BILLBOARD_REUSE_WORK baselineTransposeCalls=",baseline_ring_calls," candidateTransposeCalls=",candidate_ring_calls)
	print("CLOUD_BILLBOARD_REUSE_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)

func test_published_rotation_ownership()->void:
	# Returning one writable cache value to two matching leaves corrupts peers.
	var baseline:=BaselineProbe.new();var candidate:=make_candidate()
	var graph:=fixture_graph([Native.identity(),Native.identity(),Native.identity()])
	var graph_before:=var_to_bytes(graph)
	var expected:Array=baseline.render_minimum_states(graph,{},cameras[2])
	var actual:Array=candidate.render_minimum_states(graph,{},cameras[2])
	check(var_to_bytes(actual)==var_to_bytes(expected),"duplicate rotations start with complete frozen states")
	check(var_to_bytes(actual[0].world.rotation)==var_to_bytes(actual[1].world.rotation),"ownership fixture publishes matching billboard rotation values")
	var untouched:=var_to_bytes(actual.slice(1))
	actual[0].world.rotation[0]=123456.0
	check(var_to_bytes(actual.slice(1))==untouched,"consumer edit of one cached rotation cannot alter any matching published leaf")
	check(var_to_bytes(graph)==graph_before,"consumer edit of published rotation cannot mutate compiled input")
	check(var_to_bytes(candidate.render_minimum_states(graph,{},cameras[2]))==var_to_bytes(expected),"consumer edit cannot poison a later invocation")

func test_invocation_and_owner_boundaries()->void:
	# Memo retained after return would silently skip new-call work or old camera.
	var baseline:=BaselineProbe.new();var candidate:=make_candidate();var peer:=make_candidate()
	var graph:=fixture_graph([Native.identity(),Native.identity()])
	var rotated:=fixture_graph([Native.rotation_x(.43),Native.rotation_x(.43)])
	candidate.reset_probe()
	var first:Array=candidate.render_minimum_states(graph,{},cameras[0])
	var calls:int=candidate.transpose_calls
	var held:=var_to_bytes(first)
	candidate.reset_probe()
	var repeated:Array=candidate.render_minimum_states(graph,{},cameras[0])
	check(candidate.transpose_calls==calls and calls>0,"fresh minimum invocation recomputes its own billboard values")
	check(var_to_bytes(repeated)==held,"same inputs retain exact repeated-call output")
	for camera:Dictionary in [cameras[2],cameras[1],cameras[2],cameras[0]]:
		check(var_to_bytes(peer.render_minimum_states(rotated,{},camera))==var_to_bytes(baseline.render_minimum_states(rotated,{},camera)),"interleaved independent owner uses its own graph and camera")
		check(var_to_bytes(candidate.render_minimum_states(graph,{},camera))==var_to_bytes(baseline.render_minimum_states(graph,{},camera)),"camera change and return cannot reuse prior invocation value")
	check(var_to_bytes(first)==held,"later calls and other owners cannot mutate retained published states")
	baseline.reset_probe();candidate.reset_probe()
	for i in 2:
		check(var_to_bytes(candidate._billboard_mode0(Native.identity(),cameras[0]))==var_to_bytes(baseline._billboard_mode0(Native.identity(),cameras[0])),"direct billboard call after minimum scope keeps frozen output")
	check(candidate.transpose_calls==baseline.transpose_calls and baseline.transpose_calls==6,"direct billboard calls outside minimum invocation retain all original work")

func test_signed_zero_keys()->void:
	# Numeric matrix equality must not merge distinct binary rotation inputs.
	var positive:Array=[0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0]
	# GDScript constant folding normalizes literal -0.0; decode its sign bit.
	var negative_zero:=PackedByteArray([0,0,0,0,0,0,0,128]).decode_double(0)
	var negative:Array=[]
	for i in 9:negative.append(negative_zero)
	check(positive==negative and var_to_bytes(positive)!=var_to_bytes(negative),"signed-zero fixture is numerically equal and byte-distinct")
	var graph:=fixture_graph([positive,positive,negative,negative])
	var before:=var_to_bytes(graph)
	var baseline:=BaselineProbe.new();var candidate:=make_candidate()
	var expected:Array=baseline.render_minimum_states(graph,{},cameras[2])
	var actual:Array=candidate.render_minimum_states(graph,{},cameras[2])
	var old_keys:=distinct_rotations(baseline.transpose_rotations)
	var new_keys:=distinct_rotations(candidate.transpose_rotations)
	check(old_keys.size()==2,"real composition preserves both signed-zero matrix byte patterns at billboard input")
	check(new_keys.size()==2,"both exact signed-zero keys reach underlying computation")
	for key:PackedByteArray in old_keys:check(new_keys.has(key),"underlying computation retains each signed-zero key byte pattern")
	check(var_to_bytes(actual)==var_to_bytes(expected),"signed-zero full published states match frozen bytes")
	check(var_to_bytes(graph)==before,"signed-zero input arrays remain unchanged")

func test_degenerate_threshold()->void:
	# Reuse must preserve both sides and exact endpoint of source <= threshold.
	var baseline:=BaselineProbe.new();var candidate:=make_candidate()
	var graph:=fixture_graph([Native.identity(),Native.identity()])
	var results:Array=[]
	for height:float in [0.0,9.99999883788405e-7,9.999999974752427e-7,1.0000001111620804e-6]:
		var camera:Dictionary={"direction":[.1,-.3,.9],"up":[.7,height,.2],"right":[.4,0.0,.8]}
		var before:=var_to_bytes(camera)
		var expected:Array=baseline.render_minimum_states(graph,{},camera)
		check(var_to_bytes(candidate.render_minimum_states(graph,{},camera))==var_to_bytes(expected),"degenerate billboard branch exact bytes at y="+str(height))
		check(var_to_bytes(camera)==before,"degenerate camera remains immutable")
		results.append(var_to_bytes(expected[0].world.rotation))
	check(results[2]!=results[3],"threshold fixture observes different source branches at endpoint and next binary32 value")

func test_unoptimized_render_and_controllers(atmosphere_assets:Dictionary,outer:Dictionary)->void:
	# Broadening reuse into general/animated rendering changes original work.
	var baseline:=BaselineProbe.new();var candidate:=make_candidate()
	var assets:Dictionary=atmosphere_assets.duplicate()
	var weather:=json("res://assets/data/fidelity_fx/weather/manifest.json")
	for entry:Dictionary in weather.assets:
		var asset:=json(entry.data_path)
		if entry.file=="stormcloud_sound.nif":asset=baseline.bind_sequence(asset,json(weather.stormSequence))
		assets[entry.file]=asset
	var animated_clocks:=0;var observed_work:=0
	for name:String in assets:
		var source_before:=var_to_bytes(assets[name])
		var old:Dictionary=baseline.compile_asset(assets[name]);var current:Dictionary=candidate.compile_asset(assets[name])
		var old_before:=local_inputs(old);var new_before:=local_inputs(current)
		animated_clocks+=baseline.controller_snapshot(old).size()
		candidate.render_minimum_states(current,outer,cameras[2])
		for persistent:bool in [false,true]:
			for time:float in [0.0,.1,.1,19.200000762939453,33.5,.1,0.0,-.2]:
				baseline.reset_probe();candidate.reset_probe()
				var expected:Array=baseline.render_states(old,time,outer,true,cameras[2],true,true,persistent)
				var actual:Array=candidate.render_states(current,time,outer,true,cameras[2],true,true,persistent)
				check(var_to_bytes(actual)==var_to_bytes(expected),"animated full states preserve frozen output "+str([name,persistent,time]))
				check(var_to_bytes(candidate.controller_snapshot(current))==var_to_bytes(baseline.controller_snapshot(old)),"animated controller snapshots preserve call history "+str([name,persistent,time]))
				check(candidate.transpose_calls==baseline.transpose_calls,"animated render_states retains original underlying work "+name)
				observed_work+=baseline.transpose_calls
		baseline.reset_probe();candidate.reset_probe()
		check(var_to_bytes(candidate.render_states(current,0.0,outer,false,cameras[2],false,true))==var_to_bytes(baseline.render_states(old,0.0,outer,false,cameras[2],false,true)),"direct static render_states stays byte-exact "+name)
		check(candidate.transpose_calls==baseline.transpose_calls,"direct static render_states outside minimum entry retains original work "+name)
		check(var_to_bytes(assets[name])==source_before and local_inputs(old)==old_before and local_inputs(current)==new_before,"static and animated rendering preserve all local source bytes "+name)
	check(animated_clocks>0 and observed_work>0,"animation regression uses real fog/weather controllers and billboard work")
