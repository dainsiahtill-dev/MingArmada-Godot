extends SceneTree
## Independent cartography GPU arena. Every run needs a fresh explicit output.
const Demo=preload("res://game/research/demos/antique_cartography.gd")
const STEP:=1.0/32.0
var _directory:=""
var _demo:Node3D
var _failures:=0
var _assertions:=0
var _frames:Array=[]
var _started:=""
var _initial_sources:Dictionary={}
func _sources()->Dictionary:
	var sources:Dictionary={}
	for path in ["res://game/ui/charts/world_atlas.gd","res://game/research/demos/antique_cartography.gd","res://game/ui/shared/parchment_theme.gd","res://assets/data/cartography/east_asia_land.json","res://assets/data/cartography/atlas_places.json","res://assets/data/cartography/provenance.json","res://assets/ui/ming_maritime/chart-paper.png","res://assets/ui/ming_maritime/secondary-button.png","res://assets/ui/ming_maritime/atlas-vignette.png","res://assets/art/maps/ming-nautical-land-paper-v2.png","res://tools/capture-world-atlas.gd"]:
		sources[path]=FileAccess.get_sha256(path)
	return sources
func _initialize()->void:_run.call_deferred()
func _check(value:bool,detail:String)->void:
	_assertions+=1
	if not value:_failures+=1;printerr("FAIL: ",detail)
func _settle(count:int=3)->void:
	for index in count:await process_frame
	await RenderingServer.frame_post_draw
func _serial(value:Variant)->Variant:
	if value is Vector2:return [value.x,value.y]
	if value is Vector2i:return [value.x,value.y]
	if value is Rect2:return {"position":[value.position.x,value.position.y],"size":[value.size.x,value.size.y]}
	if value is Dictionary:
		var output:Dictionary={}
		for key in value:output[key]=_serial(value[key])
		return output
	if value is Array:
		var output:Array=[]
		for item in value:output.append(_serial(item))
		return output
	return value
func _capture(label:String,kind:String="gpu-capture")->void:
	await _settle(2)
	var pixels:=root.get_texture().get_image()
	var path:=_directory+"/"+label+".png"
	_check(pixels.save_png(path)==OK,"raw GPU PNG writes: "+label)
	var record:Dictionary={"label":label,"recordType":kind,"path":path,"sha256":FileAccess.get_sha256(path),"viewport":[pixels.get_width(),pixels.get_height()],"state":_serial(_demo.inspection_snapshot())}
	_frames.append(record)
	var file:=FileAccess.open(_directory+"/"+label+".json",FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(record,"\t"));file.close()
	else:_check(false,"snapshot writes: "+label)
func _click(point:Vector2)->void:
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;event.position=point
	Input.parse_input_event(event);await process_frame
	event=event.duplicate();event.pressed=false;Input.parse_input_event(event);await process_frame
func _run()->void:
	_started=Time.get_datetime_string_from_system(true)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):_directory=argument.trim_prefix("--output=")
	if not _directory.begins_with("res://docs/design/2026-10-26-ming-maritime/atlas/") or DirAccess.dir_exists_absolute(_directory):
		printerr("WORLD_ATLAS_GPU_COMPLETE captures=0 assertions=0 failures=1 reason=fresh-explicit-output-required");quit(1);return
	DirAccess.make_dir_recursive_absolute(_directory)
	_initial_sources=_sources()
	_check(DisplayServer.get_name()!="headless","real GPU backend is active")
	root.size=Vector2i(1600,1000);root.content_scale_size=root.size
	_demo=Demo.new();_demo.configure({"paused":true,"engraving":false,"camera_mode":"overview"});root.add_child(_demo)
	await _settle(6)
	_check(_demo.inspection_snapshot().ready,"independent atlas is ready")
	var baseline:Dictionary=_demo.inspection_snapshot()
	await _capture("01-geographic-baseline")
	_demo.set_parameter("engraving",true);await _settle()
	var candidate:Dictionary=_demo.inspection_snapshot()
	_check(baseline.atlas.view_bounds==candidate.atlas.view_bounds and baseline.atlas.selected_port==candidate.atlas.selected_port and baseline.atlas.data_sha256==candidate.atlas.data_sha256,"baseline candidate differ only by declared engraving factor")
	await _capture("02-engraved-world")
	await _click(_demo.atlas.project(Vector2(129.555,33.371389)))
	_check(_demo.atlas.selected_port().id=="hirado","native GPU input selects geographic Hirado")
	_demo.atlas.focus_selected();await _capture("03-hirado-port-detail")
	_demo.atlas.select_port("java");_demo.atlas.focus_selected();await _capture("04-java-southern-islands")
	_demo.atlas.reset_view();_demo.atlas.select_port("manila")
	root.size=Vector2i(640,960);root.content_scale_size=root.size;await _settle(5)
	_check(_demo.atlas.details_rect().position.y>=_demo.atlas.map_rect().end.y,"narrow native harbour panel is below map")
	await _capture("05-narrow-world-harbour")
	root.size=Vector2i(320,480);root.content_scale_size=root.size;await _settle(5)
	var selector:Control=_demo.atlas.find_child("HarbourSelector",true,false)
	for name in ["ZoomIn","ZoomOut","ResetView","ReturnFromAtlas"]:
		var tool:Control=_demo.atlas.find_child(name,true,false)
		_check(not tool.get_rect().intersects(selector.get_rect()) and tool.get_rect().end.y<_demo.atlas.map_rect().position.y,"320px native toolbar is separate from selector/map: "+name)
	await _capture("06-smallest-320x480")
	root.size=Vector2i(1600,1000);root.content_scale_size=root.size;await _settle(5)
	_check(_demo.atlas.details_rect().size.x<=310.1,"native harbour column shrinks back after narrow screen")
	_demo.atlas.select_port("xiamen");_demo.atlas.focus_selected();_demo.set_paused(false)
	for index in 32:
		_demo.advance(STEP);_demo.atlas.pan_pixels(Vector2(-1.5,0.35))
		await _capture("sequence-%02d"%index,"gpu-continuous-sequence")
	_check(_demo.inspection_snapshot().tick==32 and _demo.inspection_snapshot().time==1.0,"32 fixed accepted steps are preserved across GPU captures")
	var return_count:Array=[0]
	_demo.atlas.return_requested.connect(func():return_count[0]+=1)
	var button:Control=_demo.atlas.find_child("ReturnFromAtlas",true,false)
	await _click(button.global_position+button.size/2)
	_check(return_count[0]==1,"native GPU return button emits exactly one return")
	var sources:Dictionary=_sources()
	_check(sources==_initial_sources,"frozen source and art hashes remain unchanged throughout capture")
	var manifest:Dictionary={"schemaVersion":1,"topic":"antique-cartography","recordType":"gpu-capture","scope":"independent-demo","startedAtUtc":_started,"finishedAtUtc":Time.get_datetime_string_from_system(true),"environment":{"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"renderingMethod":RenderingServer.get_current_rendering_method(),"display":DisplayServer.get_name()},"controls":{"seed":0,"stepSeconds":STEP,"initialPort":"xiamen","initialView":"overview","camera":"2D geographic atlas"},"sources":sources,"assertions":_assertions,"failures":_failures,"captures":_frames.size(),"frames":_frames,"limitations":["Independent atlas GPU evidence, not main-menu integration.","Modern generalized physical coast, not seventeenth-century shoreline or berth reconstruction.","No game FPS benchmark or transoceanic navigation acceptance."]}
	var file:=FileAccess.open(_directory+"/GPU_VERIFY.json",FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(manifest,"\t"));file.close()
	else:_check(false,"manifest write")
	_demo.dispose();_demo.free()
	print("WORLD_ATLAS_GPU_COMPLETE captures=",_frames.size()," assertions=",_assertions," failures=",_failures)
	quit(1 if _failures else 0)
