extends SceneTree
## Inject a failed effect preparation without deleting or corrupting originals.
const Sea = preload("res://game/presentation/world/naval_world_view.gd")
const Encounter = preload("res://modules/naval_simulation/encounter.gd")
const Services = preload("res://game/scenes/common/sea_services.gd")
const Settings = preload("res://game/persistence/user_settings.gd")
class FailingSea extends Sea:
	var fail_atmosphere := true
	var preparations := 0
	func _prepare_atmosphere(owner:Node3D)->Dictionary:
		preparations+=1
		if fail_atmosphere:return {"ok":false,"reason":"test-atmosphere-unavailable"}
		return owner.configure_atmosphere({"enabled":bool(_options.get("combat_atmosphere",true)),"quality":_settings.quality},_destruction_anchor)
class PauseOwner extends RefCounted:
	var reasons:Dictionary={}
	var notice:=""
	func set_handling_mode(_mode:String)->void:pass
	func set_pause(reason:String,value:bool)->Dictionary:
		if value:reasons[reason]=true
		else:reasons.erase(reason)
		return {"ok":true}
	func _notify(value:String)->void:notice=value
var assertions:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,message:String)->bool:
	assertions+=1
	if not value:failures+=1;printerr("FAIL COMBAT ATMOSPHERE FAILURE: ",message)
	return value
func ground(_x:float,_z:float)->float:return -80.0
func water(_x:float,_z:float,_t:float)->float:return 0.0
func run()->void:
	var sea:Node3D=FailingSea.new();root.add_child(sea)
	if not check(sea.has_method("presentation_status") and sea.has_signal("presentation_failed"),"world exposes explicit presentation failure status and signal"):
		sea.free();finish();return
	var receipts:Array=[]
	sea.connect("presentation_failed",func(receipt:Dictionary)->void:receipts.append(receipt.duplicate(true)))
	var encounter:=Encounter.new({"battleId":"fx-failure-old","playerId":"player","oceanWaves":[],"sampleTerrainHeight":ground,"ships":[{"id":"player","kind":"fuchuan","team":"player","position":{"x":0.0,"z":0.0}}]})
	if not check(encounter.last_error.is_empty(),"real initial encounter configures"):sea.free();finish();return
	var native:Dictionary=encounter.snapshot()
	var options:Dictionary={"chunk_radius":0,"resolution":8,"ocean_resolution":24,"ocean_distance":1200.0,"vegetation":false,"island_details":false,"fidelity_islands":false,"interactive_wake":false}
	sea.apply_settings({"quality":"low","cameraFollow":false})
	check(not sea.configure(ground,[],water,native,options),"initial failed atmosphere rejects world startup")
	var failed:Dictionary=sea.presentation_status()
	check(not failed.ready and failed.failed and failed.reason=="test-atmosphere-unavailable","startup failure retains explicit underlying reason")
	check(sea.get_child_count()==0 and sea.camera==null and sea.effects==null and sea.world==null,"rejected startup disposes all partially owned renderers")
	check(receipts.size()==1 and receipts[0].phase=="configure","startup emits one explicit failure receipt")
	sea.fail_atmosphere=false
	check(sea.configure(ground,[],water,native,options) and sea.presentation_status().ready,"explicit reconfigure can recover using valid assets")
	var owner:=PauseOwner.new()
	var services:=Services.new();root.add_child(services)
	services.configure(owner,sea,Settings.new("user://unused-failure-probe-settings.json"))
	services.audio.set_paused(false)
	var old_camera:Camera3D=sea.camera
	var old_effects:Node3D=sea.effects
	var old_ship:Node3D=sea.ships.player
	var prior:Dictionary=sea.get("_snapshot").duplicate(true)
	var previous_children:=sea.get_child_count()
	sea.fail_atmosphere=true
	var next:Dictionary=native.duplicate(true);next.battleId="fx-failure-new"
	check(sea.apply_snapshot(next,[],0.0).is_empty(),"failed epoch preparation produces no fabricated event success")
	failed=sea.presentation_status()
	check(not failed.ready and failed.failed and failed.reason=="test-atmosphere-unavailable","failed reset remains explicitly not ready")
	check(sea.camera==old_camera and sea.effects==old_effects and sea.ships.get("player")==old_ship and sea.get_child_count()==previous_children,"failed reset preserves last valid camera/actors/effects and frees candidate")
	check(sea.get("_snapshot")==prior and sea.get("_battle_id")=="fx-failure-old","failed replacement cannot adopt a different authority epoch")
	check(receipts.size()==2 and receipts[1].phase=="reset","reset emits one owner-visible failure receipt")
	check(owner.reasons.has("error") and owner.notice.contains("test-atmosphere-unavailable"),"shared services pause actual runtime owner and expose the specific failure")
	check(services.audio.diagnostics().state=="paused","failure immediately pauses audio before the caller's next presentation")
	services.present(next,[],0.0,false)
	check(services.audio.diagnostics().state=="paused","stale same-frame caller pause flag cannot resume failed-world audio")
	var attempts:int=sea.preparations
	sea.apply_local_fire(next,[],0.0);sea.apply_snapshot(next,[],0.0)
	check(sea.preparations==attempts and receipts.size()==2,"latched failure does not retry allocation or duplicate notification every rendered frame")
	services.dispose()
	check(not sea.is_connected("presentation_failed",Callable(services,"_on_presentation_failed")),"disposed services disconnect the failure subscription")
	sea.fail_atmosphere=false
	check(sea.configure(ground,[],water,next,options) and sea.presentation_status().ready and not sea.presentation_status().failed,"explicit recovery clears failed latch and adopts the new epoch")
	sea.dispose()
	check(not sea.presentation_status().ready and sea.get_child_count()==0,"normal dispose cannot report ready")
	services.free();sea.free();finish()
func finish()->void:
	print("COMBAT_ATMOSPHERE_FAILURE_TEST assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
