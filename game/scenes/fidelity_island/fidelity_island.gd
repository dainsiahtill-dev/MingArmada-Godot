extends Control
## The completed source island assets in Godot; gameplay keeps its own sampler.
signal main_menu_requested
const TerrainArt = preload("res://modules/scene_engine/fidelity_island/terrain_material.gd")
const Coordinates = preload("res://modules/scene_engine/fidelity_island/source_coordinates.gd")
const Trees = preload("res://modules/scene_engine/fidelity_island/vegetation.gd")
const Surf = preload("res://modules/scene_engine/fidelity_island/shore.gd")
const Daylight = preload("res://modules/scene_engine/fidelity_island/daylight.gd")
const Ocean = preload("res://modules/scene_engine/ocean/projected_ocean.gd")
const Waves = preload("res://modules/contracts/wave_descriptor.gd")
const ShoreField = preload("res://modules/scene_engine/ocean/shore_field.gd")
const SourceWater = preload("res://modules/scene_engine/fidelity_island/source_water.gd")
var startup_options: Dictionary = {}
var startup_receipt: Dictionary = {"ok":false,"reason":"island-not-ready"}
var field: Dictionary = {}
var authored_time := 12.0
var seconds := 12.0
var paused := false
var orbit := {"yaw":0.0,"elevation":62.0*PI/180.0,"distance":13500.0}
var world: Node3D
var view: SubViewport
var camera: Camera3D
var ocean: MeshInstance3D
var reference_ocean: Node3D
var trees: Node3D
var surf: Node3D
var terrain_material: ShaderMaterial
var shore_field: RefCounted
var _container: SubViewportContainer
var _sun: DirectionalLight3D
var _environment: Environment
var _status: Label
var _dragging := false
var _disposed := false
var _native_origin := Vector3.ZERO
var _terrain_vertices := 0
var _terrain_triangles := 0
var _root_z := 0.0
var _cell_xy := 1.0
var _height_z := 1.0
var _half := Vector2.ZERO

func _ready() -> void:
	_build_ui()
	field = TerrainArt.load_source()
	var scene: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/fidelity_island/terrain-scene.json"))
	if field.is_empty() or not scene is Dictionary: _fail("海岛资源读取失败"); return
	_cell_xy=float(scene.effectiveScale[0]); _height_z=float(scene.effectiveScale[2]); _root_z=float(scene.translation[2])
	_half=Vector2((float(field.width)-1.0)*0.5,(float(field.height)-1.0)*0.5)
	_native_origin=Vector3(float(scene.translation[0])+_half.x*_cell_xy,float(scene.translation[1])-_half.y*_cell_xy,0.0)
	view.world_3d=World3D.new()
	world=Node3D.new(); world.name="FidelityIslandWorld"; view.add_child(world)
	camera=Camera3D.new(); camera.near=1000.0; camera.far=30000.0; camera.fov=360.0/7.0
	world.add_child(camera); camera.make_current(); _update_camera()
	var mapping := {"sourceCenter":_half,"sourceOutward":Vector2.DOWN,"islandCenter":Vector2.ZERO,"inward":Vector2.UP,"scale":_cell_xy,"enable_source_lighting":true,"source_normal_strength":1.0}
	terrain_material=TerrainArt.create_material({},mapping)
	if terrain_material == null: _fail("海岛材质初始化失败"); return
	# Exact source meshes use a right-handed Z-up rotation, rather than the
	# game's rotated/reflected port mapping. Correct only the texture transform.
	terrain_material.set_shader_parameter("source_uv_row_x",Vector2(1.0/(_cell_xy*float(field.width)),0.0))
	terrain_material.set_shader_parameter("source_uv_row_z",Vector2(0.0,1.0/(_cell_xy*float(field.height))))
	terrain_material.set_shader_parameter("source_uv_offset",(_half+Vector2.ONE*0.5)/Vector2(float(field.width),float(field.height)))
	terrain_material.set_shader_parameter("source_column_axis",Vector2.RIGHT)
	terrain_material.set_shader_parameter("source_row_axis",Vector2.DOWN)
	terrain_material.set_shader_parameter("display_fog_density",0.00001)
	for cell: Dictionary in scene.cells:
		var mesh := MeshInstance3D.new(); mesh.name="SourceCell_%s_%s" % [cell.column,cell.row]
		mesh.mesh=_cell_mesh(cell); mesh.material_override=terrain_material
		mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; world.add_child(mesh)
	ocean=Ocean.new(); ocean.name="PreservedOcean"; world.add_child(ocean)
	ocean.configure(camera,load("res://assets/textures/waternormals.jpg"),96,24000.0)
	ocean.set_wave_descriptors(Waves.original_descriptors())
	ocean.set_visual_style(1); ocean.set_surface_quality("high")
	ocean.material_override.set_shader_parameter("display_fog_density",0.00001)
	ocean.configure_reflection(camera); ocean.enable_surface_optics(true)
	var bounds := Rect2(Vector2(-_half.x,-_half.y)*_cell_xy,Vector2(float(field.width-1),float(field.height-1))*_cell_xy)
	shore_field=ShoreField.new()
	if not shore_field.configure(sample_height,bounds,512): _fail("海岸高度场初始化失败"); return
	ocean.set_shore_field(shore_field.get_texture(),shore_field.get_bounds(),shore_field.get_coast_texture())
	# Source observer coordinates span native units, not the game's metre scale.
	# Use the completed demo's flat NR branch with matching original mesh UVs;
	# the game ocean and its five authority waves remain available and unchanged.
	ocean.visible=false
	reference_ocean=SourceWater.new(); reference_ocean.name="CompletedReferenceWater"; world.add_child(reference_ocean)
	if not reference_ocean.configure(camera,_native_origin,{"far":30000.0,"fog_enabled":true}): _fail("参考海面初始化失败"); return
	reference_ocean.bind_terrain(terrain_material,bounds)
	trees=Trees.new(); trees.name="OriginalForestAndPalms"; world.add_child(trees)
	if not trees.configure({},Callable(),{"mode":"exact","native_origin":_native_origin}): _fail("森林与棕榈初始化失败"); return
	surf=Surf.new(); surf.name="OriginalShortSurf"; world.add_child(surf)
	if not surf.configure({},sample_height,{"mode":"exact","native_origin":_native_origin,"time":12.0,"follow_surface":false}): _fail("岸浪初始化失败"); return
	var environment_node := WorldEnvironment.new(); _environment=Environment.new()
	_environment.background_mode=Environment.BG_COLOR; _environment.background_color=Color("87ceeb")
	_environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color=Color("a0c8ff"); _environment.ambient_light_energy=0.45
	_environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR
	environment_node.environment=_environment; world.add_child(environment_node)
	_sun=DirectionalLight3D.new(); _sun.shadow_enabled=true; world.add_child(_sun)
	startup_receipt={"ok":true,"mode":"fidelity-island","terrainVertices":_terrain_vertices,"terrainTriangles":_terrain_triangles,"source":"fidelity-rebuild/island"}
	_render()
	_status.text="白沙 · 湿沙 · 岩脊 · 森林 · 棕榈 · 动态短岸浪"
	if not startup_options.get("staged",false): activate_entry()

func _cell_mesh(cell: Dictionary) -> ArrayMesh:
	var vertices := PackedVector3Array(); var normals := PackedVector3Array(); var uv := PackedVector2Array()
	var count := int(cell.verticesLocal.size()/3)
	vertices.resize(count); normals.resize(count); uv.resize(count)
	for index in count:
		var at:=index*3
		vertices[index]=Vector3(float(cell.verticesLocal[at])+float(cell.translation[0])-_half.x*_cell_xy,float(cell.verticesLocal[at+2])+float(cell.translation[2])+_root_z,-float(cell.verticesLocal[at+1])-float(cell.translation[1])-_half.y*_cell_xy)
		normals[index]=Vector3(float(cell.normals[at]),float(cell.normals[at+2]),-float(cell.normals[at+1]))
		uv[index]=Vector2(float(cell.uv[index*2]),float(cell.uv[index*2+1]))
	var indices := PackedInt32Array(cell.indices)
	for at in range(0,indices.size(),3):
		var old:=indices[at+1]; indices[at+1]=indices[at+2]; indices[at+2]=old
	var arrays: Array=[]; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_NORMAL]=normals; arrays[Mesh.ARRAY_TEX_UV]=uv; arrays[Mesh.ARRAY_INDEX]=indices
	var result := ArrayMesh.new(); result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	_terrain_vertices+=count; _terrain_triangles+=int(indices.size()/3)
	return result

func sample_height(x: float,z: float) -> float:
	if field.is_empty() or not is_finite(x) or not is_finite(z): return -800.0
	var pixel:=Vector2(x,z)/_cell_xy+_half
	if pixel.x<0.0 or pixel.y<0.0 or pixel.x>float(field.width-1) or pixel.y>float(field.height-1): return -800.0
	var column:=mini(floori(pixel.x),int(field.width)-2); var row:=mini(floori(pixel.y),int(field.height)-2)
	var f:=pixel-Vector2(column,row); var offset:=row*int(field.width)+column
	var a:=float(field.height_indices[offset]); var b:=float(field.height_indices[offset+1])
	var c:=float(field.height_indices[offset+int(field.width)]); var d:=float(field.height_indices[offset+int(field.width)+1])
	return lerpf(lerpf(a,b,f.x),lerpf(c,d,f.x),f.y)*_height_z+_root_z

func _render() -> void:
	if _disposed or not startup_receipt.ok: return
	var lighting: Dictionary=Daylight.sample(authored_time)
	if lighting.is_empty(): return
	var native_dir: Array=lighting.lightDirection
	var direction:=Vector3(float(native_dir[0]),float(native_dir[2]),-float(native_dir[1]))
	var color: Array=lighting.lightColor; var ambient: Array=lighting.ambient
	terrain_material.set_shader_parameter("source_light_direction",direction)
	terrain_material.set_shader_parameter("source_light_color",Vector3(float(color[0]),float(color[1]),float(color[2])))
	terrain_material.set_shader_parameter("source_ambient",Vector3(float(ambient[0]),float(ambient[1]),float(ambient[2])))
	terrain_material.set_shader_parameter("u_time",seconds)
	var godot_light:=lighting.duplicate(true); godot_light.lightDirection=direction
	trees.apply_snapshot({"time":seconds,"lighting":godot_light})
	ocean.set_simulation_time(seconds); ocean.update_projection()
	# Reuse the existing sea shader and all five waves. Only the observer's
	# authored sun inputs change when inspecting source day/night lighting.
	ocean.material_override.set_shader_parameter("u_sun",-direction)
	ocean.material_override.set_shader_parameter("u_sun_color",Vector3(float(color[0]),float(color[1]),float(color[2])))
	var fog_color: Array=lighting.fogColor
	_environment.background_color=Color(float(fog_color[0]),float(fog_color[1]),float(fog_color[2])).srgb_to_linear()
	reference_ocean.apply_snapshot(seconds,lighting)
	if surf.has_method("sync_surface_state"): surf.sync_surface_state(ocean.material_override)
	surf.apply_snapshot(seconds)
	_sun.basis=Basis.looking_at(direction,Vector3.UP)
	_sun.light_color=Color(float(color[0]),float(color[1]),float(color[2])); _sun.light_energy=1.0

func _process(delta: float) -> void:
	if _disposed or not startup_receipt.ok: return
	if not paused and is_visible_in_tree() and get_window().has_focus(): seconds+=minf(maxf(delta,0.0),0.05)
	_render()

func _update_camera() -> void:
	if not is_instance_valid(camera): return
	var yaw:=float(orbit.yaw); var elevation:=float(orbit.elevation); var distance:=float(orbit.distance)
	camera.position=Vector3(sin(yaw)*cos(elevation)*distance,sin(elevation)*distance,cos(yaw)*cos(elevation)*distance)
	camera.look_at(Vector3.ZERO,Vector3.UP)

func _view_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_LEFT: _dragging=event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			orbit.distance=clampf(float(orbit.distance)*(0.86 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.16),1200.0,18000.0); _update_camera()
	elif event is InputEventMouseMotion and _dragging:
		orbit.yaw=float(orbit.yaw)-event.relative.x*0.006
		orbit.elevation=clampf(float(orbit.elevation)+event.relative.y*0.004,0.25,1.35); _update_camera()

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column:=VBoxContainer.new(); column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(column)
	var toolbar:=HBoxContainer.new(); toolbar.add_theme_constant_override("separation",16); column.add_child(toolbar)
	var title:=Label.new(); title.text="海岛实景  ·  拖动环绕 / 滚轮拉近"; title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; toolbar.add_child(title)
	var noon:=Button.new(); noon.name="Noon"; noon.text="晴昼"; noon.pressed.connect(func(): set_daylight(12.0)); toolbar.add_child(noon)
	var sunset:=Button.new(); sunset.name="Sunset"; sunset.text="黄昏"; sunset.pressed.connect(func(): set_daylight(18.0)); toolbar.add_child(sunset)
	var night:=Button.new(); night.name="Night"; night.text="夜色"; night.pressed.connect(func(): set_daylight(0.0)); toolbar.add_child(night)
	var pause:=Button.new(); pause.name="Pause"; pause.text="暂停岸浪"; pause.pressed.connect(func(): paused=not paused; pause.text="继续岸浪" if paused else "暂停岸浪"); toolbar.add_child(pause)
	var back:=Button.new(); back.name="Back"; back.text="返回"; back.pressed.connect(func(): main_menu_requested.emit()); toolbar.add_child(back)
	_container=SubViewportContainer.new(); _container.stretch=true; _container.size_flags_vertical=Control.SIZE_EXPAND_FILL; _container.size_flags_horizontal=Control.SIZE_EXPAND_FILL; column.add_child(_container)
	view=SubViewport.new(); view.size=Vector2i(1280,720); view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; _container.add_child(view)
	_container.gui_input.connect(_view_input)
	_status=Label.new(); column.add_child(_status)

func set_daylight(value: float) -> bool:
	if not is_finite(value) or value<0.0 or value>24.0: return false
	authored_time=value; _render(); return true

func activate_entry() -> void:
	if _disposed or not startup_receipt.ok: return
	camera.make_current(); get_window().title="海上明旗 · 海岛实景"; _render()

func inspection_snapshot() -> Dictionary:
	return {"startup":startup_receipt.duplicate(true),"time":seconds,"authoredTime":authored_time,"paused":paused,"orbit":orbit.duplicate(true),"cameraPosition":camera.global_position if is_instance_valid(camera) else null,"trees":trees.diagnostics() if is_instance_valid(trees) else {},"shore":surf.diagnostics() if is_instance_valid(surf) else {},"water":reference_ocean.diagnostics() if is_instance_valid(reference_ocean) else {},"material":TerrainArt.diagnostics(terrain_material),"scope":"Completed reference sea/shore assets and formulas adapted to Godot source observer; formal game ocean retained separately; no original frame equivalence claim."}

func save_frame(path: String) -> Dictionary:
	if DisplayServer.get_name()=="headless" or not is_instance_valid(view): return {"ok":false,"reason":"frame-unavailable"}
	_render(); await RenderingServer.frame_post_draw
	if _disposed or not is_instance_valid(view): return {"ok":false,"reason":"frame-unavailable"}
	var image:=view.get_texture().get_image()
	var error:=image.save_png(path)
	return {"ok":error==OK,"path":ProjectSettings.globalize_path(path),"width":image.get_width(),"height":image.get_height()}

func _fail(message: String) -> void:
	_status.text=message; startup_receipt={"ok":false,"reason":"island-startup-failed","message":message}; set_process(false)

func dispose() -> void:
	if _disposed: return
	_disposed=true; set_process(false)
	if is_instance_valid(trees): trees.dispose()
	if is_instance_valid(surf): surf.dispose()
	if is_instance_valid(world): world.free()
	world=null; camera=null; ocean=null; reference_ocean=null; trees=null; surf=null; terrain_material=null
	field={}; shore_field=null; _environment=null; _sun=null

func _exit_tree() -> void: dispose()
