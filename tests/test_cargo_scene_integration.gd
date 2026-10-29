extends SceneTree
const Scene = preload("res://game/scenes/mingqi/mingqi_scene.gd")
const Sea = preload("res://game/presentation/world/naval_world_view.gd")
var checks:=0
var failures:=0
func _initialize()->void:_run.call_deferred()
func check(ok:bool,message:String)->bool:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",message)
	return ok
func same_manifest(a:Dictionary,b:Dictionary)->bool:
	if a.size()!=b.size():return false
	for good:Variant in a:
		if not b.has(good) or a[good]!=b[good]:return false
	return true
func _run()->void:
	var stub:=Sea.new()
	var integrated:=stub.has_method("cargo_diagnostics") and stub.has_method("apply_cargo_snapshot")
	stub.free()
	if not check(integrated,"production sea exposes committed cargo projection"): _finish();return
	root.size=Vector2i(1600,900)
	var scene:=Scene.new();root.add_child(scene);await process_frame
	scene.set_process(false);scene.set_physics_process(false)
	if not check(scene.startup_receipt.get("ok",false),"actual Mingqi scene starts"):scene.free();_finish();return
	var state:Dictionary=scene.runtime.snapshot()
	var accept:Dictionary=scene.runtime.command({"type":"accept-convoy","commandId":"cargo-scene-load","expectedRevision":state.campaign.revision})
	check(accept.ok,"actual convoy loads grain")
	scene._present(0.0)
	state=scene.runtime.snapshot()
	var cargo:Dictionary=scene.sea.cargo_diagnostics()
	var loaded:=0
	if not cargo.get("errors",[]).is_empty(): print("CARGO_LAYOUT_ERRORS ",cargo.errors)
	for id:String in cargo.decks:
		var true_manifest:Dictionary=state.campaign.vessels[id].cargo
		check(same_manifest(cargo.decks[id].manifest,true_manifest),"drawn cargo matches true manifest: "+id)
		if true_manifest.get("grain",0)>0:
			if cargo.decks[id].goods.is_empty(): print("CARGO_LAYOUT_DIAGNOSTIC ",id," kind=",cargo.decks[id].kind," slots=",cargo.decks[id].available_slots," source_bounds=",cargo.decks[id].source_bounds," overflow=",cargo.decks[id].overflow_goods)
			loaded+=1;check(cargo.decks[id].goods.size()>0,"loaded ship shows real grain model: "+id)
	check(loaded>=2 and cargo.floating.is_empty(),"convoy manifests draw without inventing cargo loss")
	var before:Dictionary=cargo.duplicate(true)
	scene._present_local_fire(0.0)
	check(scene.sea.cargo_diagnostics().decks.keys()==before.decks.keys() and scene.sea.cargo_diagnostics().floating.is_empty(),"local-fire path retains same cargo owners without false drop")
	scene.runtime.set_pause("player",true)
	scene._present(0.0);before=scene.sea.cargo_diagnostics()
	scene._present(0.0)
	check(scene.sea.cargo_diagnostics()==before,"paused render preserves cargo state exactly")
	var owner:WeakRef=weakref(scene.sea.get("_cargo"))
	scene.free();await process_frame
	check(owner.get_ref()==null,"leaving real scene releases cargo owner")
	_finish()
func _finish()->void:
	print("CARGO_SCENE_INTEGRATION checks=%d failures=%d"%[checks,failures]);quit(1 if failures else 0)
