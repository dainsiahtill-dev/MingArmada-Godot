extends SceneTree
## Root viewport input drives the actual native model viewer and damping.
var book: Control
var failures := 0
var captures := 0
var directory := "res://docs/migration/evidence/shipbook-orbit"
func _initialize() -> void: run.call_deferred()
func frames(count: int=6) -> void:
	for frame in count: await process_frame
func capture(label: String) -> void:
	await frames(); await RenderingServer.frame_post_draw
	var pixels := root.get_texture().get_image()
	if pixels.save_png(directory+"/"+label+".png") != OK: failures += 1
	var packet := {"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"viewport":[pixels.get_width(),pixels.get_height()],"state":book.snapshot(),"cameraPosition":str(book.camera.position),"target":str(book._target),"scope":"Native model-view GPU frame after actual root-routed pointer input; no performance claim"}
	var file := FileAccess.open(directory+"/"+label+".json",FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(packet,"\t")); file.close()
	else: failures += 1
	captures += 1
func press(button: int, held: int, value: bool, point: Vector2) -> void:
	var event := InputEventMouseButton.new(); event.button_index=button; event.button_mask=held; event.pressed=value; event.position=point; event.global_position=point
	root.push_input(event,true)
func drag(point: Vector2, delta: Vector2, held: int) -> void:
	var event := InputEventMouseMotion.new(); event.position=point+delta; event.global_position=event.position; event.relative=delta; event.button_mask=held
	root.push_input(event,true)
func run() -> void:
	root.size=Vector2i(1600,900); root.content_scale_size=root.size
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	book=load("res://game/scenes/ship_book/ship_book.tscn").instantiate(); book.startup_options={"dev":true}; root.add_child(book)
	await frames(10)
	if not book.startup_receipt.ok: failures += 1; quit(1); return
	await capture("quarter-before")
	var point: Vector2=book._view.get_global_rect().get_center()
	var before: Vector3=book.camera.position
	press(MOUSE_BUTTON_LEFT,MOUSE_BUTTON_MASK_LEFT,true,point); drag(point,Vector2(100,35),MOUSE_BUTTON_MASK_LEFT)
	press(MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MASK_LEFT|MOUSE_BUTTON_MASK_RIGHT,true,point+Vector2(100,35))
	press(MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MASK_LEFT,false,point+Vector2(100,35))
	drag(point+Vector2(100,35),Vector2(25,0),MOUSE_BUTTON_MASK_LEFT)
	press(MOUSE_BUTTON_LEFT,0,false,point+Vector2(125,35)); await frames(25)
	if book.camera.position.is_equal_approx(before): failures += 1; printerr("FAIL real orbit input")
	await capture("orbit-after-chord")
	point=book._view.get_global_rect().get_center(); var old_target: Vector3=book._target
	press(MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MASK_RIGHT,true,point); drag(point,Vector2(90,-30),MOUSE_BUTTON_MASK_RIGHT); press(MOUSE_BUTTON_RIGHT,0,false,point+Vector2(90,-30)); await frames(25)
	if book._target.is_equal_approx(old_target): failures += 1; printerr("FAIL real pan input")
	await capture("pan-after")
	press(MOUSE_BUTTON_WHEEL_UP,0,true,point); press(MOUSE_BUTTON_WHEEL_UP,0,false,point); await capture("zoom-after")
	book.queue_free(); await frames()
	print("NATIVE_SHIP_BOOK_ORBIT_CAPTURE_COMPLETE captures=",captures," failures=",failures)
	quit(1 if failures else 0)
