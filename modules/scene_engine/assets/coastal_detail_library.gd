extends RefCounted
## Small reusable native meshes, Y-up and grounded at y=0. No imported catalog.
## Composite props use a warm kind palette, linear neutral shading, one surface.
var _meshes: Dictionary = {}
var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _materials: Dictionary={}

func get_mesh(kind: String, variant: int = 0) -> ArrayMesh:
	var key := kind + str(variant)
	if _meshes.has(key): return _meshes[key]
	_vertices.clear(); _normals.clear(); _colors.clear()
	var wood := Color.html("8d6641")
	var dark := Color.html("423b31")
	var rope := Color.html("c6ac75")
	match kind:
		"coastal_tree":
			_tube(Vector3(0,-0.25,0),Vector3(0.25,4.8,0.1),0.25,wood,7)
			for index in 5:
				var angle:=index*2.399
				var crown:=Vector3(cos(angle)*1.55,4.2+(index%3)*0.65,sin(angle)*1.55)
				_tube(Vector3(0.15,2.9,0),crown,0.11,wood,6)
				_foliage(crown,1.6+(index%2)*0.3,Color.html("486b38") if index%2 else Color.html("66834a"))
			_foliage(Vector3(0.3,6.1,-0.1),1.8,Color.html("738b51"))
		"harbor_house":
			# Deep compact masonry plinth embeds on sampled slopes; no floating base.
			_box(Vector3(0,-0.7,0),Vector3(7.3,6.0,5.7),Color.html("89816b"))
			_box(Vector3(0,4.15,0),Vector3(7.1,3.7,5.5),Color.html("b4a387"))
			_roof(8.3,6.2,6.0,Color.html("7e4936"))
			_box(Vector3(0,3.5,2.8),Vector3(1.45,2.35,0.09),dark)
			for x: float in [-2.25,2.25]:
				_box(Vector3(x,4.45,2.81),Vector3(1.15,1.0,0.09),dark)
				for line in 3: _box(Vector3(x+(line-1)*0.3,4.45,2.87),Vector3(0.065,1.05,0.045),wood)
			for step in 4: _box(Vector3(0,0.3+step*0.55,4.5-step*0.4),Vector3(2.6,0.6+step*1.1,0.55),Color.html("938975"))
		"lean_to":
			for x: float in [-2.2,2.2]:
				for z: float in [-1.7,1.7]: _tube(Vector3(x,-3.6,z),Vector3(x,3.9-z*0.25,z),0.12,wood,6)
			_box(Vector3(0,0.2,0),Vector3(4.7,0.35,3.7),Color.html("9a8662"))
			var a:=Vector3(-2.7,4.5,-2.1); var b:=Vector3(2.7,4.5,-2.1)
			var c:=Vector3(2.7,3.4,2.1); var d:=Vector3(-2.7,3.4,2.1)
			_quad(a,d,c,b,Color.html("c5b280")); _quad(a-Vector3(0,0.16,0),b-Vector3(0,0.16,0),c-Vector3(0,0.16,0),d-Vector3(0,0.16,0),wood)
			for index in 7:
				var x:=(index-3)*0.78
				_tube(Vector3(x,4.54,-2.15),Vector3(x,3.44,2.15),0.055,wood,4)
			_box(Vector3(0,1.0,-1.1),Vector3(4.4,1.65,1.0),Color.html("897247"))
		"market_stall":
			for x: float in [-2.0,2.0]:
				for z: float in [-1.05,1.05]: _tube(Vector3(x,-3.5,z),Vector3(x,3.1,z),0.1,wood,6)
			_box(Vector3(0,1.05,0),Vector3(4.4,0.25,2.5),Color.html("ac8d59"))
			_box(Vector3(0,0.2,-0.4),Vector3(4.1,1.4,1.3),wood)
			_roof(5.0,3.0,3.15,Color.html("d3b675"))
			for index in 5: _foliage(Vector3((index-2)*0.68,1.38,0),0.32,Color.html("aa984e"))
		"path_gravel":
			_rock(0,false)
		"outcrop", "pebble", "reef":
			_rock(variant, kind == "reef")
		"beach_grass":
			for index in 11:
				var angle := index * 2.399
				var p := Vector3(cos(angle), 0, sin(angle)) * (0.1 + (index % 3) * 0.08)
				var tip := p + Vector3(cos(angle) * 0.34, 0.52 + (index % 4) * 0.13, sin(angle) * 0.34)
				var side := Vector3(-sin(angle),0,cos(angle)) * 0.075
				_triangle(p-side,p+side,tip,Color.html("8d9a55") if index % 3 else Color.html("c2bd75"))
				_triangle(p+side,p-side,tip,Color.html("a8b575"))
		"shrub":
			for index in 7:
				var angle := index * 2.399
				var p := Vector3(cos(angle)*0.35,0.05,sin(angle)*0.35)
				_tube(p,p+Vector3(0,0.65,0),0.035,wood)
				_foliage(p+Vector3(0,0.5+(index%3)*0.12,0),0.38,Color.html("63824a") if index%2 else Color.html("83935a"))
		"barrel":
			_profile([Vector2(0.36,0),Vector2(0.46,0.22),Vector2(0.49,0.6),Vector2(0.43,1.06),Vector2(0.36,1.17)],12,wood)
			for y: float in [0.18,0.57,0.99]: _ring(Vector3(0,y,0),0.46 if y<0.9 else 0.43,0.027,dark,16)
			for index in 12:
				var angle := index * TAU / 12.0
				_tube(Vector3(cos(angle)*0.455,0.23,sin(angle)*0.455),Vector3(cos(angle)*0.44,0.98,sin(angle)*0.44),0.008,Color.html("664828"),4)
			_box(Vector3(0,1.18,0),Vector3(0.62,0.025,0.12),Color.html("ad8455"))
		"crate":
			_box(Vector3(0,0.49,0),Vector3(1.12,0.98,0.95),wood)
			for y: float in [0.13,0.49,0.85]:
				_box(Vector3(0,y,0.49),Vector3(1.15,0.08,0.04),Color.html("b38a58"))
				_box(Vector3(0,y,-0.49),Vector3(1.15,0.08,0.04),Color.html("b38a58"))
			for x: float in [-0.45,0.45]:
				_box(Vector3(x,0.49,0.5),Vector3(0.075,1.01,0.055),dark)
				_box(Vector3(x,1.0,0),Vector3(0.075,0.04,0.95),dark)
			_tube(Vector3(-0.48,0.09,0.525),Vector3(0.48,0.91,0.525),0.045,Color.html("b89261"),4)
		"rope_coil":
			for index in 5: _ring(Vector3(0,0.045+index*0.014,0),0.22+index*0.071,0.024,rope,22)
			_tube(Vector3(0.5,0.05,0),Vector3(0.85,0.05,0.34),0.024,rope)
			_tube(Vector3(0.85,0.05,0.34),Vector3(1.02,0.065,0.19),0.024,rope)
		"cargo_net":
			_foliage(Vector3(0,0.35,0),0.68,Color.html("b8a779"))
			for line in 7:
				var k := (line-3)*0.19
				for cross in 6:
					var t := (cross-3)*0.19
					_tube(_net_point(k,t),_net_point(k,t+0.19),0.017,rope,4)
					_tube(_net_point(t,k),_net_point(t+0.19,k),0.017,rope,4)
			_ring(Vector3(0,0.06,0),0.76,0.03,dark,20)
		"basket":
			_profile([Vector2(0.3,0),Vector2(0.44,0.5),Vector2(0.47,0.6)],14,Color.html("af9861"))
			for y: float in [0.08,0.18,0.28,0.38,0.48,0.59]: _ring(Vector3(0,y,0),0.32+y*0.24,0.018,rope,14)
			for index in 4:
				_box(Vector3((index-1.5)*0.13,0.62,0.04*sin(index)),Vector3(0.09,0.07,0.42),Color.html("84999a"))
		"bollard":
			_profile([Vector2(0.18,0),Vector2(0.18,0.7),Vector2(0.24,0.72),Vector2(0.24,0.86)],8,dark)
			for y: float in [0.34,0.4,0.46]: _ring(Vector3(0,y,0),0.2,0.025,rope,14)
		"lantern":
			_box(Vector3(0,0.03,0),Vector3(0.35,0.06,0.35),dark)
			_box(Vector3(0,0.33,0),Vector3(0.28,0.54,0.28),Color.html("ddbf79"))
			for x: float in [-0.16,0.16]:
				for z: float in [-0.16,0.16]: _box(Vector3(x,0.34,z),Vector3(0.035,0.63,0.035),dark)
			_box(Vector3(0,0.66,0),Vector3(0.4,0.07,0.4),dark)
			_ring(Vector3(0,0.83,0),0.1,0.025,dark,10,Vector3.RIGHT)
	# HTML colors are authored in sRGB. Material albedo performs engine conversion;
	# neutral vertex values carry linear brightness only, preventing doubled hue.
	var palette:=_palette(kind)
	var reference:=palette.srgb_to_linear()
	var reference_luminance:=reference.r*0.2126+reference.g*0.7152+reference.b*0.0722
	for index in _colors.size():
		var linear:=_colors[index].srgb_to_linear()
		var luminance:=linear.r*0.2126+linear.g*0.7152+linear.b*0.0722
		var shade:=clampf(luminance/maxf(reference_luminance,0.01),0.23,1.0)
		_colors[index]=Color(shade,shade,shade,1.0)
	var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=_vertices; arrays[Mesh.ARRAY_NORMAL]=_normals; arrays[Mesh.ARRAY_COLOR]=_colors
	var mesh := ArrayMesh.new()
	if not _vertices.is_empty(): mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material_key:=palette.to_html()
	if not _materials.has(material_key):
		var material:=StandardMaterial3D.new(); material.vertex_color_use_as_albedo=true
		material.vertex_color_is_srgb=false; material.roughness=0.94
		material.albedo_color=palette; material.metallic_specular=0.22
		_materials[material_key]=material
	if mesh.get_surface_count()>0: mesh.surface_set_material(0,_materials[material_key])
	_meshes[key]=mesh
	return mesh

func _palette(kind: String) -> Color:
	match kind:
		"coastal_tree": return Color.html("547442")
		"harbor_house": return Color.html("a18764")
		"lean_to": return Color.html("a58d5e")
		"market_stall": return Color.html("bb9a61")
		"path_gravel": return Color.html("b29b73")
		"outcrop","pebble": return Color.html("807b69")
		"reef": return Color.html("777d67")
		"beach_grass": return Color.html("81945b")
		"shrub": return Color.html("536b38")
		"barrel","crate": return Color.html("885630")
		"rope_coil","cargo_net": return Color.html("d0ac67")
		"basket": return Color.html("ad8c4f")
		"bollard": return Color.html("3f3329")
		"lantern": return Color.html("d2a75d")
	return Color.html("807b69")

func _roof(width: float,depth: float,wall_height: float,color: Color) -> void:
	for side: float in [-1.0,1.0]:
		var a:=Vector3(-width*0.5,wall_height+1.6,0); var b:=Vector3(width*0.5,wall_height+1.6,0)
		var c:=Vector3(width*0.5,wall_height+0.28,side*depth*0.42); var d:=Vector3(-width*0.5,wall_height+0.28,side*depth*0.42)
		var e:=Vector3(width*0.5,wall_height+0.48,side*depth*0.59); var f:=Vector3(-width*0.5,wall_height+0.48,side*depth*0.59)
		if side>0:
			_quad(a,d,c,b,color); _quad(d,f,e,c,color.lightened(0.05))
		else:
			_quad(a,b,c,d,color); _quad(d,c,e,f,color.lightened(0.05))
		var lower:=Vector3(0,0.18,0)
		if side>0:
			_quad(a-lower,b-lower,c-lower,d-lower,color.darkened(0.2))
		else:
			_quad(a-lower,d-lower,c-lower,b-lower,color.darkened(0.2))
		for x: float in [-width*0.5,width*0.5]:
			var ridge:=Vector3(x,wall_height+1.6,0)
			var edge:=Vector3(x,wall_height+0.28,side*depth*0.42)
			var base:=Vector3(x,wall_height,0)
			if x*side>0:
				_triangle(ridge,edge,base,color.darkened(0.18))
			else:
				_triangle(ridge,base,edge,color.darkened(0.18))
	_box(Vector3(0,wall_height+1.66,0),Vector3(width+0.35,0.2,0.28),color.lightened(0.1))

func _net_point(x: float,z: float) -> Vector3:
	return Vector3(x,0.09+0.54*maxf(0,1.0-(x*x+z*z)/0.7),z)

func _triangle(a: Vector3,b: Vector3,c: Vector3,color: Color) -> void:
	var normal := (b-a).cross(c-a).normalized()
	# Godot clockwise front faces; normals use outward conventional cross product.
	for point: Vector3 in [a,c,b]:
		_vertices.append(point); _normals.append(normal); _colors.append(color)

func _quad(a: Vector3,b: Vector3,c: Vector3,d: Vector3,color: Color) -> void:
	_triangle(a,b,c,color); _triangle(a,c,d,color)

func _box(center: Vector3,size: Vector3,color: Color) -> void:
	var h:=size*0.5
	var a:=center+Vector3(-h.x,-h.y,h.z); var b:=center+Vector3(h.x,-h.y,h.z)
	var c:=center+Vector3(h.x,h.y,h.z); var d:=center+Vector3(-h.x,h.y,h.z)
	var e:=center+Vector3(-h.x,-h.y,-h.z); var f:=center+Vector3(h.x,-h.y,-h.z)
	var g:=center+Vector3(h.x,h.y,-h.z); var i:=center+Vector3(-h.x,h.y,-h.z)
	_quad(a,b,c,d,color); _quad(f,e,i,g,color); _quad(b,f,g,c,color.darkened(0.08))
	_quad(e,a,d,i,color); _quad(d,c,g,i,color.lightened(0.06)); _quad(e,f,b,a,color)

func _profile(profile: Array,sides: int,color: Color) -> void:
	for layer in profile.size()-1:
		var lo: Vector2=profile[layer]; var hi: Vector2=profile[layer+1]
		for index in sides:
			var angle:=TAU*index/sides; var next:=TAU*(index+1)/sides
			_quad(Vector3(cos(angle)*lo.x,lo.y,sin(angle)*lo.x),Vector3(cos(angle)*hi.x,hi.y,sin(angle)*hi.x),Vector3(cos(next)*hi.x,hi.y,sin(next)*hi.x),Vector3(cos(next)*lo.x,lo.y,sin(next)*lo.x),color.lightened(0.035*(index%3)))
	var top: Vector2=profile.back(); var base: Vector2=profile.front()
	for index in sides:
		var angle:=TAU*index/sides; var next:=TAU*(index+1)/sides
		_triangle(Vector3(0,top.y,0),Vector3(cos(next)*top.x,top.y,sin(next)*top.x),Vector3(cos(angle)*top.x,top.y,sin(angle)*top.x),color.lightened(0.07))
		_triangle(Vector3(0,base.y,0),Vector3(cos(angle)*base.x,base.y,sin(angle)*base.x),Vector3(cos(next)*base.x,base.y,sin(next)*base.x),color)

func _rock(variant: int,underwater: bool) -> void:
	var rng:=RandomNumberGenerator.new(); rng.seed=9173+variant*2141
	var rings: Array=[]
	for layer in 4:
		var ring: Array=[]
		for index in 9:
			var angle:=index*TAU/9.0
			var radius: float=[0.52,0.62,0.43,0.18][layer]*rng.randf_range(0.78,1.18)
			var y: float=[0.0,0.28,0.75,1.0][layer]
			ring.append(Vector3(cos(angle)*radius+layer*0.043,y+(rng.randf_range(-0.065,0.065) if layer>0 else 0.0),sin(angle)*radius-layer*0.028))
		rings.append(ring)
	var base_color:=Color.html("749d8b") if underwater else Color.html("a29b85")
	for layer in 3:
		for index in 9:
			var next: int=(index+1)%9
			var shade:=base_color.lightened(layer*0.055+rng.randf_range(-0.12,0.1))
			_quad(rings[layer][index],rings[layer+1][index],rings[layer+1][next],rings[layer][next],shade)
	for index in 9: _triangle(Vector3(0.13,1.035,-0.085),rings[3][(index+1)%9],rings[3][index],base_color.lightened(0.18))

func _foliage(center: Vector3,radius: float,color: Color) -> void:
	var sides:=7
	for index in sides:
		var angle:=index*TAU/sides; var next: float=(index+1)*TAU/sides
		var a:=center+Vector3(cos(angle)*radius,0,sin(angle)*radius)
		var b:=center+Vector3(cos(next)*radius,0,sin(next)*radius)
		_triangle(a,center+Vector3(0,radius*0.65,0),b,color.lightened(0.025*(index%3)))
		_triangle(a,b,center-Vector3(0,radius*0.48,0),color.darkened(0.12))

func _tube(a: Vector3,b: Vector3,radius: float,color: Color,sides: int=5) -> void:
	var direction:=(b-a).normalized()
	var u:=direction.cross(Vector3.UP if absf(direction.y)<0.9 else Vector3.RIGHT).normalized()
	var v:=direction.cross(u).normalized()
	for index in sides:
		var angle:=index*TAU/sides; var next:= (index+1)*TAU/sides
		var n:=(u*cos(angle)+v*sin(angle))*radius; var m:=(u*cos(next)+v*sin(next))*radius
		_quad(a+n,a+m,b+m,b+n,color)

func _ring(center: Vector3,radius: float,thickness: float,color: Color,sides: int,normal: Vector3=Vector3.UP) -> void:
	var u:=Vector3.RIGHT if normal==Vector3.UP else Vector3.UP
	var v:=normal.cross(u)
	for index in sides:
		var angle:=index*TAU/sides; var next:=(index+1)*TAU/sides
		_tube(center+(u*cos(angle)+v*sin(angle))*radius,center+(u*cos(next)+v*sin(next))*radius,thickness,color,5)

func diagnostics() -> Dictionary:
	var vertices:=0
	for mesh: ArrayMesh in _meshes.values(): vertices+=mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	return {"mesh_count":_meshes.size(),"mesh_vertices":vertices,"material_count":_materials.size()}
