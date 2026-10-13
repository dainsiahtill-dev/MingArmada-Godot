extends SceneTree
## Real original finite inactive fixture at the production material boundary.
const History=preload("res://modules/scene_engine/water/source_wake_history.gd")
const Geometry=preload("res://modules/scene_engine/water/source_wake_geometry.gd")
const Surface=preload("res://modules/scene_engine/water/source_surface.gd")
var assertions:=0
var failures:=0
func check(ok:bool,label:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL wake terminal descriptor: ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/source_wake/native-geometry-fixtures.json"))
	var scenario:Dictionary
	for entry:Dictionary in fixture.cases:
		if entry.name=="inactive":scenario=entry;break
	check(not scenario.is_empty(),"original inactive fixture available")
	var frame:Dictionary=scenario.frames[0]
	var bytes:PackedByteArray=str(frame.history_hex).hex_decode()
	var history:=History.new(fixture.configuration,scenario.scale)
	for i in 30:
		var at:=8+i*28
		history.points[i]={"p":[bytes.decode_float(at),bytes.decode_float(at+4),bytes.decode_float(at+8)],"born":bytes.decode_float(at+12),"length":bytes.decode_float(at+16),"v":bytes.decode_float(at+20),"active":bytes[at+24]!=0}
	history.head=bytes.decode_u32(848);history.total=bytes.decode_float(852);history.time=bytes.decode_float(860);history.scale=bytes.decode_float(864);history.updates=bytes.decode_u32(872);history.vertex_count=int(frame.native_count)
	var seed_uv:=PackedVector2Array();var seed_vertices:=PackedVector3Array();var seed_colors:=PackedColorArray()
	for i in 62:
		seed_uv.append(Vector2(scenario.initial_uvs[i][0],scenario.initial_uvs[i][1]));seed_vertices.append(Vector3.ZERO);seed_colors.append(Color(fixture.initial_color[0],fixture.initial_color[1],fixture.initial_color[2],fixture.initial_color[3]))
	history.set_meta(Geometry.STATE_KEY,{"native_vertices":seed_vertices,"native_uvs":seed_uv,"native_colors":seed_colors})
	var geometry:=Geometry.build(history,{"sourcePosition":frame.position,"sourceToWorld":1.0},frame.now,Callable(),Callable())
	check(geometry.draw_vertex_count==58 and geometry.vertices.size()==62,"allocated and submitted counts exceed actual active rows")
	check(geometry.colors[15].a>.7 and geometry.colors[17].a==0,"row7 is the visible tail and row8 is inactive")
	check(geometry.native_vertices[14]==geometry.native_vertices[16],"inactive geometry collapses at the actual tail")
	check(geometry.uvs[57].y==28.5,"original inactive UV remains untouched")
	var before_uv:PackedVector2Array=geometry.uvs.duplicate()
	var before_colors:PackedColorArray=geometry.colors.duplicate()
	var descriptor:=Surface.scene_strip_descriptor(geometry)
	check(descriptor.tail_v==geometry.uvs[15].y,"terminal mask uses row7, not stale inactive row28 UV")
	check(descriptor.tail_span_v==geometry.uvs[9].y-geometry.uvs[15].y,"terminal mask covers the last three active segments")
	check(geometry.uvs==before_uv and geometry.colors==before_colors,"material adaptation preserves original UV and row alpha")
	print("SOURCE_WAKE_TERMINAL_DESCRIPTOR_TESTS assertions=",assertions," failures=",failures)
	quit(0 if failures==0 else 1)
