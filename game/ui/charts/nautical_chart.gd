extends Control
## Read-only north-up chart. Caller owns immutable terrain and fleet authority.
signal waypoint_requested(point: Dictionary)
signal chart_requested
const Text = preload("res://game/domain/legacy/utf16_text.gd")
const Parchment = preload("res://game/ui/shared/parchment_theme.gd")
const DEFAULT_BOUNDS = Rect2(-1000,-800,2400,1750)
const GRID_STEP = 30.0
const CACHE_LIMIT = 20480
const BACKGROUND = "res://assets/art/maps/ming-nautical-chart-v2.png"
const BACKGROUND_FALLBACK = "res://assets/art/maps/ming-nautical-chart-v1.png"
const LAND_PAPER = "res://assets/art/maps/ming-nautical-land-paper-v2.png"
const LAND_GRAIN_SPAN = 720.0
const INK = Parchment.INK
const GOLD = Parchment.OUTLINE
var _ports: Array = []
var _height: Callable
var _native: Dictionary = {}
var _overlays: Dictionary = {}
var _height_cache: Dictionary = {}
var _land_polygons: Array = []
var _shoal_polygons: Array = []
var _coast_segments: Array = []
var _mountains: Array = []
var _bounds: Rect2 = DEFAULT_BOUNDS
var _compact := false
var _span := 1100.0
var _title := "大明沿海航图"
var _terrain_window: Rect2i
var _terrain_ready := false
var _configured := false
var _background: Texture2D
var _land_paper: Texture2D
var _fallback_land_paper: Texture2D
var _font: Font
var _title_font: Font
var _land_mesh: ArrayMesh
var _shoal_mesh: ArrayMesh
var _mesh_rect: Rect2
var _mesh_bounds: Rect2
var _mesh_ready := false
var _label_boxes: Array = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP; clip_contents = true; custom_minimum_size = Vector2(160,230)
	theme = Parchment.create()
	_font = theme.default_font
	_title_font = Parchment.title_font()
	_background=_load_texture(BACKGROUND)
	if not _background: _background=_load_texture(BACKGROUND_FALLBACK)
	_land_paper=_load_texture(LAND_PAPER); _fallback_land_paper=_native_land_paper()
	texture_repeat=CanvasItem.TEXTURE_REPEAT_ENABLED
	resized.connect(_on_chart_resized)
	_update_intrinsic_height()

func _load_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path): return null
	return load(path) as Texture2D

func _native_land_paper() -> Texture2D:
	# A cached material fallback; no terrain, time or external resource dependency.
	var image := Image.create_empty(128,128,false,Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:
			var grain := float(posmod(x*37+y*61+x*y*7,29)-14)/520.0
			var fiber := 0.018 if posmod(x+y*3,17)<2 else 0.0
			image.set_pixel(x,y,Color(0.81+grain-fiber,0.68+grain-fiber,0.39+grain-fiber,1))
	return ImageTexture.create_from_image(image)

func configure(ports: Array, height_sampler: Callable, options: Dictionary = {}) -> bool:
	dispose()
	if not height_sampler.is_valid(): return false
	var requested: Variant = options.get("bounds",DEFAULT_BOUNDS)
	if not requested is Rect2 or requested.size.x<=0 or requested.size.y<=0: return false
	if not requested.position.is_finite() or not requested.size.is_finite() or requested.size.x>3840 or requested.size.y>3840: return false
	_bounds=requested; _compact=bool(options.get("compact",false)); _span=clampf(float(options.get("span",1100.0)),300.0,2400.0)
	_title=String(options.get("title","海图" if _compact else "大明沿海航图"))
	_ports=ports.duplicate(true); _height=height_sampler; _configured=true
	_update_intrinsic_height()
	_prepare_terrain(); queue_redraw(); return true

func _on_chart_resized() -> void:
	_update_intrinsic_height()
	queue_redraw()

func _update_intrinsic_height() -> void:
	var height := 230.0
	if _configured and not _compact:
		height=float(ceili(clampf(maxf(0,size.x-44)*_bounds.size.y/_bounds.size.x+86,300,500)))
	var minimum := Vector2(160,height)
	if custom_minimum_size!=minimum: custom_minimum_size=minimum

func apply_naval_snapshot(native: Dictionary, overlays: Dictionary = {}) -> void:
	if not _configured: return
	_native=native.duplicate(true); _overlays=overlays.duplicate(true)
	if not _overlays.get("waypoint") is Dictionary: _overlays.waypoint={}
	for key in ["activeObjectives","routes","landSites"]:
		if not _overlays.get(key) is Array: _overlays[key]=[]
	_prepare_terrain(); queue_redraw()

func _player() -> Dictionary:
	for ship: Dictionary in _native.get("ships",[]):
		if String(ship.get("id",""))==String(_native.get("playerId","")): return ship
	return {}

func _ship_position(ship: Dictionary) -> Dictionary:
	return ship.get("visual",{}).get("position",ship.get("position",{}))

func view_bounds() -> Rect2:
	if not _compact: return _bounds
	var point: Dictionary = _ship_position(_player())
	var focus := Vector2(float(point.get("x",_bounds.get_center().x)),float(point.get("z",_bounds.get_center().y)))
	return Rect2(focus-Vector2.ONE*_span/2,Vector2.ONE*_span)

func map_rect() -> Rect2:
	var margin := 14.0 if _compact else 22.0
	var top := 34.0 if _compact else 48.0
	var bottom := 27.0 if _compact else 38.0
	var available := Vector2(maxf(0,size.x-margin*2),maxf(0,size.y-top-bottom))
	var world := view_bounds().size
	var scale := minf(available.x/world.x,available.y/world.y)
	var extent := world*scale
	return Rect2(Vector2((size.x-extent.x)/2,top+(available.y-extent.y)/2),extent)

func projected(point: Dictionary) -> Vector2:
	var bounds := view_bounds(); var rect := map_rect()
	return rect.position+Vector2((float(point.get("x",0))-bounds.position.x)/bounds.size.x*rect.size.x,(float(point.get("z",0))-bounds.position.y)/bounds.size.y*rect.size.y)

func unprojected(point: Vector2) -> Dictionary:
	var bounds := view_bounds(); var rect := map_rect()
	if rect.size.x<=0 or rect.size.y<=0: return {}
	return {"x":bounds.position.x+(point.x-rect.position.x)/rect.size.x*bounds.size.x,"z":bounds.position.y+(point.y-rect.position.y)/rect.size.y*bounds.size.y}

func ship_marks() -> Array:
	var result: Array = []
	for ship: Dictionary in _native.get("ships",[]):
		var point := _ship_position(ship); var position := Vector2(float(point.get("x",0)),float(point.get("z",0)))
		if not view_bounds().has_point(position): continue
		var flagship := String(ship.get("id",""))==String(_native.get("playerId",""))
		var selected: bool = ship.get("id","")==_overlays.get("selectedShipId","") and not String(ship.get("id","")).is_empty()
		var team := String(ship.get("team","neutral")); var heading := float(ship.get("visual",{}).get("heading",ship.get("heading",0)))
		result.append({"id":ship.get("id",""),"position":position,"direction":Vector2(cos(heading),sin(heading)),"flagship":flagship,"selected":selected,"role":"hostile" if team=="hostile" else "ally" if team in ["player","ally","friendly"] else "trade"})
	return result

func _sample(ix: int, iz: int) -> float:
	var key := Vector2i(ix,iz)
	if not _height_cache.has(key):
		if _height_cache.size()>=CACHE_LIMIT: _height_cache.erase(_height_cache.keys()[0])
		_height_cache[key]=float(_height.call(ix*GRID_STEP,iz*GRID_STEP))
	return _height_cache[key]

func _prepare_terrain() -> void:
	if not _configured: return
	var bounds := view_bounds(); var begin := Vector2i(floori(bounds.position.x/GRID_STEP),floori(bounds.position.y/GRID_STEP))
	var end := Vector2i(ceili(bounds.end.x/GRID_STEP),ceili(bounds.end.y/GRID_STEP)); var window := Rect2i(begin,end-begin)
	if _terrain_ready and window==_terrain_window: return
	_terrain_window=window; _terrain_ready=true
	_mesh_ready=false
	_land_polygons.clear(); _shoal_polygons.clear(); _coast_segments.clear(); _mountains.clear()
	for iz in range(begin.y,end.y):
		for ix in range(begin.x,end.x):
			var points := PackedVector2Array([Vector2(ix,iz)*GRID_STEP,Vector2(ix+1,iz)*GRID_STEP,Vector2(ix+1,iz+1)*GRID_STEP,Vector2(ix,iz+1)*GRID_STEP])
			var heights := PackedFloat64Array([_sample(ix,iz),_sample(ix+1,iz),_sample(ix+1,iz+1),_sample(ix,iz+1)])
			_march_cell(points,heights,0.0,_land_polygons,true); _march_cell(points,heights,-4.0,_shoal_polygons,false)
			if heights[0]>12 and posmod(ix+iz*3,11)==0: _mountains.append({"point":points[0],"height":heights[0]})

func _march_cell(points: PackedVector2Array, heights: PackedFloat64Array, level: float, polygons: Array, coast: bool) -> void:
	var mask := 0
	for i in 4:
		if heights[i]>=level: mask|=1<<i
	if mask==0: return
	if mask==15: polygons.append(points); return
	var crossings: Array = []; var polygon := PackedVector2Array()
	for i in 4:
		var next := (i+1)%4; var inside := heights[i]>=level
		if inside: polygon.append(points[i])
		if inside!=(heights[next]>=level):
			var edge := points[i].lerp(points[next],clampf((level-heights[i])/(heights[next]-heights[i]),0,1))
			polygon.append(edge); crossings.append(edge)
	# Resolve diagonal marching-squares masks using the sampled center average.
	if mask in [5,10] and (heights[0]+heights[1]+heights[2]+heights[3])/4<level:
		for i in 4:
			if heights[i]<level: continue
			var prev := (i+3)%4; var next := (i+1)%4
			var a := points[i].lerp(points[prev],(level-heights[i])/(heights[prev]-heights[i]))
			var b := points[i].lerp(points[next],(level-heights[i])/(heights[next]-heights[i]))
			polygons.append(PackedVector2Array([a,points[i],b]))
			if coast: _coast_segments.append(PackedVector2Array([a,b]))
	else:
		polygons.append(polygon)
		if coast:
			if crossings.size()==2: _coast_segments.append(PackedVector2Array(crossings))
			elif crossings.size()==4:
				var offset := 0 if mask==5 else 1
				_coast_segments.append(PackedVector2Array([crossings[offset],crossings[(offset+1)%4]]))
				_coast_segments.append(PackedVector2Array([crossings[(offset+2)%4],crossings[(offset+3)%4]]))

func _world_pixel(point: Vector2) -> Vector2: return projected({"x":point.x,"z":point.y})

func _terrain_mesh(polygons: Array) -> ArrayMesh:
	var bounds := view_bounds(); var rect := map_rect(); var scale := rect.size/bounds.size
	var mask := PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
	var vertices := PackedVector2Array(); var indices := PackedInt32Array(); var uvs := PackedVector2Array()
	for polygon in polygons:
		var pixels := PackedVector2Array(); var inside := true
		for point in polygon:
			var pixel: Vector2 = rect.position+(point-bounds.position)*scale
			pixels.append(pixel)
			if pixel.x<rect.position.x or pixel.x>rect.end.x or pixel.y<rect.position.y or pixel.y>rect.end.y: inside=false
		# Interior polygons already satisfy the exact rectangular clipping mask.
		var clipped_polygons: Array = [pixels] if inside else Geometry2D.intersect_polygons(pixels,mask)
		for clipped in clipped_polygons:
			if clipped.size()<3: continue
			var triangles := Geometry2D.triangulate_polygon(clipped)
			var offset := vertices.size()
			vertices.append_array(clipped)
			for vertex_index in clipped.size():
				# Recover clipped world coordinates once per mesh build. Adjacent cells,
				# resize and compact follow share one continuous world paper material.
				var world: Vector2 = polygon[vertex_index] if inside else bounds.position+(clipped[vertex_index]-rect.position)/scale
				uvs.append(world/LAND_GRAIN_SPAN)
			for index in triangles: indices.append(offset+index)
	var mesh := ArrayMesh.new()
	if not indices.is_empty():
		var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_INDEX]=indices; arrays[Mesh.ARRAY_TEX_UV]=uvs
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func _prepare_meshes() -> void:
	if _mesh_ready and _mesh_rect==map_rect() and _mesh_bounds==view_bounds(): return
	_mesh_rect=map_rect(); _mesh_bounds=view_bounds(); _mesh_ready=true
	_land_mesh=_terrain_mesh(_land_polygons); _shoal_mesh=_terrain_mesh(_shoal_polygons)

func _clip_line(a: Vector2, b: Vector2) -> PackedVector2Array:
	var rect := map_rect(); var delta := b-a; var low := 0.0; var high := 1.0
	var p := PackedFloat64Array([-delta.x,delta.x,-delta.y,delta.y]); var q := PackedFloat64Array([a.x-rect.position.x,rect.end.x-a.x,a.y-rect.position.y,rect.end.y-a.y])
	for i in 4:
		if absf(p[i])<0.0001:
			if q[i]<0: return PackedVector2Array()
		else:
			var fraction := q[i]/p[i]
			if p[i]<0: low=maxf(low,fraction)
			else: high=minf(high,fraction)
			if low>high: return PackedVector2Array()
	return PackedVector2Array([a+delta*low,a+delta*high])

func _line(a: Vector2, b: Vector2, color: Color, width: float = 1.0) -> void:
	var clipped := _clip_line(a,b)
	if clipped.size()==2: draw_line(clipped[0],clipped[1],color,width,true)

func _draw() -> void:
	if size.x<=0 or size.y<=0 or not _font: return
	draw_rect(Rect2(Vector2.ZERO,size),Color("b39a5f"))
	if _background: draw_texture_rect(_background,Rect2(Vector2.ZERO,size),false)
	else:
		draw_rect(Rect2(Vector2(5,5),size-Vector2(10,10)),Color("ded0a0"))
		for i in 20: draw_line(Vector2(5,float(i)*size.y/20),Vector2(size.x-5,float(i)*size.y/20+2),Color(0.43,0.31,0.15,0.045),1)
	var rect := map_rect()
	if rect.size.x<=0 or rect.size.y<=0: return
	draw_rect(rect,Color(0.10,0.28,0.32,0.12 if _background else 0.84)); _draw_rhumbs(rect); _draw_waves(rect)
	if _configured:
		_prepare_meshes()
		if _shoal_mesh.get_surface_count()>0: draw_mesh(_shoal_mesh,null,Transform2D.IDENTITY,Color("749485"))
		if _land_mesh.get_surface_count()>0: draw_mesh(_land_mesh,_land_paper if _land_paper else _fallback_land_paper)
		for segment in _coast_segments: _line(_world_pixel(segment[0]),_world_pixel(segment[1]),Color(0.68,0.52,0.26,0.65),2.8 if _compact else 3.6)
		for segment in _coast_segments: _line(_world_pixel(segment[0]),_world_pixel(segment[1]),INK,0.9 if _compact else 1.1)
		_label_boxes.clear()
		for mark: Dictionary in ship_marks():
			var p := _world_pixel(mark.position)
			if rect.has_point(p): _label_boxes.append(Rect2(p-Vector2(12,12),Vector2(24,24)))
		_draw_mountains(); _draw_routes(); _draw_ports(); _draw_ships()
	_draw_frame(rect)

func _draw_rhumbs(rect: Rect2) -> void:
	var origin := rect.position+rect.size*Vector2(0.76,0.28)
	var reach := rect.size.length()
	for i in (4 if _compact else 12):
		var angle := float(i)*PI/(4 if _compact else 12)
		var direction := Vector2(cos(angle),sin(angle))*reach
		_line(origin-direction,origin+direction,Color(0.75,0.67,0.43,0.10 if _compact else 0.15),0.7)

func _draw_waves(rect: Rect2) -> void:
	var spacing := 32.0 if _compact else 42.0
	for y in range(int(rect.position.y+12),int(rect.end.y-8),int(spacing)):
		var offset := spacing*0.65 if posmod(int((y-rect.position.y)/spacing),2) else 0.0
		for x in range(int(rect.position.x+8+offset),int(rect.end.x-18),int(spacing*1.6)):
			var points := PackedVector2Array()
			for i in 9: points.append(Vector2(x+i*2,y+sin(float(i)*PI/4)*2))
			draw_polyline(points,Color(0.07,0.24,0.28,0.21),0.7,true)
			if not _compact:
				for i in points.size(): points[i]+=Vector2(0,2)
				draw_polyline(points,Color(0.69,0.75,0.58,0.12),0.6,true)

func _draw_mountains() -> void:
	var drawn: Array = []
	for mountain in _mountains:
		var p := _world_pixel(mountain.point)
		if not map_rect().grow(-9).has_point(p): continue
		if drawn.any(func(existing):return existing.distance_to(p)<(11 if _compact else 14)): continue
		drawn.append(p)
		var height := clampf(float(mountain.height)*0.05,3,7)
		var ridge := PackedVector2Array([p+Vector2(-5,3),p+Vector2(-4,1),p+Vector2(-2,-height*0.45),p+Vector2(0,-height),p+Vector2(2,-height*0.3),p+Vector2(4,1),p+Vector2(5,3)])
		draw_polyline(ridge,Color(0.27,0.25,0.16,0.56),0.8,true)
		for i in 3: _line(p+Vector2(i*0.8,-height+i*1.7),p+Vector2(i*0.8+2.6,2),Color(0.30,0.27,0.16,0.30),0.6)

func _draw_routes() -> void:
	var waypoint: Dictionary = _overlays.get("waypoint",{}); var player := _ship_position(_player())
	if not waypoint.is_empty() and not player.is_empty():
		_dotted(projected(player),projected(waypoint),Color("765b34"))
	for route: Dictionary in _overlays.get("routes",[]):
		var points: Array = route.get("points",[])
		for i in range(1,points.size()): _dotted(projected(points[i-1]),projected(points[i]),Color(0.39,0.29,0.13,0.6))
	for site: Dictionary in _overlays.get("landSites",[]):
		var p := projected(site)
		if map_rect().grow(-5).has_point(p):
			draw_rect(Rect2(p-Vector2(2,2),Vector2(4,4)),Color("6e5635")); _label_boxes.append(Rect2(p-Vector2(4,4),Vector2(8,8)))
	for objective: Dictionary in _overlays.get("activeObjectives",[]):
		var p := projected(objective.get("position",{}))
		if not map_rect().grow(-9).has_point(p): continue
		draw_arc(p,7,0,TAU,20,Parchment.CINNABAR,1.5,true)
		_label_boxes.append(Rect2(p-Vector2(8,8),Vector2(16,16)))
		if not _compact: _label(Text.display_text(str(objective.get("label",""))),p+Vector2(12,14),13,map_rect(),_label_boxes)
	if not waypoint.is_empty():
		var p := projected(waypoint)
		if map_rect().grow(-8).has_point(p):
			draw_line(p+Vector2(-6,0),p+Vector2(6,0),Parchment.CINNABAR,1.5,true); draw_line(p+Vector2(0,-6),p+Vector2(0,6),Parchment.CINNABAR,1.5,true)
			_label_boxes.append(Rect2(p-Vector2(8,8),Vector2(16,16)))

func _dotted(a: Vector2, b: Vector2, color: Color) -> void:
	var clipped := _clip_line(a,b)
	if clipped.size()!=2: return
	var delta := clipped[1]-clipped[0]; var distance := delta.length()
	for step in range(0,int(distance),10):
		var start := clipped[0]+delta.normalized()*step
		_line(start,start+delta.normalized()*minf(4,distance-step),color,1.5)

func _draw_ports() -> void:
	for port: Dictionary in _ports:
		var p := projected(port)
		if not map_rect().grow(-6).has_point(p): continue
		draw_circle(p,4.5,Color("ead49a")); draw_arc(p,4.5,0,TAU,16,INK,1.1,true)
		draw_rect(Rect2(p-Vector2(1.5,1.5),Vector2(3,3)),Color("77572e"))
	for label: Dictionary in _port_labels(_label_boxes): _draw_label(label)

func _port_labels(occupied: Array) -> Array:
	var result: Array = []; var visible: Array = []; var boxes := occupied.duplicate()
	var rect := map_rect(); var position := _ship_position(_player())
	var focus := Vector2(float(position.get("x",view_bounds().get_center().x)),float(position.get("z",view_bounds().get_center().y)))
	for i in _ports.size():
		var port: Dictionary = _ports[i]; var p := projected(port)
		if not rect.grow(-6).has_point(p): continue
		var world := Vector2(float(port.get("x",0)),float(port.get("z",0)))
		visible.append({"port":port,"point":p,"distance":focus.distance_squared_to(world),"order":i})
		boxes.append(Rect2(p-Vector2(5,5),Vector2(10,10)))
	visible.sort_custom(func(a,b):return a.order<b.order if is_equal_approx(a.distance,b.distance) else a.distance<b.distance)
	var font_size := 14 if _compact else 17
	for mark: Dictionary in visible:
		if result.size()>=(3 if _compact else 8): break
		var text: String = Text.display_text(str(mark.port.get("name","")))
		var width := _font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
		var candidates := [Vector2(9,-7),Vector2(9,font_size+6),Vector2(-9-width,-7),Vector2(-9-width,font_size+6)]
		for offset: Vector2 in candidates:
			var label := _fit_label(text,mark.point+offset,font_size,rect,boxes)
			if label.is_empty(): continue
			label.port_id=String(mark.port.get("id","")); result.append(label); boxes.append(label.box)
			break
	return result

func _fit_label(text: String, baseline: Vector2, font_size: int, bounds: Rect2, occupied: Array) -> Dictionary:
	if text.is_empty() or not _font: return {}
	var extent := _font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
	var position := Vector2(clampf(baseline.x,bounds.position.x+4,maxf(bounds.position.x+4,bounds.end.x-extent.x-4)),clampf(baseline.y,bounds.position.y+font_size+4,bounds.end.y-4))
	var box := Rect2(position-Vector2(0,font_size),extent).grow(3)
	if not bounds.encloses(box): return {}
	for existing: Rect2 in occupied:
		if existing.intersects(box): return {}
	return {"text":text,"position":position,"size":font_size,"box":box}

func _label(text: String, baseline: Vector2, font_size: int, bounds: Rect2, occupied: Array) -> bool:
	var label := _fit_label(text,baseline,font_size,bounds,occupied)
	if label.is_empty(): return false
	occupied.append(label.box); _draw_label(label)
	return true

func _draw_label(label: Dictionary) -> void:
	# Pale continuous ground keeps small live labels readable across sea and relief.
	draw_style_box(_label_ground(),label.box)
	draw_string_outline(_font,label.position,label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,label.size,1,Color("efdcaa"))
	draw_string(_font,label.position,label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,label.size,INK)

func _label_ground() -> StyleBoxFlat:
	var style := StyleBoxFlat.new(); style.bg_color=Color(Parchment.PAPER,0.96); style.set_corner_radius_all(2)
	return style

func _draw_ships() -> void:
	for mark: Dictionary in ship_marks():
		var p := _world_pixel(mark.position)
		if not map_rect().grow(-12).has_point(p): continue
		var direction: Vector2 = mark.direction; var normal := Vector2(-direction.y,direction.x)
		var color := Color("e2c989") if mark.flagship else Parchment.CINNABAR if mark.role=="hostile" else Parchment.SEA if mark.role=="ally" else Color("b38a45")
		var length := 8.0 if mark.flagship else 6.0
		var polygon := PackedVector2Array([p+direction*length,p-direction*length*.7+normal*4,p-direction*length*.45,p-direction*length*.7-normal*4])
		if mark.flagship: draw_circle(p,11,Color(0.99,0.90,0.58,0.17)); draw_arc(p,10,0,TAU,24,Color("765b34"),1,true)
		if mark.selected and not _compact and map_rect().grow(-16).has_point(p):
			draw_arc(p,14,0,TAU,32,Color("ebd8a0"),3,true)
			draw_arc(p,14,0,TAU,32,Color("684825"),1.2,true)
		draw_colored_polygon(polygon,color)
		var outline := polygon.duplicate(); outline.append(polygon[0]); draw_polyline(outline,INK,1.2,true)

func _draw_frame(rect: Rect2) -> void:
	draw_rect(Rect2(Vector2(3,3),size-Vector2(6,6)),Color("655336"),false,2); draw_rect(Rect2(Vector2(7,7),size-Vector2(14,14)),GOLD,false,1); draw_rect(rect,Color("7f7951"),false,1.2)
	var font_size := 18 if _compact else 24; var title_size := _title_font.get_string_size(_title,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
	draw_style_box(_cartouche(),Rect2(Vector2((size.x-title_size.x)/2-9,9),Vector2(title_size.x+18,23 if _compact else 33)))
	draw_string(_title_font,Vector2((size.x-title_size.x)/2,26 if _compact else 34),_title,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,INK)
	_draw_compass(Vector2(size.x-27,22 if _compact else 29))
	var seal := Rect2(Vector2(17,13),Vector2(17,17) if _compact else Vector2(22,22))
	draw_rect(seal,Color(0.53,0.19,0.13,0.12)); draw_rect(seal,Color("944530"),false,1.2); draw_rect(seal.grow(-2.5),Color("944530"),false,0.6)
	draw_string(_title_font,seal.position+Vector2(3,seal.size.y-4),"海",HORIZONTAL_ALIGNMENT_LEFT,-1,11 if _compact else 15,Color("944530"))
	for corner in [Vector2(12,12),Vector2(size.x-12,12),Vector2(12,size.y-12),Vector2(size.x-12,size.y-12)]: draw_arc(corner,5,0,TAU,18,GOLD,1,true)
	var legend := "金舟旗舰 · 青舟同盟 · 朱舟敌舰" if not _compact else "点击展开航图"
	draw_rect(Rect2(Vector2(12,size.y-29),Vector2(size.x-24,21)),Color("dcc38a"))
	draw_string(_font,Vector2(16,size.y-12),legend,HORIZONTAL_ALIGNMENT_LEFT,maxf(0,size.x-32),12 if _compact else 14,INK)
	if not _compact:
		var scale := minf(400,view_bounds().size.x/5); var length := scale/view_bounds().size.x*rect.size.x; var p := Vector2(rect.end.x-length-8,size.y-23)
		draw_rect(Rect2(p-Vector2(4,6),Vector2(length+8,25)),Color("dcc38a"))
		draw_line(p,p+Vector2(length,0),INK,1.5); draw_line(p-Vector2(0,3),p+Vector2(0,3),INK,1); draw_line(p+Vector2(length,-3),p+Vector2(length,3),INK,1)
		draw_string(_font,p+Vector2(0,14),str(int(scale))+" 米",HORIZONTAL_ALIGNMENT_LEFT,-1,11,INK)

func _draw_compass(center: Vector2) -> void:
	var radius := 9.0 if _compact else 12.0
	draw_circle(center,radius+3,Color("dcc38a")); draw_arc(center,radius+2,0,TAU,32,GOLD,0.8,true)
	for i in 8:
		var direction := Vector2(cos(float(i)*PI/4),sin(float(i)*PI/4))
		var normal := Vector2(-direction.y,direction.x)
		var reach := radius if i%2==0 else radius*0.62
		draw_colored_polygon(PackedVector2Array([center+direction*reach,center+normal*2,center]),INK if i%2==0 else GOLD)
		draw_line(center+direction*reach,center-normal*2,INK,0.7,true)
	draw_circle(center,1.8,Color("e9d39e"))
	draw_string(_font,center+Vector2(-4,-radius-2),"北",HORIZONTAL_ALIGNMENT_LEFT,-1,9,INK)

func _cartouche() -> StyleBoxFlat:
	var style := StyleBoxFlat.new(); style.bg_color=Parchment.PAPER; style.border_color=GOLD; style.set_border_width_all(1); style.set_corner_radius_all(3)
	return style

func _gui_input(event: InputEvent) -> void:
	if not _configured or not event is InputEventMouseButton: return
	if not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT: return
	if not map_rect().has_point(event.position) or map_rect().size.x<=0 or map_rect().size.y<=0: return
	if _compact: chart_requested.emit()
	else: waypoint_requested.emit(unprojected(event.position))
	accept_event()

func dispose() -> void:
	_configured=false; _height=Callable(); _ports.clear(); _native.clear(); _overlays.clear(); _height_cache.clear()
	_land_polygons.clear(); _shoal_polygons.clear(); _coast_segments.clear(); _mountains.clear(); _terrain_ready=false; queue_redraw()
	_land_mesh=null; _shoal_mesh=null; _mesh_ready=false; _label_boxes.clear()

func _exit_tree() -> void: dispose()
