extends SceneTree
const Scene=preload("res://game/scenes/natural_island/natural_island_prototype.gd")
func _initialize() -> void: _open.call_deferred()
func _open() -> void:
	root.size=Vector2i(1600,900); root.title="海上明旗 · 自然海岛实景"
	var scene:=Scene.new(); root.add_child(scene)
	await process_frame
	if not scene.ready_receipt.get("ok",false): printerr("NATURAL_ISLAND_OPEN failed=true"); quit(1); return
	print("NATURAL_ISLAND_OPEN ready=true gpu=",RenderingServer.get_video_adapter_name())
