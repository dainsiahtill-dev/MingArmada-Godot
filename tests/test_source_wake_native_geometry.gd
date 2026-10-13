extends SceneTree
## Original CPU oracle buffers, not a screenshot or a duplicated implementation.
const History=preload("res://modules/scene_engine/water/source_wake_history.gd")
const Geometry=preload("res://modules/scene_engine/water/source_wake_geometry.gd")
const FIXTURE="res://assets/data/source_wake/native-geometry-fixtures.json"
var assertions:=0
var failures:=0
var maximum_position_error:=0.0
func check(ok:bool,message:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: ",message)
func _initialize()->void:_run.call_deferred()
func _history(history:RefCounted,frame:Dictionary)->void:
	var raw:PackedByteArray=str(frame.history_hex).hex_decode()
	for i in 30:
		var at:=8+i*28
		history.points[i]={"p":[raw.decode_float(at),raw.decode_float(at+4),raw.decode_float(at+8)],"born":raw.decode_float(at+12),"length":raw.decode_float(at+16),"v":raw.decode_float(at+20),"active":raw[at+24]!=0}
	history.head=raw.decode_u32(848);history.total=raw.decode_float(852)
	history.time=raw.decode_float(860);history.scale=raw.decode_float(864)
	history.updates=raw.decode_u32(872);history.vertex_count=int(frame.native_count)
func _check_buffer(out:Dictionary,frame:Dictionary,name:String)->void:
	var positions:PackedByteArray=str(frame.vertices_hex).hex_decode()
	var colors:PackedByteArray=str(frame.colors_hex).hex_decode()
	var uvs:PackedByteArray=str(frame.uvs_hex).hex_decode()
	var error:=0.0;var uv_error:=0.0;var alpha_error:=0.0
	if out.vertices.size()<int(frame.native_count):
		check(false,name+" allocated source geometry holds draw count");return
	for i in int(frame.native_count):
		var actual:Vector3=out.vertices[i]
		var expected:=Vector3(positions.decode_float(i*12),positions.decode_float(i*12+8),-positions.decode_float(i*12+4))
		error=maxf(error,actual.distance_to(expected))
		uv_error=maxf(uv_error,out.uvs[i].distance_to(Vector2(uvs.decode_float(i*8),uvs.decode_float(i*8+4))))
		alpha_error=maxf(alpha_error,absf(out.colors[i].a-colors.decode_float(i*16+12)))
	maximum_position_error=maxf(maximum_position_error,error)
	check(error<=0.0005,name+" native edge/head positions max_error="+str(error))
	check(uv_error<=0.000001,name+" active and retained inactive UV max_error="+str(uv_error))
	check(alpha_error<=0.000001,name+" original row/startup alpha max_error="+str(alpha_error))
func _run()->void:
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	check(str(fixture.source_sha256).length()==64,"original geometry fixture retains source SHA256")
	check(fixture.exe_sha256=="0da87d60243280dea5965dbb23d099bcd0727db344de35886a5207e487a7e120","geometry fixtures bind the recovered EXE")
	for scenario:Dictionary in fixture.cases:
		var history:=History.new(fixture.configuration,float(scenario.scale))
		var seed_uv:=PackedVector2Array();var seed_vertices:=PackedVector3Array();var seed_colors:=PackedColorArray()
		for i in 62:
			seed_vertices.append(Vector3.ZERO);seed_colors.append(Color(fixture.initial_color[0],fixture.initial_color[1],fixture.initial_color[2],fixture.initial_color[3]))
			seed_uv.append(Vector2(scenario.initial_uvs[i][0],scenario.initial_uvs[i][1]))
		# The oracle explicitly supplies synthetic initial buffers. This does
		# not claim recovery of the original geometry constructor or model UVs.
		history.set_meta("source_wake_geometry_state",{"native_vertices":seed_vertices,"native_uvs":seed_uv,"native_colors":seed_colors})
		var last:Dictionary={}
		for frame:Dictionary in scenario.frames:
			_history(history,frame)
			var packet:Dictionary={"sourcePosition":frame.position,"sourceToWorld":1.0,"worldOrigin":[0.0,0.0,0.0],"sourceHeading":0.0}
			if bool(frame.accepted):last=Geometry.build(history,packet,float(frame.now),Callable(),Callable())
			_check_buffer(last,frame,str(scenario.name)+" frame "+str(frame.frame))
		check(last.vertices.size()==62,"source storage capacity differs from effective 58 vertex draw count")
	# Real caller-stage buffers include the exceptional finite AL=true cases
	# absent from the normal sailing sequences; do not substitute generic cross.
	for fixture_case:Dictionary in fixture.repair_cases:
		var input:PackedByteArray=str(fixture_case.input_vertices_hex).hex_decode()
		var expected:PackedByteArray=str(fixture_case.output_vertices_hex).hex_decode()
		var vertices:=PackedVector3Array()
		for i in 62:vertices.append(Vector3(input.decode_float(i*12),input.decode_float(i*12+4),input.decode_float(i*12+8)))
		var repaired:int=Geometry._repair(vertices)
		check(repaired==int(fixture_case.hits),str(fixture_case.name)+" original AL selects caller-stage copies")
		check(vertices.to_byte_array()==expected,str(fixture_case.name)+" exact finite source caller-stage edge copies")
	var initial:=History.new({},0.6,1,[100.0,100.0,0.0]);initial.update([100.0,100.0,0.0],0.0)
	var first:=Geometry.build(initial,{"sourcePosition":[100.0,100.0,0.0],"sourceToWorld":0.01},0.0,Callable(),Callable())
	check(first.indices.is_empty(),"first zero-total sample does not submit native nonfinite geometry to GPU")
	for p:Vector3 in first.vertices:check(p.is_finite(),"first zero-total sample has no GPU NaN")
	print("SOURCE_WAKE_NATIVE_GEOMETRY_TESTS assertions=",assertions," failures=",failures," max_position_error=",maximum_position_error)
	quit(1 if failures else 0)
