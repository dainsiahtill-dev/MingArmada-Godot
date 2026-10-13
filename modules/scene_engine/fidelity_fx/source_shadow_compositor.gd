extends CompositorEffect
const Backend=preload("res://modules/scene_engine/fidelity_fx/source_shadow_rd.gd")
var _backend:RefCounted
var _mutex:=Mutex.new()
var _volumes:Array=[]
var _color:=Color(0,0,0,0.5)
var _disposed:=false
var _status:Dictionary={"frames":0,"draws":0,"error":"","initialized":false}

func _init()->void:
	effect_callback_type=EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color=true;access_resolved_depth=true

func submit(volumes:Array,color:Color)->void:
	_mutex.lock();_volumes=volumes.duplicate(true);_color=color;_mutex.unlock()

func status()->Dictionary:
	_mutex.lock();var result:=_status.duplicate(true);_mutex.unlock();return result

func _render_callback(callback_type:int,render_data:RenderData)->void:
	if callback_type!=effect_callback_type:return
	_mutex.lock()
	if _disposed:_mutex.unlock();return
	var volumes:=_volumes;var color:=_color
	_mutex.unlock()
	if volumes.is_empty():return
	if _backend==null:
		_backend=Backend.new()
		if not _backend.initialize(RenderingServer.get_rendering_device()):
			_mutex.lock();_status.error=_backend.last_error;_mutex.unlock();return
	var buffers:=render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	var scene:=render_data.get_render_scene_data()
	if buffers==null or scene==null:return
	# RenderSceneData is this pass's camera, never a cached main-camera matrix.
	var view:Transform3D=scene.get_cam_transform().affine_inverse()
	var success:=true
	for eye in buffers.get_view_count():
		var projection:Projection=scene.get_view_projection(eye)
		var eye_view:Transform3D=Transform3D(Basis.IDENTITY,-scene.get_view_eye_offset(eye))*view
		success=_backend.render(buffers.get_color_layer(eye),buffers.get_depth_layer(eye),buffers.get_internal_size(),projection*Projection(eye_view),volumes,color) and success
	_mutex.lock()
	_status.initialized=true;_status.frames+=int(success);_status.draws=_backend.draw_count;_status.error=_backend.last_error
	_mutex.unlock()

func dispose()->void:
	_mutex.lock();_disposed=true;_volumes=[];_mutex.unlock()
	# All RD operations and destruction remain on render thread.
	RenderingServer.call_on_render_thread(_dispose_render_thread)

func _dispose_render_thread()->void:
	if _backend!=null:_backend.dispose();_backend=null
