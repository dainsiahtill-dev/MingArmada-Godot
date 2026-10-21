extends Node3D
## Finite formal-game composition from the numeric owner's accepted grids.
## Owns terrain and original tree models; never modifies game height authority.
const Terrain = preload("res://modules/scene_engine/terrain/natural_island_mesh.gd")
const Trees = preload("res://modules/scene_engine/fidelity_island/vegetation.gd")
const Surf = preload("res://modules/scene_engine/terrain/natural_shore_surf.gd")
var _terrain: Array[Node3D] = []
var _trees: Array[Node3D] = []
var _grids: Array = []
var _configured := false
var _geometry_builds := 0
var _vertices := 0
var _triangles := 0
var _dynamic_shore: Array[Node3D] = []
func configure(grids: Array,height_sampler: Callable,options: Dictionary = {}) -> bool:
	if _configured or grids.is_empty() or not height_sampler.is_valid(): return false
	for entry: Variant in grids:
		if not entry is Dictionary or not entry.get("field") is RefCounted or not entry.field.has_method("get_grid") or not entry.get("bounds") is Rect2: return false
	for entry: Dictionary in grids:
		var terrain := Terrain.new(); terrain.name=str(entry.id)
		add_child(terrain)
		if not terrain.configure(entry.field): terrain.free(); dispose(); return false
		var mesh: MeshInstance3D=terrain.get_mesh()
		mesh.set_meta("natural_island_id",entry.id)
		mesh.set_meta("terrain_bounds",entry.bounds)
		mesh.set_meta("shoal",entry.get("shoal",false))
		_terrain.append(terrain); _geometry_builds+=1
		var grid: Dictionary=entry.field.get_grid(); var side: int=grid.side
		_vertices+=side*side; _triangles+=(side-1)*(side-1)*2
		if entry.get("shoal",false): continue
		if bool(options.get("vegetation",true)):
			var trees := Trees.new(); trees.name="NaturalForest_"+str(entry.id); add_child(trees)
			var pattern := FastNoiseLite.new(); pattern.seed=int(entry.seed)+9217
			pattern.noise_type=FastNoiseLite.TYPE_SIMPLEX_SMOOTH; pattern.frequency=0.022; pattern.fractal_octaves=2
			var mapping:={"id":str(entry.id),"width":329,"height":193,"sourceCenter":Vector2(164,96),"sourceOutward":Vector2.RIGHT,"islandCenter":entry.center,"inward":Vector2.LEFT,"scale":float(entry.radius)/220.0*2.3}
			if not trees.configure(mapping,_forest_ground.bind(entry.field,pattern,float(entry.peak)),{"mode":"mapped","adaptive_population":true,"existing_buildings":options.get("existing_buildings",[]),"forest_spacing":5.8,"forest_seed":int(entry.seed),"canopy_height":10.0,"palm_height":13.0,"forest_min_height":2.0,"forest_max_slope":1.1}):
				trees.free(); dispose(); return false
			_trees.append(trees)
	_grids=grids.duplicate(true); _configured=true
	return _configure_dynamic_shore(options)

func _configure_dynamic_shore(options: Dictionary) -> bool:
	if not bool(options.get("shore_surf",true)): return true
	for entry: Dictionary in _grids:
		if entry.get("shoal",false): continue
		var shore:=Surf.new(); shore.name="AdvancingSurf_"+str(entry.id)
		add_child(shore)
		if not shore.configure(entry.field,{"shore_id":entry.id,"wave_span":clampf(float(entry.radius)*0.08,6.0,14.0)}): shore.free(); dispose(); return false
		_dynamic_shore.append(shore)
	return true

func _forest_ground(x: float,z: float,field: RefCounted,pattern: FastNoiseLite,peak: float) -> float:
	var h: float=field.sample_triangle_height(x,z)
	if not is_finite(h) or h<2.0: return NAN
	var dx: float=(field.sample_triangle_height(x+1,z)-field.sample_triangle_height(x-1,z))*0.5
	var dz: float=(field.sample_triangle_height(x,z+1)-field.sample_triangle_height(x,z-1))*0.5
	if h>peak*(42.0/58.0) or h>peak*(24.0/58.0) and Vector2(dx,dz).length()>0.36: return NAN
	if h>6.0 and pattern.get_noise_2d(x,z)>0.31: return NAN
	return h

func get_meshes() -> Array:
	var meshes: Array=[]
	for terrain: Node3D in _terrain:
		if is_instance_valid(terrain): meshes.append(terrain.get_mesh())
	return meshes
func sample_mesh_height(x: float,z: float) -> float:
	if not _configured or not is_finite(x) or not is_finite(z): return NAN
	var height := -24.0
	for terrain: Node3D in _terrain: height=maxf(height,terrain.sample_height(x,z))
	return height
func supports(center: Vector2,radius: float) -> bool:
	if not _configured or not center.is_finite() or not is_finite(radius) or radius<0.0: return false
	for entry: Dictionary in _grids:
		var bounds: Rect2=entry.bounds
		if center.distance_to(center.clamp(bounds.position,bounds.end))<=radius: return true
	return false
func set_view_cameras(main:Camera3D,reflection:Camera3D=null,reflection_enabled:bool=false)->void:
	for shore:Node3D in _dynamic_shore:shore.set_view_cameras(main,reflection,reflection_enabled)
func sync_surface_state(ocean_material: ShaderMaterial,state: Dictionary = {}) -> void:
	for terrain: Node3D in _terrain: terrain.sync_surface_state(ocean_material,state)
	for shore: Node3D in _dynamic_shore: shore.sync_surface_state(ocean_material,state)
func apply_snapshot(snapshot: Dictionary,consumed: float = 0.0) -> void:
	var forest_state := snapshot.duplicate(true)
	forest_state.lighting={"lightDirection":Vector3(0.5,-0.8,-0.3).normalized(),"lightColor":Vector3(1,0.95,0.82),"ambient":Vector3(0.35,0.40,0.30),"customFog":false}
	for trees: Node3D in _trees: trees.apply_snapshot(forest_state,consumed)
	for shore: Node3D in _dynamic_shore: shore.apply_snapshot(snapshot,consumed)
func diagnostics() -> Dictionary:
	var islands: Array=[]; var vegetation: Array=[]; var surf: Array=[]
	for entry: Dictionary in _grids:
		if entry.get("shoal",false): continue
		var metrics: Dictionary=entry.field.get_diagnostics(); metrics.id=entry.id; metrics.bounds=entry.bounds
		islands.append(metrics)
	for trees: Node3D in _trees: vegetation.append(trees.diagnostics())
	for shore: Node3D in _dynamic_shore: surf.append(shore.diagnostics())
	return {"meshCount":_terrain.size(),"islandCount":islands.size(),"shoalMeshCount":_terrain.size()-islands.size(),"geometry_builds":_geometry_builds,"vertices":_vertices,"triangles":_triangles,"islands":islands,"vegetation":vegetation,"shoreSurf":surf,"artificialHarborFeatures":0,"sampling":"same cached Float32 a,b,c / c,b,d triangle surface","cameraRegeneration":false}
func dispose() -> void:
	for list: Array in [_terrain,_trees,_dynamic_shore]:
		for node: Node3D in list:
			if is_instance_valid(node): node.dispose(); node.free()
		list.clear()
	_grids.clear(); _configured=false; _geometry_builds=0; _vertices=0; _triangles=0
