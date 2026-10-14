extends SceneTree
const Math=preload("res://modules/scene_engine/fidelity_fx/source_shadow_math.gd")
const Adapter=preload("res://game/presentation/world/target_rigid_shadow_caster.gd")
const Ship=preload("res://game/presentation/ships/ship_view.gd")
var assertions:=0
var failures:=0
func check(ok:bool,label:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL cap candidate: ",label)
func _initialize()->void:run.call_deferred()
func _boundary(volume:Dictionary)->int:
	var welded:Dictionary={};var ids:Array=[];var balances:Dictionary={}
	for point:Array in volume.positions:
		var p:=Vector3(point[0],point[1],point[2])
		if not welded.has(p):welded[p]=welded.size()
		ids.append(welded[p])
	for offset in range(0,volume.indices.size(),3):
		for side in 3:
			var a:int=ids[volume.indices[offset+side]];var b:int=ids[volume.indices[offset+(side+1)%3]]
			if a==b:continue
			var key:=Vector2i(mini(a,b),maxi(a,b));balances[key]=int(balances.get(key,0))+(1 if a<b else -1)
	var count:=0
	for value:int in balances.values():count+=int(value!=0)
	return count
func run()->void:
	var path:="res://game/research/shadow_cap_winding_candidate.gd"
	if not ResourceLoader.exists(path):check(false,"independent cap-only candidate exists");finish();return
	var candidate:Script=load(path)
	var original:Dictionary=Math.build_volume_component([[-1,-1,-2],[1,-1,-2],[0,1,-2]],[0,0,-1],[[0,1],[1,2],[2,0]],[0,1,2])
	var before:=var_to_bytes(original)
	var adapted:Dictionary=candidate.adapt(original)
	check(adapted.ok and adapted.sideTriangles==3 and adapted.capTriangles==1,"source triangle layout identifies exactly three side triangles and one cap")
	check(adapted.geometry.indices==[2,1,0,4,3,0,6,5,0,7,8,9],"candidate flips only the literal source cap triangle")
	check(_boundary(original)==3 and _boundary(adapted.geometry)==0,"cap-only change closes the three inconsistent directed near-boundary edges")
	check(var_to_bytes(original)==before and adapted.geometry.positions==original.positions and adapted.geometry.direction==original.direction,"candidate cannot alter source input, source points, direction or finite apex")
	var damaged:Dictionary=original.duplicate(true);damaged.indices[1]=8
	check(not candidate.adapt(damaged).ok,"unknown side-index layout is rejected without guessing its cap range")
	var ship:=Ship.new();root.add_child(ship);check(ship.configure("fuchuan"),"actual imported ship configures")
	var adapter:=Adapter.new();var packet:Dictionary=adapter.compose({}, {"ship":ship},Vector3(.35,-.8,.5).normalized(),false)
	var count_before:=0;var count_after:=0;var triangles:=0
	for caster:Dictionary in packet.native.sourceShadows.casters:
		var volume:Dictionary=Math.build_volume_component(caster.positions,caster.localLight,caster.edges,caster.capIndices)
		var converted:Dictionary=candidate.adapt(volume)
		check(converted.ok,"actual source component layout qualifies: "+caster.id)
		if not converted.ok:continue
		check(converted.geometry.positions==volume.positions and converted.geometry.direction==volume.direction and converted.geometry.vertexCount==volume.vertexCount and converted.geometry.triangleCount==volume.triangleCount,"actual candidate preserves all geometry payload except cap winding")
		count_before+=int(_boundary(volume)>0);count_after+=int(_boundary(converted.geometry)>0);triangles+=converted.capTriangles
	check(count_before>0 and count_after<count_before and triangles>0,"actual target components expose a closure improvement without removing any caster")
	print("SHADOW_CAP_CANDIDATE_EVIDENCE casters=",packet.native.sourceShadows.casters.size()," openBefore=",count_before," openAfter=",count_after," capTriangles=",triangles)
	adapter.dispose();ship.dispose();ship.free();finish()
func finish()->void:
	print("SHADOW_CAP_WINDING_CANDIDATE_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
