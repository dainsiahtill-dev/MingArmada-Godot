extends SceneTree
const Math = preload("res://modules/scene_engine/fidelity_fx/source_shadow_math.gd")
const Adapter = preload("res://game/presentation/world/target_rigid_shadow_caster.gd")
const Renderer = preload("res://modules/scene_engine/fidelity_fx/source_shadow_renderer.gd")
const Effect = preload("res://modules/scene_engine/fidelity_fx/source_shadow_compositor.gd")
const Ship = preload("res://game/presentation/ships/ship_view.gd")
var assertions := 0
var failures := 0
func check(ok:bool,label:String)->bool:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL prepared shadow: ",label)
	return ok
func _initialize()->void:run.call_deferred()
func run()->void:
	var path := "res://game/presentation/world/prepared_rigid_shadow.gd"
	if not ResourceLoader.exists(path): check(false,"isolated prepared rigid shadow component exists");finish();return
	var script:Script=load(path)
	var prepared:RefCounted=script.new()
	var positions:Array=[[0.1,0.2,0.3],[1.2,0.1,0.0],[0.0,1.2,0.0]]
	var faces:Array=[{"indices":[0,1,2],"normal":Vector3(0,0,1)}]
	check(prepared.configure(positions,faces).ok,"finite original geometry prepares")
	var first:Dictionary=prepared.build_volume([0.1,0.2,-1.0])
	var saved:=var_to_bytes(first)
	var reference:Dictionary=Math.build_volume_component(positions,[0.1,0.2,-1.0],[[0,1],[1,2],[2,0]],[0,1,2])
	check(first==reference,"prepared output equals complete original Math volume")
	var rebuilds:int=prepared.diagnostics().topologyBuilds
	var second:Dictionary=prepared.build_volume([0.100001,0.2,-1.0])
	check(prepared.diagnostics().topologyBuilds==rebuilds,"same exact face signs reuse topology across changing light")
	check(second.direction!=first.direction and second.positions[0]!=first.positions[0],"changing light still recalculates exact f32 far apex")
	check(var_to_bytes(first)==saved,"previous frame remains byte-identical after apex update")
	positions[0][0]=99.0;faces[0].indices[0]=2
	check(var_to_bytes(prepared.build_volume([0.1,0.2,-1.0]))==saved,"caller input holders cannot mutate prepared source data")
	var absent:Dictionary=prepared.build_volume([0.0,0.0,0.0])
	check(absent.positions.is_empty() and absent.indices.is_empty() and prepared.diagnostics().topologyBuilds==rebuilds+1,"exact zero face boundary rebuilds and removes the facing triangle")
	check(first.is_read_only() and first.positions.is_read_only() and first.positions[0].is_read_only() and first.positions[1].is_read_only() and first.indices.is_read_only(),"published volume is recursively immutable")
	check(prepared.build_volume([INF,0.0,-1.0]).has("error"),"nonfinite light rejected before publishing")
	check(not prepared.configure([[INF,0,0]],faces).ok,"nonfinite source rejected")
	await real_adapter_and_publication()
	finish()
func real_adapter_and_publication()->void:
	var ship:=Ship.new();root.add_child(ship);check(ship.configure("fuchuan"),"real ship configures")
	var adapter:=Adapter.new();var renderer:=Renderer.new();var camera:=Camera3D.new();root.add_child(camera)
	renderer.configure(ship,camera)
	var packet:Dictionary=adapter.compose({}, {"ship":ship},Vector3(.35,-.8,.5).normalized(),false)
	renderer.apply_snapshot(packet.native,packet.actors)
	var first:Dictionary=renderer.get("_volumes").duplicate(true)
	var bytes:=var_to_bytes(first)
	var effect:=Effect.new()
	if not check(effect.has_method("submit_prepared"),"compositor has a typed immutable submission boundary"):
		renderer.dispose();adapter.dispose();ship.dispose();ship.free();camera.free();return
	var frame_script:Script=load("res://modules/scene_engine/fidelity_fx/prepared_shadow_frame.gd")
	var prepared_frame:RefCounted=frame_script.new()
	prepared_frame.configure(renderer.get("_volumes").values())
	effect.submit_prepared(prepared_frame,Color.BLACK)
	var publication:Array=effect.get("_volumes")
	var publication_bytes:=var_to_bytes(publication)
	for step in 12:
		ship.rotation.y=float(step)*.0001
		packet=adapter.compose({}, {"ship":ship},Vector3(.35+step*.000001,-.8,.5).normalized(),false)
		renderer.apply_snapshot(packet.native,packet.actors)
		for caster:Dictionary in packet.native.sourceShadows.casters:
			var actual:Dictionary=renderer.get("_volumes")[caster.id].geometry
			var original:Dictionary=Math.build_volume_component(caster.positions,caster.localLight,caster.edges,caster.capIndices)
			var original_prefix:bool=actual.direction==original.direction and actual.positions.slice(0,original.positions.size())==original.positions and actual.indices.slice(0,original.indices.size())==original.indices
			# Generic Prepared remains the complete Math oracle above. The target
			# adapter now appends directed-boundary sides for nonmanifold meshes.
			check(actual==original if actual.triangleCount==original.triangleCount else original_prefix,"real target retains exact complete Math or its unchanged prefix at changing light")
	check(var_to_bytes(first)==bytes and var_to_bytes(publication)==publication_bytes,"old render publication remains unchanged while all real casters advance")
	check(renderer.diagnostics().get("preparedBuilds",0)>0,"actual adapter and renderer use the prepared production path")
	var generic:Dictionary=packet.native.sourceShadows.casters[0].duplicate(false)
	generic.positions=generic.positions.duplicate(true);generic.positions[0][0]+=2.0;generic.dirty=true
	renderer.apply_snapshot({"sourceShadows":{"casters":[generic]}},packet.actors)
	check(renderer.get("_volumes")[generic.id].geometry==Math.build_volume_component(generic.positions,generic.localLight,generic.edges,generic.capIndices),"replaced mutable source holder falls back to full original Math")
	var mutable:Array=[{"geometry":{"positions":[[1,2,3]],"indices":[0]},"transform":Transform3D.IDENTITY}]
	effect.submit(mutable,Color.BLACK);mutable[0].geometry.positions[0][0]=9
	check(effect.get("_volumes")[0].geometry.positions[0][0]==1,"default compositor submission keeps deep-copy isolation")
	prepared_frame.configure(mutable);effect.submit_prepared(prepared_frame,Color.BLACK)
	var safe:Array=effect.get("_volumes");mutable[0].geometry.positions[0][0]=7
	check(safe[0].geometry.positions[0][0]==9,"typed frame also deep-freezes arbitrary mutable input")
	check(not prepared_frame.configure([{"geometry":{"unowned":RefCounted.new()}}]) and prepared_frame.snapshot()==safe,"unowned object references cannot obtain a frozen frame certificate")
	renderer.dispose();adapter.dispose();ship.dispose();ship.free();camera.free()
func finish()->void:
	print("RIGID_SHADOW_PREPARATION_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
