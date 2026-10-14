extends RefCounted
## Independent double precision reference for the linear numerical tests only.
var resolution: int
var h := PackedFloat64Array()
var v := PackedFloat64Array()
var foam := PackedFloat64Array()
var drift_x := PackedFloat64Array()
var drift_z := PackedFloat64Array()
func _init(size: int = 9) -> void:
	resolution = size; h.resize(size*size); v.resize(size*size); foam.resize(size*size)
	drift_x.resize(size*size);drift_z.resize(size*size)
func at(data: PackedFloat64Array, x: int, y: int) -> float:
	return data[y*resolution+x] if x>=0 and y>=0 and x<resolution and y<resolution else 0.0
func sample(data: PackedFloat64Array, p: Vector2) -> float:
	var x := floori(p.x); var y := floori(p.y)
	return lerpf(lerpf(at(data,x,y),at(data,x+1,y),p.x-x),lerpf(at(data,x,y+1),at(data,x+1,y+1),p.x-x),p.y-y)
func step(dt: float, dx: float, speed: float, damping: float, decay: float, diffusion: float, shift := Vector2.ZERO, flow := Vector2.ZERO) -> void:
	var next_h := h.duplicate(); var next_v := v.duplicate(); var next_foam := foam.duplicate()
	var next_dx:=drift_x.duplicate();var next_dz:=drift_z.duplicate()
	for y in resolution:
		for x in resolution:
			var index := y*resolution+x
			var p := Vector2(x,y)+shift-flow*dt/dx
			var value := sample(h,p)
			var lap := sample(h,p+Vector2.LEFT)+sample(h,p+Vector2.RIGHT)+sample(h,p+Vector2.UP)+sample(h,p+Vector2.DOWN)-4.0*value
			var local:=Vector2(sample(drift_x,Vector2(x,y)+shift),sample(drift_z,Vector2(x,y)+shift))
			var fp:=p-local*dt/dx
			var fv := sample(foam,fp)
			var fl := sample(foam,fp+Vector2.LEFT)+sample(foam,fp+Vector2.RIGHT)+sample(foam,fp+Vector2.UP)+sample(foam,fp+Vector2.DOWN)-4.0*fv
			next_v[index] = (sample(v,p)+dt*speed*speed*lap/(dx*dx))*exp(-damping*dt)
			next_h[index] = value+dt*next_v[index]
			next_foam[index] = clampf((fv+diffusion*dt*fl/(dx*dx))*exp(-decay*dt),0.0,1.0)
			var here:=Vector2(x,y)+shift
			var divergence:float=(sample(drift_x,here+Vector2.RIGHT)-sample(drift_x,here+Vector2.LEFT)+sample(drift_z,here+Vector2.DOWN)-sample(drift_z,here+Vector2.UP))/(2.0*dx)
			next_foam[index]*=exp(-maxf(0.0,divergence)*dt)
			next_dx[index]=sample(drift_x,fp)*exp(-0.18*dt)
			next_dz[index]=sample(drift_z,fp)*exp(-0.18*dt)
	h=next_h; v=next_v; foam=next_foam;drift_x=next_dx;drift_z=next_dz
