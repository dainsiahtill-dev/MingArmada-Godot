extends RefCounted
## Cached authored supply shoal. This same finite Float32 grid is rendered and
## sampled by navigation; it cannot create dry land or alter an island coast.
var _bounds := Rect2()
var _side := 0
var _heights := PackedFloat32Array()
func configure(start: Vector2,end: Vector2,resolution: int = 129) -> bool:
	if not start.is_finite() or not end.is_finite() or start.distance_to(end)<=0.0 or resolution<17 or resolution>257: return false
	var low := start.lerp(end,0.32)
	var high := start.lerp(end,0.68)
	var margin := Vector2.ONE*135.0
	var bounds := Rect2(low.min(high)-margin,low.max(high)-low.min(high)+margin*2.0)
	var direction := (end-start).normalized()
	var length := start.distance_to(end)
	var heights := PackedFloat32Array(); heights.resize(resolution*resolution)
	for row in resolution:
		for column in resolution:
			var p := bounds.position+bounds.size*Vector2(column,row)/float(resolution-1)
			var along := (p-start).dot(direction)
			var across := (p-start).dot(Vector2(-direction.y,direction.x))
			var end_distance := maxf(maxf(length*0.32-along,0.0),along-length*0.68)
			var distance := Vector2(across,end_distance).length()
			var t := clampf((135.0-distance)/45.0,0.0,1.0)
			heights[row*resolution+column] = -24.0+21.6*t*t*(3.0-2.0*t)
	# Force exact deep boundary after arithmetic, preserving mesh continuity.
	for index in resolution:
		heights[index]=-24.0; heights[(resolution-1)*resolution+index]=-24.0
		heights[index*resolution]=-24.0; heights[index*resolution+resolution-1]=-24.0
	_bounds=bounds; _side=resolution; _heights=heights
	return true
func bounds() -> Rect2: return _bounds
func get_grid() -> Dictionary: return {"bounds":_bounds,"side":_side,"heights":_heights.duplicate()}
func sample_triangle_height(x: float,z: float) -> float:
	if _side<2 or not is_finite(x) or not is_finite(z): return NAN
	if x<_bounds.position.x or z<_bounds.position.y or x>_bounds.end.x or z>_bounds.end.y: return -24.0
	var p := (Vector2(x,z)-_bounds.position)/_bounds.size*float(_side-1)
	var column := mini(floori(p.x),_side-2); var row := mini(floori(p.y),_side-2)
	var u := p.x-column; var v := p.y-row; var a := row*_side+column
	if u+v<=1.0: return _heights[a]+(_heights[a+1]-_heights[a])*u+(_heights[a+_side]-_heights[a])*v
	var d := a+_side+1
	return _heights[d]+(_heights[a+_side]-_heights[d])*(1.0-u)+(_heights[a+1]-_heights[d])*(1.0-v)
