extends SceneTree
const Compiler=preload("res://modules/scene_engine/fidelity_fx/cloud_render_compiler.gd")
const Native=preload("res://modules/scene_engine/fidelity_fx/cloud_native.gd")
var assertions:=0
var failures:=0
func check(value:bool,reason:String)->void:
	assertions+=1
	if not value:failures+=1;printerr("FAIL atmosphere float kernel: ",reason)
func bits(value:float)->int:
	var bytes:=PackedByteArray();bytes.resize(4);bytes.encode_float(0,value)
	return bytes.decode_u32(0)
func same_bits(actual:Variant,expected:Variant)->bool:
	if actual is Dictionary:
		if not expected is Dictionary or actual.size()!=expected.size():return false
		for key:Variant in actual:
			if not expected.has(key) or not same_bits(actual[key],expected[key]):return false
		return true
	if actual is Array:
		if not expected is Array or actual.size()!=expected.size():return false
		for i in actual.size():
			if not same_bits(actual[i],expected[i]):return false
		return true
	return bits(float(actual))==bits(float(expected))
func _initialize()->void:_run.call_deferred()
func _run()->void:
	var compiler:=Compiler.new()
	var ready:=true
	for method:String in ["_f32","_multiply_matrix","_transform_vector","_transform_transpose","_compose_transform","_billboard_mode0","render_minimum_states"]:
		var available:=compiler.has_method(method);check(available,"private exact reusable-buffer kernel exists: "+method);ready=ready and available
	if ready:
		# Expected stores come from the unchanged source oracle, including signed
		# zero/subnormals/ties/overflow, rather than a second rounding formula.
		var values:Array=[0.0,-0.0,INF,-INF,NAN,pow(2.0,-149.0),-pow(2.0,-149.0),pow(2.0,-150.0),pow(2.0,-126.0),1.0+pow(2.0,-24.0),1.0+pow(2.0,-24.0)+pow(2.0,-52.0),1.0-pow(2.0,-25.0),16777217.0,-16777217.0,3.4028234663852886e38,3.5e38]
		for value:float in values:check(bits(compiler.call("_f32",value))==bits(Native.f32(value)),"binary32 store matches source for "+str(value))
		var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/fidelity_fx/manifest.json"))
		var cameras:Array=[{"direction":[0.0,-1.0,0.0],"up":[0.0,0.0,1.0],"right":[1.0,0.0,0.0]},{"direction":[0.0,0.0,-1.0],"up":[0.0,1.0,0.0],"right":[1.0,0.0,0.0]},{"direction":[.36085122,-.43081242,.82719978],"up":[.17228565,.90244198,.3949131],"right":[-.91659197,0.0,.39982493]}]
		var ring:Dictionary=Native.create_cloud_ring(1)
		var count:=0
		for entry:Dictionary in manifest.atmosphere.assets:
			var asset:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(str(entry.data_path)))
			var bounds_outer:Dictionary={"rotation":ring.nodes[count%ring.nodes.size()].rotation,"translation":[.1,.2,.3],"scale":1.15}
			var compiled:Dictionary=compiler.compile_asset(asset)
			for camera:Dictionary in cameras:
				var minimum_states:Array=compiler.call("render_minimum_states",compiled,bounds_outer,camera)
				var full:Array=Native.original_meshes(asset,0.0,bounds_outer,false,camera)
				check(minimum_states.size()==full.size(),"minimum-only path preserves every actual source mesh")
				for i in full.size():
					var minimum:=INF
					for point:Array in full[i].vertices:minimum=minf(minimum,float(point[2]))
					check(bits(minimum_states[i].minimumZ)==bits(minimum),"minimum-only path matches all source vertex Z stores exactly: "+str(full[i].block))
					check(not minimum_states[i].has("vertices") and not minimum_states[i].has("uvs"),"minimum-only live path does not allocate unused transformed geometry")
					for field:String in ["world","billboard"]:check(same_bits(minimum_states[i].get(field,{}),full[i].get(field,{})),"minimum-only path retains actual source "+field)
			for block:Dictionary in asset.blocks:
				if not block.fields.has("rotation"):continue
				var local:Dictionary=Native._static_transform(block.fields)
				var clone:Dictionary=ring.nodes[count%ring.nodes.size()]
				var parent:Dictionary={"rotation":clone.rotation,"translation":Native.transform_vector(clone.rotation,[0,1,0]),"scale":1.15}
				check(same_bits(compiler.call("_multiply_matrix",parent.rotation,local.rotation),Native.multiply_matrix(parent.rotation,local.rotation)),"actual source matrix multiplication bit order: "+str(block.id))
				check(same_bits(compiler.call("_transform_vector",parent.rotation,local.translation),Native.transform_vector(parent.rotation,local.translation)),"actual source vector store order: "+str(block.id))
				check(same_bits(compiler.call("_transform_transpose",parent.rotation,local.translation),Native.transform_transpose(parent.rotation,local.translation)),"actual source transposed-vector reverse sum order: "+str(block.id))
				check(same_bits(compiler.call("_compose_transform",parent,local),Native.compose_transform(parent,local)),"actual source nested TRS bit identity: "+str(block.id))
				for camera:Dictionary in cameras:check(same_bits(compiler.call("_billboard_mode0",local.rotation,camera),Native.billboard_mode0(local.rotation,camera)),"actual source billboard branch bit identity: "+str(block.id))
				count+=1
		check(count>60,"bit comparison consumes all six original cloud/fog node transforms")
	print("ATMOSPHERE_FLOAT_KERNEL_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
