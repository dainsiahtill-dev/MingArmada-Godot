extends Control
## Geographic reading atlas. Longitude/latitude never become gameplay x/z.
signal return_requested
signal main_menu_requested
signal port_selected(port: Dictionary)
const Parchment = preload("res://game/ui/shared/parchment_theme.gd")
const Maritime = preload("res://game/ui/shared/maritime_art_theme.gd")
const LAND_PATH := "res://assets/data/cartography/east_asia_land.json"
const PLACES_PATH := "res://assets/data/cartography/atlas_places.json"
const PAPER_PATH := "res://assets/ui/ming_maritime/chart-paper.png"
const FALLBACK_PAPER := "res://assets/art/maps/ming-nautical-land-paper-v2.png"
const STANDARD_PARALLEL := 0.90630778703665 # cos(25 degrees)
const INK := Color("463e2c")
const GOLD := Color("a58a51")
const SEA := Color("839b9b")
const LAND := Color("dbc692")
class MapSurface:
	extends Control
	var atlas: Control
	func _draw() -> void:
		if is_instance_valid(atlas): atlas._draw_map(self)
var startup_options: Dictionary = {}
var startup_receipt: Dictionary = {"ok":false,"mode":"world-atlas"}
var _configured := false
var _disposed := false
var _bounds := Rect2(92,-12,56,57)
var _view := Rect2(92,-12,56,57)
var _ports: Array = []
var _labels: Array = []
var _land: Array = []
var _relief: Array[Vector2] = []
var _source_sha := ""
var _data_sha := ""
var _selected := "xiamen"
var _engraving := true
var _zoom := 1.0
var _surface: Control
var _detail: ScrollContainer
var _detail_body: VBoxContainer
var _detail_title: Label
var _detail_subtitle: Label
var _detail_description: Label
var _detail_coordinates: Label
var _selector: OptionButton
var _title: Label
var _subtitle: Label
var _footer: Label
var _buttons: Array[Button] = []
var _paper: Texture2D
var _vignette: TextureRect
var _land_paper: Texture2D
var _font: Font
var _title_font: Font
var _mesh: ArrayMesh
var _mesh_view := Rect2()
var _mesh_size := Vector2.ZERO
var _geometry := {"vertices":0,"triangles":0,"land_polygons":0,"failed_polygons":0,"mesh_builds":0}
var _pressed := false
var _dragged := false
var _press_position := Vector2.ZERO

func _ready() -> void:
	if size==Vector2.ZERO: set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP; clip_contents=true
	theme=Parchment.create(); _font=theme.default_font; _title_font=Parchment.title_font()
	_paper=_texture(PAPER_PATH)
	if _paper==null: _paper=_texture(FALLBACK_PAPER)
	_land_paper=_texture(FALLBACK_PAPER)
	_build_ui(); resized.connect(_layout)
	if not _configured: configure(startup_options)
	_layout()

func _texture(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null

func configure(options: Dictionary = {}) -> Dictionary:
	if options.has("engraving") and not options.engraving is bool:
		return {"ok":false,"reason":"invalid-atlas-style"}
	var raw: Variant=JSON.parse_string(FileAccess.get_file_as_string(LAND_PATH))
	var places: Variant=JSON.parse_string(FileAccess.get_file_as_string(PLACES_PATH))
	if not raw is Dictionary or raw.get("coordinateSystem")!="EPSG:4326" or not raw.get("polygons") is Array or not places is Dictionary or not places.get("ports") is Array:
		return {"ok":false,"reason":"atlas-data-unavailable"}
	_disposed=false; _engraving=options.get("engraving",true)
	_land.clear(); _relief.clear(); _ports=places.ports.duplicate(true); _labels=places.get("labels",[]).duplicate(true)
	var b: Array=raw.bounds; _bounds=Rect2(float(b[0]),float(b[1]),float(b[2])-float(b[0]),float(b[3])-float(b[1]))
	_geometry={"vertices":0,"triangles":0,"land_polygons":0,"failed_polygons":0,"mesh_builds":0}
	for ring: Array in raw.polygons:
		var polygon:=PackedVector2Array()
		for coordinate: Array in ring: polygon.append(Vector2(float(coordinate[0]),float(coordinate[1])))
		var triangles:=Geometry2D.triangulate_polygon(polygon)
		if triangles.is_empty(): _geometry.failed_polygons+=1; continue
		_land.append({"points":polygon,"triangles":triangles})
		_geometry.vertices+=polygon.size(); _geometry.triangles+=triangles.size()/3
	_geometry.land_polygons=_land.size()
	if _geometry.failed_polygons>0: return {"ok":false,"reason":"invalid-coast-polygon"}
	for lat in range(-8,42,3):
		for lon in range(96,142,3):
			if posmod(lon*7+lat*3,5)>=2: continue
			var p:=Vector2(lon+sin(lon*.73+lat*.31)*.8,lat+cos(lon*.47-lat*.89)*.7)
			if _is_land(p) and not _near_port(p,1.5): _relief.append(p)
	_source_sha=raw.sourceSha256; _data_sha=FileAccess.get_sha256(LAND_PATH)
	_configured=true; _selected="xiamen"; reset_view(); _populate_selector(); _refresh_details()
	startup_receipt={"ok":true,"mode":"world-atlas","source":"bundled-geographic-data","source_sha256":_source_sha}
	_layout(); return startup_receipt.duplicate(true)

func _is_land(point: Vector2) -> bool:
	for polygon: Dictionary in _land:
		if Geometry2D.is_point_in_polygon(point,polygon.points): return true
	return false

func _near_port(point: Vector2, degrees: float) -> bool:
	for port: Dictionary in _ports:
		if point.distance_to(Vector2(port.lon,port.lat))<degrees: return true
	return false

func data_bounds() -> Rect2: return _bounds
func view_bounds() -> Rect2: return _view
func details_rect() -> Rect2:
	if _detail: return Rect2(_detail.position,_detail.size)
	return Rect2()

func map_rect() -> Rect2:
	var wide:=size.x>=1000
	var tiny:=size.x<460
	var top:=156.0 if tiny else 132.0
	var detail_height:=clampf(size.y*0.27,130 if tiny else 165,255)
	var bottom:=size.y-50.0 if wide else maxf(280.0,size.y-detail_height-44.0)
	var available:=Rect2(Vector2(26,top),Vector2(maxf(80,size.x-(354 if wide else 52)),maxf(100,bottom-top)))
	var aspect:=_bounds.size.x*STANDARD_PARALLEL/_bounds.size.y
	var extent:=Vector2(minf(available.size.x,available.size.y*aspect),minf(available.size.y,available.size.x/aspect))
	return Rect2(available.position+(available.size-extent)/2,extent)

func project(point: Vector2) -> Vector2:
	var rect:=map_rect()
	return rect.position+Vector2((point.x-_view.position.x)/_view.size.x*rect.size.x,(_view.end.y-point.y)/_view.size.y*rect.size.y)

func unproject(pixel: Vector2) -> Vector2:
	var rect:=map_rect()
	if rect.size.x<=0 or rect.size.y<=0: return Vector2.INF
	return Vector2(_view.position.x+(pixel.x-rect.position.x)/rect.size.x*_view.size.x,_view.end.y-(pixel.y-rect.position.y)/rect.size.y*_view.size.y)

func reset_view() -> void:
	_view=_bounds; _zoom=1.0; _invalidate_mesh()

func zoom_at(factor: float, pixel: Vector2 = Vector2.INF) -> bool:
	if not _configured or _disposed or not is_finite(factor) or factor<=0: return false
	var rect:=map_rect(); var anchor:=rect.get_center() if pixel==Vector2.INF else pixel
	if not anchor.is_finite() or not rect.has_point(anchor): return false
	var point:=unproject(anchor); var next_zoom:=clampf(_zoom*factor,1.0,6.0)
	var extent:=_bounds.size/next_zoom
	var fraction:=(anchor-rect.position)/rect.size
	_view=Rect2(Vector2(point.x-fraction.x*extent.x,point.y-(1.0-fraction.y)*extent.y),extent)
	_zoom=next_zoom; _clamp_view(); _invalidate_mesh(); return true

func pan_pixels(delta: Vector2) -> bool:
	if not _configured or _disposed or not delta.is_finite(): return false
	var rect:=map_rect()
	_view.position+=Vector2(-delta.x/rect.size.x*_view.size.x,delta.y/rect.size.y*_view.size.y)
	_clamp_view(); _invalidate_mesh(); return true

func _clamp_view() -> void:
	_view.position=Vector2(clampf(_view.position.x,_bounds.position.x,_bounds.end.x-_view.size.x),clampf(_view.position.y,_bounds.position.y,_bounds.end.y-_view.size.y))

func select_port(id: String) -> bool:
	if _disposed or not _configured: return false
	for port: Dictionary in _ports:
		if port.id==id:
			_selected=id; _refresh_details()
			port_selected.emit(port.duplicate(true)); _redraw(); return true
	return false

func focus_selected() -> void:
	var port:=selected_port()
	if port.is_empty(): return
	_zoom=3.2; var extent:=_bounds.size/_zoom
	_view=Rect2(Vector2(port.lon,port.lat)-extent/2,extent); _clamp_view(); _invalidate_mesh()

func selected_port() -> Dictionary:
	for port: Dictionary in _ports:
		if port.id==_selected: return port.duplicate(true)
	return {}

func set_engraving(enabled: bool) -> void:
	_engraving=enabled; _redraw()

func _invalidate_mesh() -> void:
	_mesh=null; _redraw()

func _redraw() -> void:
	queue_redraw()
	if _surface: _surface.queue_redraw()

func _build_ui() -> void:
	_surface=MapSurface.new(); _surface.name="GeographicChart"; _surface.atlas=self
	_surface.mouse_filter=Control.MOUSE_FILTER_IGNORE; _surface.clip_contents=true; add_child(_surface)
	_vignette=TextureRect.new(); _vignette.name="AtlasVignette"
	_vignette.texture=_texture("res://assets/ui/ming_maritime/atlas-vignette.png")
	_vignette.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_vignette.mouse_filter=Control.MOUSE_FILTER_IGNORE; add_child(_vignette)
	_title=_make_label(self,"AtlasTitle","东洋南海舆图",32)
	_title.add_theme_font_override("font",_title_font)
	_subtitle=_make_label(self,"AtlasSubtitle","山海相望，帆路相通",16)
	for specification in [["ZoomIn","＋"],["ZoomOut","－"],["ResetView","全图"],["ReturnFromAtlas","返回"]]:
		var button:=Button.new(); button.name=specification[0]; button.text=specification[1]
		add_child(button); _buttons.append(button)
	_buttons[0].pressed.connect(func(): zoom_at(1.35))
	_buttons[1].pressed.connect(func(): zoom_at(1.0/1.35))
	_buttons[2].pressed.connect(reset_view)
	_buttons[3].pressed.connect(_return)
	_selector=OptionButton.new(); _selector.name="HarbourSelector"; add_child(_selector)
	_selector.get_popup().theme=Maritime.create()
	_selector.item_selected.connect(func(index): select_port(_selector.get_item_metadata(index)))
	_detail=ScrollContainer.new(); _detail.name="HarbourDetails"; _detail.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; add_child(_detail)
	_detail_body=VBoxContainer.new(); _detail_body.size_flags_horizontal=Control.SIZE_EXPAND_FILL; _detail_body.add_theme_constant_override("separation",15); _detail.add_child(_detail_body)
	_make_label(_detail_body,"HarbourSection","港 口 志",16)
	_detail_title=_make_label(_detail_body,"HarbourName","",30); _detail_title.add_theme_font_override("font",_title_font)
	_detail_subtitle=_make_label(_detail_body,"HarbourRegion","",16)
	_detail_description=_make_label(_detail_body,"HarbourDescription","",18)
	_detail_coordinates=_make_label(_detail_body,"HarbourCoordinates","",14)
	var focus:=Button.new(); focus.name="FocusHarbour"; focus.text="放大这片海域"; focus.custom_minimum_size.y=42; _detail_body.add_child(focus); focus.pressed.connect(focus_selected)
	_make_label(_detail_body,"AtlasReadingHint","点击港口看图志\n拖动图面 · 滚轮缩放",14)
	_footer=_make_label(self,"AtlasFooter","东至日本，南至爪哇  ·  一卷阅尽东洋南海",14)
	_populate_selector(); _refresh_details()

func _make_label(parent: Node, node_name: String, text: String, font_size: int) -> Label:
	var label:=Label.new(); label.name=node_name; label.text=text
	label.add_theme_font_size_override("font_size",font_size); label.add_theme_color_override("font_color",INK)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE; parent.add_child(label); return label

func _populate_selector() -> void:
	if not _selector: return
	_selector.clear()
	for port: Dictionary in _ports:
		_selector.add_item(port.name); _selector.set_item_metadata(_selector.item_count-1,port.id)

func _refresh_details() -> void:
	if not _detail_title: return
	var port:=selected_port()
	if port.is_empty(): return
	_detail_title.text=port.name; _detail_subtitle.text=port.subtitle+"  ·  "+port.region
	_detail_description.text=port.description
	_detail_coordinates.text="东经 %.2f°  ·  %s %.2f°" % [port.lon,"北纬" if port.lat>=0 else "南纬",absf(port.lat)]
	for index in _selector.item_count:
		if _selector.get_item_metadata(index)==_selected: _selector.select(index)

func _layout() -> void:
	if not _surface or _disposed: return
	var wide:=size.x>=1000; var tiny:=size.x<460; var rect:=map_rect()
	_surface.position=rect.position; _surface.size=rect.size
	_title.position=Vector2(28,20); _title.size=Vector2(maxf(230,size.x-350),42)
	_title.add_theme_font_size_override("font_size",32 if size.x>=600 else 26)
	_subtitle.position=Vector2(30,67); _subtitle.size=Vector2(maxf(180,size.x-60),24)
	_subtitle.visible=not tiny
	for index in _buttons.size():
		_buttons[index].position=Vector2((size.x-242)/2+index*62,108) if tiny else Vector2(size.x-28-(4-index)*62,24 if size.x>=700 else 93)
		_buttons[index].size=Vector2(56,38)
	_selector.position=Vector2(28,64 if tiny else 93); _selector.size=Vector2(size.x-56 if tiny else maxf(120,minf(218,size.x-312)),34)
	_detail_body.custom_minimum_size.x=0
	if wide:
		_detail.position=Vector2(rect.end.x+42,145); _detail.size=Vector2(minf(310,size.x-_detail.position.x-28),maxf(160,size.y-205))
		# The wide folio has room for a period illustration beneath the port text.
		# It is decoration only and never overlaps the geographic picking surface.
		_vignette.visible=size.y>=780 and _vignette.texture!=null
		if _vignette.visible:
			_vignette.size=Vector2(_detail.size.x,220)
			_vignette.position=Vector2(_detail.position.x,size.y-270)
			_detail.size.y=minf(_detail.size.y,_vignette.position.y-_detail.position.y-22)
	else:
		_vignette.hide()
		_detail.position=Vector2(28,maxf(rect.end.y+18,size.y-clampf(size.y*0.27,130 if tiny else 165,255)-25))
		_detail.size=Vector2(maxf(100,size.x-56),maxf(100,size.y-_detail.position.y-42))
	_footer.position=Vector2(28,size.y-31); _footer.size=Vector2(maxf(50,size.x-56),24)
	_footer.text="东洋南海 · 选港阅图" if tiny else "东至日本，南至爪哇  ·  一卷阅尽东洋南海"
	if _mesh_size!=rect.size: _mesh=null
	_redraw()

func _draw() -> void:
	if not _font: return
	draw_rect(Rect2(Vector2.ZERO,size),Color("ead9af"))
	if _paper: draw_texture_rect(_paper,Rect2(Vector2.ZERO,size),false,Color(1,1,1,0.26))
	for inset in [7.0,12.0]: draw_rect(Rect2(Vector2.ONE*inset,size-Vector2.ONE*inset*2),GOLD,false,1.0)
	draw_line(Vector2(28,84),Vector2(size.x-28,84),Color(GOLD,0.6),1)
	var rect:=map_rect()
	draw_rect(rect.grow(5),GOLD,false,1); draw_rect(rect.grow(8),Color(GOLD,0.48),false,1)
	if size.x>=1000: draw_line(Vector2(rect.end.x+22,145),Vector2(rect.end.x+22,size.y-56),Color(GOLD,0.58),1)
	for corner in [Vector2(20,20),Vector2(size.x-20,20),Vector2(20,size.y-20),Vector2(size.x-20,size.y-20)]:
		draw_arc(corner,4,0,TAU,16,GOLD,1,true)

func _prepare_mesh() -> void:
	if _mesh and _mesh_view==_view and _mesh_size==_surface.size: return
	_mesh_view=_view; _mesh_size=_surface.size
	var vertices:=PackedVector2Array(); var triangles:=PackedInt32Array(); var uvs:=PackedVector2Array()
	for polygon: Dictionary in _land:
		var offset:=vertices.size()
		for coordinate: Vector2 in polygon.points:
			vertices.append(project(coordinate)-map_rect().position); uvs.append(coordinate/24.0)
		for index: int in polygon.triangles: triangles.append(offset+index)
	_mesh=ArrayMesh.new()
	if not triangles.is_empty():
		var arrays: Array=[]; arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_TEX_UV]=uvs; arrays[Mesh.ARRAY_INDEX]=triangles
		_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	_geometry.mesh_builds+=1

func _draw_map(surface: Control) -> void:
	if not _configured or _disposed or not _font: return
	var rect:=Rect2(Vector2.ZERO,surface.size); var offset:=map_rect().position
	surface.draw_rect(rect,SEA)
	if _paper: surface.draw_texture_rect(_paper,rect,false,Color(1,1,1,0.12))
	if _engraving: _draw_sea(surface)
	_prepare_mesh()
	if _mesh.get_surface_count()>0:
		surface.texture_repeat=CanvasItem.TEXTURE_REPEAT_ENABLED
		surface.draw_mesh(_mesh,_land_paper,Transform2D.IDENTITY,LAND if _land_paper==null else Color("f5eddb"))
	for polygon: Dictionary in _land:
		var points:=PackedVector2Array()
		for p: Vector2 in polygon.points: points.append(project(p)-offset)
		points.append(points[0])
		if _engraving: surface.draw_polyline(points,Color(0.31,0.37,0.34,0.36),3.4,true)
		surface.draw_polyline(points,INK,0.95,true)
	if _engraving: _draw_relief(surface)
	_draw_labels(surface); _draw_ports(surface)
	if _engraving and surface.size.x>=250: _draw_compass(surface,Vector2(surface.size.x-53,surface.size.y-65)); _draw_junk(surface,Vector2(surface.size.x*0.84,surface.size.y*0.57))
	surface.draw_rect(rect,INK,false,1.1)

func _draw_sea(surface: Control) -> void:
	var rect:=Rect2(Vector2.ZERO,surface.size)
	for y in range(24,int(rect.end.y),34):
		for x in range(20+posmod(y,3)*7,int(rect.end.x),46):
			var points:=PackedVector2Array()
			for index in 7: points.append(Vector2(x+index*2,y+sin(index*PI/3)*1.4))
			surface.draw_polyline(points,Color(0.20,0.29,0.29,0.13),0.7,true)
	var origin:=Vector2(rect.size.x*0.70,rect.size.y*0.25)
	for index in 8:
		var direction:=Vector2.from_angle(index*PI/8)*rect.size.length()
		surface.draw_line(origin-direction,origin+direction,Color(0.85,0.79,0.60,0.12),0.7,true)

func _draw_relief(surface: Control) -> void:
	var offset:=map_rect().position
	for p: Vector2 in _relief:
		if not _view.has_point(p): continue
		var center:=project(p)-offset
		var h:=clampf(surface.size.y/110,3.5,7.0)
		var points:=PackedVector2Array([center+Vector2(-7,4),center+Vector2(-3,-h*.2),center+Vector2(0,-h),center+Vector2(3,-h*.3),center+Vector2(7,4)])
		surface.draw_polyline(points,Color(INK,0.48),0.8,true)
		for index in 3: surface.draw_line(center+Vector2(index*.8,-h+index*1.5),center+Vector2(index*1.4+2,3),Color(INK,0.25),0.6,true)

func _draw_labels(surface: Control) -> void:
	if surface.size.x<250: return
	var offset:=map_rect().position; var occupied: Array=[]
	for port: Dictionary in _ports:
		var p:=Vector2(port.lon,port.lat)
		if _view.has_point(p): occupied.append(Rect2(project(p)-offset-Vector2(9,9),Vector2(70,28)))
	for label: Array in _labels:
		var coordinate:=Vector2(label[1],label[2])
		if not _view.has_point(coordinate): continue
		var font_size:=int(clampf(float(label[3])*surface.size.y/850,14,32))
		var text_size:=_title_font.get_string_size(label[0],HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
		var p:=project(coordinate)-offset; var box:=Rect2(p-text_size/2,text_size)
		if not Rect2(Vector2.ZERO,surface.size).grow(-7).encloses(box): continue
		var blocked:=false
		for existing: Rect2 in occupied:
			if box.intersects(existing): blocked=true; break
		if blocked: continue
		surface.draw_string(_title_font,p+Vector2(-text_size.x/2,font_size*.35),label[0],HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color(INK,0.78))
		occupied.append(box)

func _draw_ports(surface: Control) -> void:
	var offset:=map_rect().position; var occupied: Array=[]
	var ports:=_ports.duplicate()
	ports.sort_custom(func(a,b): return a.id==_selected if a.id==_selected or b.id==_selected else false)
	for port: Dictionary in ports:
		var coordinate:=Vector2(port.lon,port.lat)
		if not _view.has_point(coordinate): continue
		var p:=project(coordinate)-offset; var selected: bool=port.id==_selected
		surface.draw_circle(p,3.7,Color("f0dcaa")); surface.draw_arc(p,3.7,0,TAU,20,INK,1.1,true)
		if selected: surface.draw_arc(p,8,0,TAU,28,Color("904c38"),1.4,true)
		if surface.size.x<250 and not selected: continue
		var font_size:=15 if surface.size.x>=450 else 13
		var extent:=_font.get_string_size(port.name,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
		for placement in [Vector2(9,-6),Vector2(9,17),Vector2(-extent.x-9,-6),Vector2(-extent.x-9,17)]:
			var baseline: Vector2=p+placement
			var box:=Rect2(baseline-Vector2(2,font_size),extent+Vector2(4,4))
			if not Rect2(Vector2.ZERO,surface.size).grow(-3).encloses(box): continue
			var blocked:=false
			for existing: Rect2 in occupied:
				if existing.intersects(box): blocked=true; break
			if blocked: continue
			surface.draw_rect(box,Color(0.91,0.83,0.64,0.93))
			surface.draw_string(_font,baseline,port.name,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color("833e2d") if selected else INK)
			occupied.append(box.grow(2)); break

func _draw_compass(surface: Control, center: Vector2) -> void:
	var radius:=26.0 if surface.size.x>450 else 18.0
	surface.draw_arc(center,radius+5,0,TAU,64,Color(INK,0.6),0.7,true)
	for index in 16:
		var direction:=Vector2.from_angle(index*PI/8)
		var normal:=Vector2(-direction.y,direction.x)
		var reach:=radius if index%2==0 else radius*.55
		surface.draw_colored_polygon(PackedVector2Array([center+direction*reach,center+normal*2.6,center]),INK if index%2==0 else GOLD)
		surface.draw_line(center+direction*reach,center-normal*2.6,INK,.6,true)
	surface.draw_string(_title_font,center+Vector2(-6,-radius-8),"北",HORIZONTAL_ALIGNMENT_LEFT,-1,13,INK)

func _draw_junk(surface: Control, center: Vector2) -> void:
	if surface.size.x<330: return
	var color:=Color(INK,0.62)
	var hull:=PackedVector2Array([center+Vector2(-23,10),center+Vector2(-13,19),center+Vector2(19,17),center+Vector2(29,7),center+Vector2(-23,10)])
	surface.draw_polyline(hull,color,1.1,true)
	for mast in [Vector2(-6,-20),Vector2(10,-29)]:
		surface.draw_line(center+mast,center+Vector2(mast.x,11),color,1.1,true)
		var sail:=PackedVector2Array([center+mast+Vector2(1,1),center+mast+Vector2(16,4),center+mast+Vector2(19,23),center+mast+Vector2(1,25)])
		surface.draw_colored_polygon(sail,Color(0.85,0.79,0.60,0.65)); var outline:=sail.duplicate(); outline.append(sail[0]); surface.draw_polyline(outline,color,.8,true)
		for batten in 4: surface.draw_line(center+mast+Vector2(1,5+batten*5),center+mast+Vector2(16+batten,7+batten*5),color,.7,true)
	for index in 3: surface.draw_line(center+Vector2(-27+index*5,23+index*3),center+Vector2(20-index*4,21+index*3),Color(color,0.4),.7,true)

func _gui_input(event: InputEvent) -> void:
	if not _configured or _disposed: return
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:
			_pressed=false; _dragged=false
			return
		if not map_rect().has_point(event.position): return
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_at(1.25 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 0.8,event.position); accept_event()
		elif event.button_index==MOUSE_BUTTON_LEFT:
			if event.pressed:
				_pressed=true; _dragged=false; _press_position=event.position
				_pick_port(event.position)
			else: _pressed=false
			accept_event()
	elif event is InputEventMouseMotion and _pressed:
		if event.position.distance_to(_press_position)>4: _dragged=true
		if _dragged: pan_pixels(event.relative); accept_event()

func _pick_port(pixel: Vector2) -> void:
	var closest: Dictionary={}; var distance:=18.0
	for port: Dictionary in _ports:
		var coordinate:=Vector2(port.lon,port.lat)
		if not _view.has_point(coordinate): continue
		var next:=project(coordinate).distance_to(pixel)
		if next<distance: closest=port; distance=next
	if not closest.is_empty(): select_port(closest.id)

func _return() -> void:
	if _disposed: return
	return_requested.emit(); main_menu_requested.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:
		_return(); get_viewport().set_input_as_handled()

func inspection_snapshot() -> Dictionary:
	return {"ready":_configured and not _disposed,"disposed":_disposed,"geography_basis":"longitude-latitude","projection":"equirectangular-standard-parallel-25N","data_bounds":_bounds,"view_bounds":_view,"zoom":_zoom,"selected_port":selected_port(),"engraving":_engraving,"geometry":_geometry.duplicate(true),"source_sha256":_source_sha,"data_sha256":_data_sha,"paper":PAPER_PATH if ResourceLoader.exists(PAPER_PATH) else FALLBACK_PAPER,"scope":"Read-only geographic atlas; no campaign navigation, fleet pose, save or settings writes."}

func activate_entry() -> void:
	if not _disposed: get_window().title="海上明旗 · 东洋南海舆图"

func dispose() -> void:
	_disposed=true; _configured=false; _pressed=false; _land.clear(); _ports.clear(); _labels.clear(); _relief.clear(); _mesh=null
	_geometry={"vertices":0,"triangles":0,"land_polygons":0,"failed_polygons":0,"mesh_builds":0}
	_redraw()

func _exit_tree() -> void: dispose()
