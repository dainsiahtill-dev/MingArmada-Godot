extends SceneTree
var assertions:=0
var failures:=0
var fields: Array=[]
class FakeField extends RefCounted:
	var options: Dictionary={}
	var calls: Array=[]
	var acks: Array=[]
	var disposal_count:=0
	var pending:=false
	var generation:=0
	var processed:=false
	var configure_error:=""
	var surface: Dictionary={}
	var texture:=ImageTexture.new()
	func configure(value:Dictionary)->Dictionary:
		options=value.duplicate(true)
		return {"ok":configure_error.is_empty(),"pending":configure_error.is_empty(),"error":configure_error}
	func advance(seconds:float,center:Vector2,emitters:Array,wakes:Array=[])->Dictionary:
		calls.append({"seconds":seconds,"center":center,"emitters":emitters.duplicate(true),"wakes":wakes.duplicate(true)});pending=true;return diagnostics()
	func complete(initial:bool=false)->void:
		generation+=1;pending=false
		processed=not initial and not calls.is_empty()
		var extent:=float(options.get("extent_m",96.0));var n:=float(options.get("resolution",256));var dx:=extent/n
		var input:Dictionary=calls.back() if not calls.is_empty() else {"seconds":0.0,"center":Vector2.ONE*extent*.5}
		var origin:Vector2=(input.center/dx).floor()*dx-Vector2.ONE*extent*.5
		surface={"generation":generation,"texture":texture,"time":input.seconds,"bounds":Vector4(origin.x,origin.y,origin.x+extent,origin.y+extent)}
	func diagnostics()->Dictionary:return {"ready":not surface.is_empty(),"pending":pending,"error":"","time":surface.get("time",0.0),"resets":1 if processed else 0,"resolution":options.get("resolution",256),"extent_m":options.get("extent_m",96.0)}
	func acquire_surface()->Dictionary:return surface.duplicate() if disposal_count==0 else {}
	func acknowledge_surface(value:int)->void:acks.append(value)
	func dispose()->void:disposal_count+=1
class FakeOcean extends RefCounted:
	var reject:=false
	var bindings:Array=[]
	func bind_interactive_wake_field(texture:Texture2D,bounds:Vector4,enabled:bool)->bool:
		if enabled and reject:return false
		bindings.append({"texture":texture,"bounds":bounds,"enabled":enabled});return true
func _initialize()->void:run.call_deferred()
func check(ok:bool,why:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: ",why)
func flat(_x:float,_z:float,_seconds:float)->float:return 0.0
func factory()->RefCounted:
	var field:=FakeField.new();fields.append(field);return field
func actor(id:String,x:float=0.0,z:float=0.0,length:float=20.0)->Dictionary:
	var transform:=Transform3D(Basis.IDENTITY,Vector3(x,0,z))
	return {"id":id,"hull_alive":true,"attachment":{"bow":transform*Vector3(0,0,length*.5),"surfaceProfile":{"sections":[{"z":-length*.5,"left":-2.0,"right":2.0},{"z":length*.5,"left":-2.0,"right":2.0}],"hullToWorld":transform}}}
func mask(revision:int=1,value:int=255)->Dictionary:
	return {"valid":true,"revision":revision,"cell_m":10.0,"resolution":2,"bounds":Vector4(-100,-100,100,100),"data":PackedByteArray([value,255,255,255])}
func run()->void:
	var path:="res://modules/scene_engine/water/interactive_wake_system.gd"
	check(ResourceLoader.exists(path),"production-reusable wake owner must coordinate whole ships and published coverage")
	if ResourceLoader.exists(path):
		var System=load(path)
		var ocean:=FakeOcean.new();var system=System.new()
		check(system.configure(ocean,flat,mask(),{"field_factory":factory}).ok,"injected field seam configures real owner and real producer")
		var f:FakeField=fields.back()
		check(not f.options.wet_mask.has("revision") and not f.options.wet_mask.has("cell_m"),"terrain metadata stripped before field configure")
		var fleet: Array=[actor("d",9),actor("c",6),actor("focus"),actor("b",3),actor("far",200)]
		system.apply_snapshot(0.0,"focus",fleet,"epochA")
		check(system.covered_actor_ids().is_empty(),"requested but unpublished ships retain source fallback")
		check(f.calls.size()==1 and f.calls[0].emitters.size()==15,"at most three whole ships upload15 probes")
		check(system.diagnostics().selected==["focus","b","c"],"focus first, strict world distance next, deterministic ids")
		check(f.calls[0].center==Vector2(0,-30),"center uses actual20m waterline length and8m bow safety")
		for id in ["focus","b","c"]:
			var count:=0
			for emitter:Dictionary in f.calls[0].emitters:
				if emitter.id.begins_with(id+":probe"):count+=1
			check(count==5,"selected actor keeps all five probes: "+id)
		f.complete();ocean.reject=true;system.poll()
		check(system.covered_actor_ids().is_empty() and f.acks.is_empty(),"failed ocean binding neither ACKs nor hides source")
		ocean.reject=false;system.poll()
		check(system.covered_actor_ids()==["focus","b","c"] and f.acks.size()==1,"coverage only follows successful binding of matching published input")
		system.apply_snapshot(0.0,"focus",fleet,"epochA")
		check(f.calls.size()==1 and f.calls[0].emitters.size()==15,"same-time redraw cannot enqueue empty replacement force")
		var count_before:=fields.size();var replacement:=FakeOcean.new()
		system.set_ocean(replacement,mask(2))
		check(fields.size()==count_before and f.disposal_count==0,"same actual mask bytes preserve field across quality rebuild")
		check(system.covered_actor_ids()==["focus","b","c"],"paused rebind retains covered actors without requiring new force")
		check(not ocean.bindings.back().enabled and replacement.bindings.back().enabled,"old ocean detached and rebuilt ocean receives current pair")
		var removed:Array=[actor("focus"),actor("c",6),actor("d",9)]
		system.apply_snapshot(0.0,"focus",removed,"epochA")
		check("b" not in system.covered_actor_ids() and f.calls.size()==1,"paused removal forgets actor without touching force clock")
		check(system.diagnostics().history_actors==2,"removed producer history released while paused")
		var shifted:Array=[actor("focus"),actor("c",200),actor("d",9)]
		system.apply_snapshot(0.0,"focus",shifted,"epochA")
		check("c" not in system.covered_actor_ids(),"actor outside published field regains fallback even on redraw")
		system.apply_snapshot(0.1,"focus",[],"epochA")
		check(f.calls.size()==2 and f.calls.back().emitters.is_empty(),"empty fleet advances old foam without inventing emitters")
		check(system.covered_actor_ids().is_empty() and system.diagnostics().history_actors==0,"empty fleet releases all coverage and producer history")
		f.complete();system.poll()
		system.apply_snapshot(0.2,"focus",[actor("focus")],"epochB")
		check(f.disposal_count==1 and fields.size()==count_before+1,"epoch change recreates field and clears old history")
		var epoch_field:FakeField=fields.back();epoch_field.complete();system.poll()
		system.apply_snapshot(0.3,"focus",[actor("focus",100)],"epochB")
		check(epoch_field.disposal_count==1 and system.diagnostics().resets>=2,"real producer warp recreates field before connecting distant water")
		var warped:FakeField=fields.back()
		check(warped.calls.back().emitters[0].velocity==Vector3.ZERO,"postwarp first force has no artificial derivative")
		var before_mask:=fields.size();system.set_ocean(replacement,mask(3,0))
		check(fields.size()==before_mask+1 and warped.disposal_count==1,"changed actual R8 mask clears field and producer")
		var masked:FakeField=fields.back()
		system.set_ocean(replacement,{"valid":false,"revision":4})
		check(masked.disposal_count==1 and system.covered_actor_ids().is_empty() and not system.diagnostics().error.is_empty(),"invalid terrain metadata explicitly falls back and releases field")
		system.set_ocean(replacement,mask())
		check(system.diagnostics().error.is_empty(),"valid terrain data can recover disabled owner")
		system.apply_snapshot(0.4,"missing",[actor("z",5),actor("a",5)],"epochB")
		check(system.diagnostics().selected==["a","z"],"missing focus falls back deterministically with id tie break")
		var final_field:FakeField=fields.back();system.dispose();system.dispose()
		check(final_field.disposal_count==1 and system.covered_actor_ids().is_empty(),"system disposal is idempotent and leaves no coverage")
		long_hull(System)
		var boot=System.new();boot.configure(FakeOcean.new(),flat,{}, {"field_factory":factory})
		boot.apply_snapshot(0.0,"boot",[actor("boot")],"boot")
		var boot_field:FakeField=fields.back();boot_field.complete(true);boot.poll()
		check(boot.covered_actor_ids().is_empty(),"initial zero texture cannot cover pending actor input at the same timestamp")
		boot_field.complete();boot.poll()
		check(boot.covered_actor_ids()==["boot"],"initial texture ACK must preserve time0 record until first actor field completes")
		boot.dispose()
		var failed:=FakeField.new();failed.configure_error="GPU unavailable"
		var unavailable=System.new()
		check(not unavailable.configure(FakeOcean.new(),flat,{}, {"field_factory":func():return failed}).ok,"field configuration failure is reported to caller")
		unavailable.apply_snapshot(0.0,"focus",[actor("focus")],"failure")
		check(failed.disposal_count==1 and failed.calls.is_empty(),"failed field is released and receives no production input")
		check(unavailable.covered_actor_ids().is_empty(),"unavailable field cannot hide original tail")
		unavailable.dispose()
		for trigger in ["epoch","warp","rewind","mask"]:reset_failure(System,trigger)
	print("INTERACTIVE_WAKE_SYSTEM assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
func long_hull(System)->void:
	var system=System.new();system.configure(FakeOcean.new(),flat,{}, {"field_factory":factory})
	system.apply_snapshot(0.0,"long",[actor("long",0,0,70)],"long")
	var f:FakeField=fields.back()
	check(system.diagnostics().selected==["long"] and f.calls.back().center==Vector2(0,-5),"long70m hull moves center ahead while keeping full probe set")
	check(f.calls.back().emitters.size()==5,"long hull probes are never truncated to fit field")
	system.dispose()
	var huge=System.new();huge.configure(FakeOcean.new(),flat,{}, {"field_factory":factory})
	huge.apply_snapshot(0.0,"huge",[actor("huge",0,0,120)],"huge")
	check(huge.diagnostics().selected.is_empty() and huge.covered_actor_ids().is_empty(),"hull that cannot fit inner field stays on original fallback")
	check(fields.back().calls.size()==1 and fields.back().calls.back().emitters.is_empty(),"valid but uncovered ships still advance historical field decay")
	huge.dispose()
func reset_failure(System,trigger:String)->void:
	var created:Array=[]
	var switching_factory:Callable=func():
		var candidate:=FakeField.new()
		if not created.is_empty():candidate.configure_error="reconfiguration unavailable"
		created.append(candidate)
		return candidate
	var system=System.new()
	check(system.configure(FakeOcean.new(),flat,{}, {"field_factory":switching_factory}).ok,"first configuration succeeds before "+trigger+" failure")
	system.apply_snapshot(1.0,"focus",[actor("focus")],"epochA")
	created[0].complete();system.poll()
	check(system.covered_actor_ids()==["focus"],"live coverage established before "+trigger+" failure")
	var next_time:=0.5 if trigger=="rewind" else 1.1
	var next_actor:=actor("focus",100) if trigger=="warp" else actor("focus")
	var next_epoch:="epochB" if trigger=="epoch" else "epochA"
	var rejected:Variant=system.set_ocean(FakeOcean.new(),mask()) if trigger=="mask" else system.apply_snapshot(next_time,"focus",[next_actor],next_epoch)
	check(rejected is Dictionary and str(rejected.get("error","")).contains("reconfiguration unavailable"),"failed "+trigger+" rebuild returns safe fallback receipt")
	check(created.size()==2 and created[0].disposal_count==1 and created[1].disposal_count==1,"failed "+trigger+" rebuild releases old and rejected resources once")
	check(created[1].calls.is_empty() and system.covered_actor_ids().is_empty(),"failed "+trigger+" rebuild cannot advance missing field or hide tail")
	check(system.diagnostics().history_actors==0 and system.diagnostics().pending_records==0,"failed "+trigger+" rebuild leaves no new producer or input records")
	system.poll();system.dispose();system.dispose()
