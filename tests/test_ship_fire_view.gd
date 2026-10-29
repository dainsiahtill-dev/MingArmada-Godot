extends SceneTree
const PATH:="res://game/presentation/combat/ship_fire_view.gd"
const Fire=preload("res://modules/naval_simulation/combat/fire_control.gd")
var checks:=0
var failures:=0
func _initialize()->void:_run.call_deferred()
func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures+=1;printerr("FAIL live fire: ",label)
	return ok
func _run()->void:
	if not check(ResourceLoader.exists(PATH),"state driven living-fire view exists"):_finish();return
	var script:Script=load(PATH)
	var view:Node3D=script.new();root.add_child(view)
	var anchor:Dictionary={"position":Vector3(3,4,5),"time":0.0,"shipId":"ship"}
	check(view.configure({},null,func(_x:float,_z:float,_t:float)->float:return 0.0,func(_id:String)->Dictionary:return anchor).ok,"original PNG view configures")
	var fire:Dictionary=Fire.ignite(Fire.initial(24),"thorn-ball",0.0).state
	var packet:Dictionary={"time":0.0,"battleId":"live-fire","wind":{"direction":{"x":1.0,"y":0.0},"speed":10.0},"ships":[{"id":"ship","hull":100.0,"fireControl":fire}]}
	var original:Dictionary=packet.duplicate(true)
	view.apply_snapshot(packet);view.refresh_anchors()
	var started:Dictionary=view.diagnostics()
	check(started.living_fires==1 and started.active_flames>0 and started.active_smoke>0,"real positive heat drives fire and smoke without fabricated death event")
	view.apply_snapshot(packet);view.refresh_anchors()
	check(view.diagnostics()==started,"same accepted time is idempotent")
	packet.time=.5;anchor.time=.5;anchor.position=Vector3(13,4,5)
	view.apply_snapshot(packet);view.refresh_anchors()
	var moved:Dictionary=view.diagnostics()
	var historical_smoke:=false
	for particle:Dictionary in moved.particles:
		if particle.kind=="flame":check(absf(float(particle.position[0])-13.0)<2.0,"flames follow actual current deck once")
		if particle.kind=="smoke" and particle.born==0.0:historical_smoke=absf(float(particle.position[0])-3.0)<3.0
	check(historical_smoke,"older smoke stays in world space after ship moves")
	packet.time=1.0;anchor.time=.5
	view.apply_snapshot(packet);view.refresh_anchors()
	check(view.diagnostics().active_flames==0,"stale anchor never draws fire at an old ship pose")
	anchor.time=1.0;anchor.position=Vector3(13,-1,5)
	view.refresh_anchors();check(view.diagnostics().active_flames==0,"underwater deck cannot show living flame")
	packet.time=1.5;anchor.time=1.5;anchor.position=Vector3(13,4,5);packet.ships[0].fireControl.heat=0.0
	view.apply_snapshot(packet);view.refresh_anchors()
	check(view.diagnostics().living_fires==0 and view.diagnostics().active_flames==0,"quenching removes live flame immediately")
	packet.time=10.0;anchor.time=10.0;view.apply_snapshot(packet);view.refresh_anchors()
	check(view.diagnostics().particles.is_empty(),"residual world smoke has finite lifetime")
	packet.time=0.0;packet.battleId="new-epoch";packet.ships[0].fireControl=Fire.initial(0);anchor.time=0.0
	view.apply_snapshot(packet);view.refresh_anchors()
	check(view.diagnostics().particles.is_empty() and view.diagnostics().living_fires==0,"epoch clears previous live ownership")
	check(original.ships[0].fireControl.heat==28.0 and original.time==0.0,"presentation leaves fire authority untouched")
	view.dispose();check(not view.diagnostics().ready and view.get_child_count()==0,"dispose releases live emitter and all batches")
	view.free();_finish()
func _finish()->void:
	print("SHIP_FIRE_VIEW checks=%d failures=%d"%[checks,failures]);quit(1 if failures else 0)
