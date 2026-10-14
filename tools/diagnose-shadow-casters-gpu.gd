extends "res://tools/diagnose-voyage-ship-line.gd"
## Frozen actual scene, diagnostic subsets only. Never alters production caster policy.
const PreparedFrame=preload("res://modules/scene_engine/fidelity_fx/prepared_shadow_frame.gd")
const ROI=Rect2i(250,0,220,390)
const NEAR_ROI=Rect2i(440,390,80,80)
const MAX_CASES=96
var _effect:CompositorEffect
var _source_renderer:RefCounted
var _scene:Control
var _baseline:Image
var _baseline_bytes:PackedByteArray
var _color:=Color(0,0,0,.5)
var _cases:Array=[]
var _contributors:Array=[]
var _interactions:Array=[]
var _errors:Array=[]
var _all:Array=[]

func _initialize()->void:
	output="res://docs/research/evidence/shadow-edges/caster-isolation"
	super._initialize()

func _score(image:Image,region:Rect2i)->Dictionary:
	var picture:Image=image.duplicate();picture.convert(Image.FORMAT_RGBA8)
	var bytes:=picture.get_data();var count:=0
	var minimum:=Vector2i(picture.get_width(),picture.get_height());var maximum:=Vector2i(-1,-1)
	var clipped:=region.intersection(Rect2i(Vector2i.ZERO,picture.get_size()))
	for y in range(clipped.position.y,clipped.end.y):
		for x in range(clipped.position.x,clipped.end.x):
			var offset: int=(y*picture.get_width()+x)*4
			if int(_baseline_bytes[offset])-int(bytes[offset])>10 and int(_baseline_bytes[offset+1])-int(bytes[offset+1])>10 and int(_baseline_bytes[offset+2])-int(bytes[offset+2])>10:
				count+=1;minimum.x=mini(minimum.x,x);minimum.y=mini(minimum.y,y);maximum.x=maxi(maximum.x,x);maximum.y=maxi(maximum.y,y)
	return {"darkPixels":count,"bounds":[minimum.x,minimum.y,maximum.x,maximum.y] if count>0 else [],"roi":[region.position.x,region.position.y,region.size.x,region.size.y],"criterion":"each RGB channel is >10/255 darker than same-time stencil-off"}

func _submit(volumes:Array)->void:
	var frame:=PreparedFrame.new()
	if not frame.configure(volumes):_errors.append("could not freeze diagnostic subset");return
	_effect.submit_prepared(frame,_color)

func _probe(volumes:Array,label:String)->Dictionary:
	_submit(volumes);_effect.enabled=true
	await frames(3);await RenderingServer.frame_post_draw
	var image:Image=_scene.view.get_texture().get_image()
	var name:="%03d-%s.png"%[_cases.size(),label]
	image.save_png(output+"/"+name)
	var identifiers:Array=[];var expected_meshes:=0
	for volume:Dictionary in volumes:
		identifiers.append(volume.id);expected_meshes+=int(not volume.geometry.indices.is_empty())
	var state:Dictionary=_source_renderer.diagnostics().gpu
	var row:={"index":_cases.size(),"label":label,"ids":identifiers,"expectedMeshes":expected_meshes,"line":_score(image,ROI),"nearShip":_score(image,NEAR_ROI),"gpu":state,"image":name,"sha256":FileAccess.get_sha256(output+"/"+name),"acceptedSceneTime":_scene.seconds}
	if not state.get("initialized",false) or not state.get("error","").is_empty() or int(state.get("cachedMeshes",-1))!=expected_meshes:_errors.append("GPU subset was not confirmed: "+label+" "+JSON.stringify(state))
	_cases.append(row)
	print("SHADOW_CASTER_CASE ",label," casters=",volumes.size()," linePixels=",row.line.darkPixels," meshes=",state.get("cachedMeshes",-1))
	return row

func _split(volumes:Array,label:String,parent:Dictionary)->void:
	if int(parent.line.darkPixels)==0:return
	if volumes.size()==1:
		_contributors.append(parent);return
	if _cases.size()+2>MAX_CASES:
		_errors.append("diagnostic case limit reached");return
	var half:int=volumes.size()/2
	var left:Array=volumes.slice(0,half);var right:Array=volumes.slice(half)
	var a:Dictionary=await _probe(left,label+"L")
	var b:Dictionary=await _probe(right,label+"R")
	if int(a.line.darkPixels)==0 and int(b.line.darkPixels)==0:
		_interactions.append({"parent":parent.index,"left":a.index,"right":b.index,"ids":parent.ids,"reason":"combined subset produces line but neither child alone does"});return
	await _split(left,label+"L",a)
	await _split(right,label+"R",b)

func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size=Vector2i(1600,1000);root.content_scale_size=root.size
	var main:Node=Main.instantiate();root.add_child(main);await frames(4)
	main.menu.find_child("fidelity-island",true,false).pressed.emit()
	for wait in 150:
		await process_frame
		if is_instance_valid(main.current_scene):break
	_scene=main.current_scene
	if not is_instance_valid(_scene) or not _scene.startup_receipt.ok:printerr("FAIL actual shared world unavailable");quit(1);return
	_scene.set_process(false);_scene.paused=true;_scene.seconds=24.0;_scene._render();await frames(4)
	_source_renderer=_scene.sea.source_shadows;_effect=_source_renderer._effect
	if _effect==null:printerr("FAIL real compositor unavailable");main.free();quit(1);return
	_all=_source_renderer._volumes.values();_color=_effect.get("_color")
	_effect.enabled=false;await frames(3);await RenderingServer.frame_post_draw
	_baseline=_scene.view.get_texture().get_image();_baseline.save_png(output+"/stencil-off.png")
	_baseline=_baseline.duplicate();_baseline.convert(Image.FORMAT_RGBA8);_baseline_bytes=_baseline.get_data()
	var initial:Dictionary=await _probe(_all,"all")
	await _split(_all,"group",initial)
	var restored:Dictionary=await _probe(_all,"restored-all")
	if restored.line!=initial.line:_errors.append("restored complete caster set did not reproduce initial line pixels")
	var sources:Dictionary={}
	for source:String in ["res://tools/diagnose-shadow-casters-gpu.gd","res://modules/scene_engine/fidelity_fx/source_shadow_rd.gd","res://modules/scene_engine/fidelity_fx/source_shadow_math.gd","res://game/presentation/world/target_rigid_shadow_caster.gd"]:sources[source]=FileAccess.get_sha256(source)
	var proof:={"valid":_errors.is_empty(),"errors":_errors,"cases":_cases,"contributors":_contributors,"interactions":_interactions,"sources":sources,"sourceCasterCount":_all.size(),"camera":_scene.camera.global_transform,"sceneTime":_scene.seconds,"viewportSize":_baseline.get_size(),"baselineSHA256":FileAccess.get_sha256(output+"/stencil-off.png"),"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"scope":"Diagnostic source-volume filtering only, same actual shared scene at24s. All casters restored before cleanup. No production removal, shader, topology or gameplay change. Bisection preserves ordering inside each subset; combined-only interactions are recorded explicitly."}
	var file:=FileAccess.open(output+"/CASTER_ISOLATION.json",FileAccess.WRITE);file.store_string(JSON.stringify(proof,"\t"));file.close()
	main.free();await frames(3)
	print("SHADOW_CASTER_ISOLATION cases=",_cases.size()," contributors=",_contributors.size()," interactions=",_interactions.size()," failures=",_errors.size())
	quit(0 if _errors.is_empty() else 1)
