extends SceneTree
## Actual native GPU screenshots and canonical scene input, no poster mockups.
const LegacyScene = preload("res://game/scenes/legacy/legacy_scene.gd")
const MingqiScene = preload("res://game/scenes/mingqi/mingqi_scene.gd")
const TrialScene = preload("res://game/scenes/sailing_trial/sailing_trial.gd")
const Settings = preload("res://game/persistence/user_settings.gd")
var failed := false
var captures := 0
var directory := "res://docs/migration/evidence/charts"
var settings_path := ""
func _initialize() -> void: _run.call_deferred()
func _frames(count: int = 6) -> void:
	for frame in count: await process_frame
func _capture(scene: Node3D, label: String) -> void:
	await _frames()
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var pixels := root.get_texture().get_image()
	if pixels.save_png(directory+"/"+label+".png") != OK: failed=true; push_error("Native chart PNG save failed")
	var overlay: CanvasLayer = scene.get("minimap") if scene.get("minimap") else scene.get("mini_chart")
	var map: Control = overlay.chart
	var camera: Camera3D = scene.get("sea").camera if scene.get("sea") else scene.get("camera")
	var metadata := {"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"viewport":[pixels.get_width(),pixels.get_height()],"packet":scene.runtime.snapshot(),"minimap":{"visible":map.visible,"rect":[map.position.x,map.position.y,map.size.x,map.size.y],"viewBounds":[map.view_bounds().position.x,map.view_bounds().position.y,map.view_bounds().size.x,map.view_bounds().size.y],"marks":map.ship_marks(),"overlays":map._overlays,"seaMaterial":map.BACKGROUND,"landMaterial":map.LAND_PAPER},"cameraPosition":[camera.position.x,camera.position.y,camera.position.z],"scope":"native GPU render; accepted runtime progression; not a performance benchmark"}
	var file := FileAccess.open(directory+"/"+label+".json",FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(metadata,"\t")); file.close()
	else: failed=true; push_error("Native chart metadata save failed")
	captures += 1
func _click(control: Control) -> void:
	var event := InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=true; event.position=control.global_position+control.map_rect().get_center()
	Input.parse_input_event(event); await process_frame
	event=event.duplicate(); event.pressed=false; Input.parse_input_event(event); await process_frame
func _run() -> void:
	if "--chart-v2" in OS.get_cmdline_user_args(): directory += "/v2"
	settings_path = "user://tests/chart-capture-%d-settings.json" % OS.get_process_id()
	root.size=Vector2i(1600,900); root.content_scale_size=root.size
	DisplayServer.window_set_title("海上明旗 · 古航图与海岛原生画面验收")
	var legacy := LegacyScene.new()
	legacy.settings_storage=Settings.new(settings_path)
	root.add_child(legacy); legacy.set_physics_process(false); await _frames()
	await _click(legacy.minimap.chart)
	if not legacy.interface.is_panel_open() or legacy.interface._panel!="chart": failed=true; push_error("Actual legacy minimap click failed")
	await _capture(legacy,"legacy-expanded")
	legacy.interface.close_panel(); legacy._command({"type":"depart"})
	legacy.runtime.set_held("KeyW",true)
	for tick in 180: legacy.runtime.advance(1.0/60.0)
	legacy._present(3.0)
	await _capture(legacy,"legacy-sailing-minimap")
	for tick in 600: legacy.runtime.advance(1.0/60.0)
	legacy.runtime.set_held("KeyW",false); legacy._present(10.0)
	await _capture(legacy,"legacy-sailing-minimap-moved")
	legacy.interface.visible=false; legacy._present(0.0)
	legacy.sea.camera.position=Vector3(-480,270,185); legacy.sea.camera.look_at(Vector3(-480,0,-60)); legacy.sea.world.get_ocean().update_projection()
	await _capture(legacy,"island-details-wide")
	legacy.sea.camera.position=Vector3(-280,80,70); legacy.sea.camera.look_at(Vector3(-320,0,-40)); legacy.sea.world.get_ocean().update_projection()
	await _capture(legacy,"harbor-details-close")
	legacy.queue_free(); await _frames(2); await create_timer(0.08).timeout
	var mingqi := MingqiScene.new()
	mingqi.settings_storage=Settings.new(settings_path)
	root.add_child(mingqi); mingqi.set_physics_process(false); await _frames()
	mingqi.interface.open_panel("convoy"); mingqi._present(0.0)
	await _capture(mingqi,"mingqi-expanded")
	mingqi.interface.close_panel(); mingqi._present(0.0)
	await _capture(mingqi,"mingqi-sailing-minimap")
	await _click(mingqi.minimap.chart)
	if not mingqi.interface.is_panel_open() or mingqi.interface._panel!="convoy": failed=true; push_error("Actual Mingqi minimap click failed")
	if "--chart-v2" in OS.get_cmdline_user_args():
		var packet: Dictionary = mingqi.runtime.snapshot()
		mingqi._command({"type":"accept-convoy","commandId":"chart-v2-accept","expectedRevision":packet.campaign.revision})
		var fast: String = packet.campaign.campaignId+"-fast"
		mingqi._command({"type":"select-ship","shipId":fast})
		mingqi._present(0.0)
		var expanded: Control = mingqi.interface.find_child("fleet_chart",true,false)
		if expanded.selected_id != fast: failed=true; push_error("Actual escort chart selection failed")
		await _capture(mingqi,"mingqi-selected-escort-expanded")
		root.size=Vector2i(800,900); root.content_scale_size=root.size; await _frames()
		if mingqi.minimap.chart.visible: failed=true; push_error("Narrow map overlaps career HUD")
		await _capture(mingqi,"mingqi-narrow-expanded")
		root.size=Vector2i(1600,900); root.content_scale_size=root.size; await _frames()
	mingqi.queue_free(); await _frames(2); await create_timer(0.08).timeout
	var trial := TrialScene.new()
	root.add_child(trial); trial.set_physics_process(false); await _frames()
	await _capture(trial,"default-trial-minimap")
	await _click(trial.mini_chart.chart)
	if not trial.chart_open or not trial.runtime.snapshot().paused: failed=true; push_error("Actual trial minimap click failed")
	await _capture(trial,"default-trial-expanded")
	trial.queue_free(); await _frames(2)
	print("NATIVE_NAUTICAL_CHART_CAPTURE_COMPLETE captures=",captures," failures=",int(failed))
	quit(1 if failed else 0)
