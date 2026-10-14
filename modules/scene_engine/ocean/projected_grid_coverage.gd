extends RefCounted
## Conservative base-plane footprint of a vertically displaced perspective grid.
## No time, wave phase or terrain authority is changed by this presentation bound.

static func screen_bounds(camera: Camera3D, amplitude: float, padding: float) -> Rect2:
	var size := camera.get_viewport().get_visible_rect().size
	var bounds := Rect2(-Vector2.ONE*padding,Vector2.ONE*(1.0+2.0*padding))
	var eye := camera.get_camera_transform().origin
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL or eye.y<=0.0: return bounds
	# Views inside the wave volume have no finite all-phase plane projection.
	# Keep their geometry finite; above-volume views use the full physical bound.
	var limit := minf(amplitude,eye.y*0.95)
	for corner: Vector2 in [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]:
		var direction := camera.project_ray_normal(corner*size)
		if direction.y>=-0.0001: continue
		for height: float in [-limit,limit]:
			var point := eye+direction*((height-eye.y)/direction.y)
			point.y=0.0
			if camera.is_position_behind(point): continue
			var screen := camera.unproject_position(point)/size
			if screen.is_finite(): bounds=bounds.expand(screen)
	return bounds.grow(0.005)

static func project(ocean: MeshInstance3D,camera: Camera3D,amplitude: float) -> void:
	var bounds := screen_bounds(camera,amplitude,ocean._projection_padding)
	var basis := camera.get_camera_transform().basis
	var eye := camera.get_camera_transform().origin
	var inverse_world := ocean.global_transform.affine_inverse()
	# Reuse native lens rays already cached by the production owner. Perspective
	# rays divided by -z form an affine screen basis, regardless of FOV/offset.
	var rays: PackedVector3Array=ocean._local_rays
	var down_left := rays[0]
	var down_right := rays[ocean._segments]
	var top_left := rays[ocean._segments*(ocean._segments+1)]
	down_left/=maxf(-down_left.z,0.0001);down_right/=maxf(-down_right.z,0.0001);top_left/=maxf(-top_left.z,0.0001)
	var padding: float=ocean._projection_padding
	var step_x := (down_right-down_left)/(1.0+2.0*padding)
	var step_y := (down_left-top_left)/(1.0+2.0*padding)
	var origin := down_left+step_x*padding-step_y*(1.0+padding)
	var vertices: PackedVector3Array=ocean._vertices
	var segments: int=ocean._segments
	var columns := PackedVector3Array();columns.resize(segments+1)
	# Separability avoids a camera/basis transform and four lerps per vertex.
	# Plane intersection divides by ray.y, so ray normalization cancels exactly.
	for column in segments+1:
		var u := float(column)/segments
		var x := lerpf(bounds.position.x,0.5,u*2.0) if u<=0.5 else lerpf(0.5,bounds.end.x,u*2.0-1.0)
		columns[column]=basis*(origin+step_x*x)
	var world_step_y := basis*step_y
	var has_limit: bool=ocean._has_maximum_distance
	var maximum: float=ocean._maximum_distance
	var maximum_squared := maximum*maximum
	var fallback: float=ocean._fallback_distance
	var eye_xz := Vector2(eye.x,eye.z)
	for row in segments+1:
		var v := float(row)/segments
		var y := lerpf(bounds.end.y,0.5,v*2.0) if v<=0.5 else lerpf(0.5,bounds.position.y,v*2.0-1.0)
		var row_ray := world_step_y*y
		for column in segments+1:
			var direction := columns[column]+row_ray
			var horizontal := Vector2(direction.x,direction.z)
			var displacement: Vector2
			# Match the normalized-ray grazing threshold without sqrt per vertex.
			if direction.y<0.0 and direction.y*direction.y>0.00000001*direction.length_squared():
				displacement=horizontal*(-eye.y/direction.y)
				if has_limit and displacement.length_squared()>maximum_squared:displacement=displacement.normalized()*maximum
			else:displacement=horizontal.normalized()*fallback
			var planar := eye_xz+displacement
			vertices[row*(segments+1)+column]=inverse_world*Vector3(planar.x,0.0,planar.y)
	ocean._vertices=vertices
	ocean._upload_grid()
