extends RefCounted
## Independent CPU oracle for the triangular texture-blend contract. Image
## pixels remain original; this fixture never generates an art asset.

static func cell_hash(vertex: Vector2i, salt: int) -> int:
	var value:=((vertex.x*1597334677) ^ (vertex.y*3812015801) ^ salt)&0xffffffff
	value=((value^(value>>16))*2246822519)&0xffffffff
	value=((value^(value>>13))*3266489917)&0xffffffff
	return (value^(value>>16))&0xffffffff

static func triangle(point: Vector2) -> Dictionary:
	var cell:=Vector2i(floori(point.x),floori(point.y))
	var local:=point-Vector2(cell)
	var vertices: Array[Vector2i]
	var weights: Vector3
	if local.x+local.y<=1.0:
		vertices=[cell,cell+Vector2i(0,1),cell+Vector2i(1,0)]
		weights=Vector3(1.0-local.x-local.y,local.y,local.x)
	else:
		vertices=[cell+Vector2i(1,1),cell+Vector2i(1,0),cell+Vector2i(0,1)]
		weights=Vector3(local.x+local.y-1.0,1.0-local.y,1.0-local.x)
	for i in 3: weights[i]=weights[i]*weights[i]*(3.0-2.0*weights[i])
	weights/=weights.x+weights.y+weights.z
	return {"vertices":vertices,"weights":weights}

static func texture_alpha(image: Image, uv: Vector2) -> float:
	var pixel:=uv*Vector2(image.get_width(),image.get_height())-Vector2(.5,.5)
	var x:=floori(pixel.x); var y:=floori(pixel.y); var f:=pixel-Vector2(x,y)
	var a:=image.get_pixel(posmod(x,image.get_width()),posmod(y,image.get_height())).a
	var b:=image.get_pixel(posmod(x+1,image.get_width()),posmod(y,image.get_height())).a
	var c:=image.get_pixel(posmod(x,image.get_width()),posmod(y+1,image.get_height())).a
	var d:=image.get_pixel(posmod(x+1,image.get_width()),posmod(y+1,image.get_height())).a
	return lerpf(lerpf(a,b,f.x),lerpf(c,d,f.x),f.y)

static func stochastic_alpha(image: Image, uv: Vector2, salt: int, angle_range: float) -> float:
	var plan:=triangle(uv); var result:=0.0
	for i in 3:
		var vertex: Vector2i=plan.vertices[i]
		var bits:=cell_hash(vertex,salt)
		var angle: float=(float(bits&65535)/65535.0*2.0-1.0)*angle_range
		var offset:=Vector2(float((bits>>8)&65535)/65535.0,float((bits>>16)&65535)/65535.0)
		var p: Vector2=(uv-Vector2(vertex)).rotated(angle)+offset
		result+=texture_alpha(image,p)*float(plan.weights[i])
	return result
