extends RefCounted
## Bounded forward-speed bow and side crests. Rebuilt only on authority time.
const Volume = preload("res://game/presentation/water/splash_volume.gd")
const ROWS := 14
const CROSS := [-1.0,-0.55,0.0,0.55,1.0]

static func build(pose: Dictionary, kind: String, now: float, water: Callable, filter: Callable) -> ArrayMesh:
	var vertices := PackedVector3Array(); var uvs := PackedVector2Array()
	var colors := PackedColorArray(); var indices := PackedInt32Array(); var wet: Array[bool] = []
	var forward: Vector2 = pose.forward; var side := Vector2(-forward.y,forward.x)
	# Attachment pose.position is ship center; historical stern samples are
	# converted by the caller before they cross this module boundary.
	var center: Vector2 = pose.position
	var width := float(pose.width); var length := float(pose.length)
	var strength := smoothstep(0.35,4.5,float(pose.speed))
	var surge := clampf(float(pose.get("acceleration",0.0))/3.0,0.0,1.0)
	var turn := clampf(float(pose.get("turn_rate",0.0))/0.65,-1.0,1.0)
	var bow := kind == "bow"
	var sign_side := -1.0 if kind == "port" else 1.0
	var intensity := strength*(0.36+surge*0.18) if bow else strength*(0.24+surge*0.08)*(1.0+turn*sign_side*0.55)
	for row in ROWS+1:
		var t := float(row)/ROWS
		var along: float; var lateral: float; var thickness: float
		if bow:
			# Continuous crescent across bow, feathered tips and foam ribbon edges.
			lateral = (t*2.0-1.0)*width*0.84
			along = length*0.51-pow(t*2.0-1.0,2.0)*width*0.73
			thickness = width*(0.035+0.08*sin(t*PI))
		else:
			along = lerpf(length*0.40,-length*0.48,t)
			lateral = sign_side*width*(0.46+0.14*sin(t*PI)+0.05*t)
			thickness = width*(0.055+0.07*sin(t*PI))
		var fade := smoothstep(0.0,0.16,t)*(1.0-smoothstep(0.76,1.0,t))
		for cross: float in CROSS:
			var p := center+forward*(along+(cross*thickness if bow else 0.0))+side*(lateral+(0.0 if bow else cross*thickness))
			var mask := pow(maxf(0.0,1.0-cross*cross),2.0)
			var crest := strength*0.20*sin(t*PI)*mask
			vertices.append(Vector3(p.x,Volume.height(water,p,now)+0.11+crest,p.y))
			uvs.append(Vector2((cross+1.0)*0.5,t*2.0)); colors.append(Color(1,1,1,intensity*fade*mask))
			wet.append(Volume.sea(filter,p))
	var count := CROSS.size()
	for row in ROWS:
		for column in count-1:
			var a := row*count+column; var b := a+count
			if wet[a] and wet[b] and wet[a+1]: indices.append_array(PackedInt32Array([a,b,a+1]))
			if wet[a+1] and wet[b] and wet[b+1]: indices.append_array(PackedInt32Array([a+1,b,b+1]))
	return Volume.mesh_from(vertices,uvs,colors,indices)
