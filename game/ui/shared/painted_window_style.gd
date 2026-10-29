class_name PaintedWindowStyle
extends StyleBox
## Quiet reading surface plus a generated frame/shadow outside native layout.
## Getters expose the original body/edge textures for native pixel acceptance.
## This resource issues only native StyleBoxTexture.draw calls; it paints no
## procedural line, rectangle, blur, shadow, lettering or replacement artwork.
@export var _body: StyleBoxTexture
@export var _edge: StyleBoxTexture
@export var _outer_expansion := Vector4.ZERO
static var _edge_templates: Dictionary = {}

static func compose(body: StyleBoxTexture,edge: StyleBoxTexture) -> StyleBox:
	if body==null or body.texture==null or edge==null or edge.texture==null: return null
	# Self-load also works before an editor has refreshed its global-class cache.
	var result = load("res://game/ui/shared/painted_window_style.gd").new()
	result._body=body.duplicate(false)
	result._edge=edge.duplicate(false)
	# The outer public margins are applied once to the shared drawing baseline.
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		result.set_content_margin(side,body.get_margin(side))
		result.set_expand_margin(side,body.get_expand_margin(side))
		result._body.set_expand_margin(side,0)
	return result

func get_body_style() -> StyleBoxTexture: return _body

func get_edge_style() -> StyleBoxTexture: return _edge

func set_expand_margin(side: Side,value: float) -> void:
	_outer_expansion[side]=value
	emit_changed()

func get_expand_margin(side: Side) -> float: return _outer_expansion[side]

func set_expand_margin_all(value: float) -> void:
	_outer_expansion=Vector4(value,value,value,value)
	emit_changed()

static func framed_edge(texture: Texture2D) -> StyleBoxTexture:
	if texture==null: return null
	var key := texture.get_instance_id()
	if _edge_templates.has(key): return _edge_templates[key].duplicate(false)
	var pixels := texture.get_image()
	if pixels==null or pixels.is_empty(): return null
	if pixels.is_compressed(): pixels.decompress()
	var horizontal := _opaque_span(pixels,true)
	var vertical := _opaque_span(pixels,false)
	if horizontal.x<0 or vertical.x<0: return null
	var result := StyleBoxTexture.new()
	result.texture=texture
	result.region_rect=Rect2(Vector2.ZERO,texture.get_size())
	result.draw_center=false
	var expansion := [horizontal.x+1,vertical.x+1,pixels.get_width()-horizontal.y+1,pixels.get_height()-vertical.y]
	var sides := [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]
	for index in range(4):
		# Seven extra source pixels protect the alpha falloff around the face.
		result.set_expand_margin(sides[index],expansion[index])
		result.set_texture_margin(sides[index],expansion[index]+7)
		result.set_content_margin(sides[index],0)
	_edge_templates[key]=result
	return result.duplicate(false)

static func _opaque_span(pixels: Image,horizontal: bool) -> Vector2i:
	var length := pixels.get_width() if horizontal else pixels.get_height()
	var first := -1
	var last := -1
	for index in range(length):
		var point := Vector2i(index,pixels.get_height()/2) if horizontal else Vector2i(pixels.get_width()/2,index)
		if pixels.get_pixelv(point).a>=200.0/255.0:
			if first<0: first=index
			last=index
	return Vector2i(first,last)

func _outer_rect(rect: Rect2) -> Rect2:
	return rect.grow_individual(get_expand_margin(SIDE_LEFT),get_expand_margin(SIDE_TOP),get_expand_margin(SIDE_RIGHT),get_expand_margin(SIDE_BOTTOM))

func _get_draw_rect(rect: Rect2) -> Rect2:
	var outer := _outer_rect(rect)
	if _edge==null: return outer
	return outer.grow_individual(_edge.get_expand_margin(SIDE_LEFT),_edge.get_expand_margin(SIDE_TOP),_edge.get_expand_margin(SIDE_RIGHT),_edge.get_expand_margin(SIDE_BOTTOM))

func _draw(to_canvas_item: RID,rect: Rect2) -> void:
	if _body==null or _edge==null: return
	var outer := _outer_rect(rect)
	_body.draw(to_canvas_item,outer)
	_edge.draw(to_canvas_item,outer)
