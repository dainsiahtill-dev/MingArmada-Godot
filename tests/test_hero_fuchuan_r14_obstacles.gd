extends SceneTree
## Independent raw-GLB research fixture, no production provider mutation.
const Library=preload("res://modules/scene_engine/assets/asset_library.gd")
const Hero=preload("res://modules/scene_engine/assets/hero_ship_provider.gd")
const Deck=preload("res://game/presentation/crew/deck_stations.gd")
class Redirect extends RefCounted:
	var owner=Library.new()
	var actual_paths:Array[String]=[]
	func instantiate_model(path:String)->Node3D:
		var actual:=path.replace("/hero_fuchuan_v3_r7c/","/hero_fuchuan_v3_r14/")
		actual_paths.append(actual)
		return owner.instantiate_model(actual)
	func dispose()->void:owner.dispose()
var checks:=0
var failures:Array[String]=[]
var output:Array=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,detail:String)->bool:
	checks+=1
	if not ok:failures.append(detail);printerr("FAIL: ",detail)
	return ok
func role_counts(stations:Array)->Dictionary:
	var result:Dictionary={}
	for station:Dictionary in stations:
		var key:String=station.role+":"+str(station.side)
		result[key]=result.get(key,0)+1
	return result
func run()->void:
	var hero=Hero.new("art_r7c",true);var redirect=Redirect.new()
	for lod in range(3):
		var baseline:Node3D=hero.instantiate_ship("fuchuan",lod)
		var candidate:Node3D=hero.instantiate_ship("fuchuan",lod,redirect)
		if not check(baseline!=null and candidate!=null,"actual provider loads both models LOD%d"%lod):continue
		check(redirect.actual_paths[lod]=="res://assets/models/hero_fuchuan_v3_r14/fuchuan-lod%d.glb"%lod,"actual requested candidate path LOD%d"%lod)
		check(baseline.find_children("cannon_port_*","Node3D",true,false).size()==4 and baseline.find_children("cannon_starboard_*","Node3D",true,false).size()==4,"baseline four guns each side")
		check(candidate.find_children("cannon_port_*","Node3D",true,false).size()==4 and candidate.find_children("cannon_starboard_*","Node3D",true,false).size()==4,"candidate four guns each side")
		check(baseline.find_children("socket_smoke_*","Node3D",true,false).size()==candidate.find_children("socket_smoke_*","Node3D",true,false).size(),"gun sockets retained")
		check(candidate.find_child("rudder_pivot",true,false)!=null and candidate.find_child("deck",true,false)!=null,"rudder and support remain")
		var old_deck=Deck.new();var new_deck=Deck.new()
		check(old_deck.configure("fuchuan",baseline) and new_deck.configure("fuchuan",candidate),"real deck-station algorithm builds")
		check(old_deck.faces==new_deck.faces,"support surface unchanged")
		check(new_deck._obstacles.size()==old_deck._obstacles.size()+2,"new coamings contribute two real obstacles")
		var bounds:Array=[];var cannon_clearance:Array=[]
		# Godot sanitizes glTF node-name dots to underscores on actual import.
		for name:String in ["cargo_hold_coaming_-3_2","cargo_hold_coaming_5_8"]:
			var coaming:=candidate.find_child(name,true,false) as MeshInstance3D
			if not check(coaming!=null,"coaming exists "+name):continue
			check(coaming.get_meta("deck_obstacle",false),"provider exposes obstacle "+name)
			var box:AABB=new_deck._bounds(coaming,candidate);bounds.append([box.position.x,box.position.y,box.position.z,box.size.x,box.size.y,box.size.z])
			check(absf(box.size.x-2.2)<.001 and absf(box.size.z-2.7)<.001,"coaming bounds match LOD%d"%lod)
			check(box in new_deck._obstacles,"real obstacle array contains coaming")
			var nearest_cannon:=INF;var nearest_station:Dictionary={}
			for station:Dictionary in new_deck.stations:
				var actor:=AABB(station.position+Vector3(-.34,.02,-.32),Vector3(.68,1.69,.64))
				check(not actor.intersects(box),"crew station avoids "+name)
				if station.role=="cannon":
					var dx:=maxf(0.0,maxf(box.position.x-actor.end.x,actor.position.x-box.end.x))
					var dz:=maxf(0.0,maxf(box.position.z-actor.end.z,actor.position.z-box.end.z))
					var distance:=Vector2(dx,dz).length()
					if distance<nearest_cannon:
						nearest_cannon=distance
						nearest_station={"side":station.side,"position":[station.position.x,station.position.y,station.position.z]}
			check(nearest_cannon>0.0 and nearest_cannon<INF,"cannon actor footprint clears "+name)
			cannon_clearance.append({"coaming":name,"nearestFootprintDistanceXZ":nearest_cannon,"station":nearest_station})
		var old_roles:=role_counts(old_deck.stations);var new_roles:=role_counts(new_deck.stations)
		for key:String in ["helm:","haul:","cannon:port","cannon:starboard","lookout:"]:
			if old_roles.has(key):check(new_roles.get(key,0)>0,"candidate retains baseline role "+key)
		output.append({"lod":lod,"oldStations":old_deck.stations.size(),"newStations":new_deck.stations.size(),"oldRoles":old_roles,"newRoles":new_roles,"oldObstacleCount":old_deck._obstacles.size(),"newObstacleCount":new_deck._obstacles.size(),"coamingBounds":bounds,"cannonClearance":cannon_clearance})
		baseline.free();candidate.free()
	redirect.dispose()
	var report={"checks":checks,"failures":failures,"lods":output,"scope":"Actual Godot imported geometry and instantaneous DeckStations sample only; no animated paths, muzzle sweep, collision or GPU acceptance."}
	var path="res://docs/production/hero-fuchuan-2026-10-26-art/r14-author-01/obstacles-03.json"
	if FileAccess.file_exists(path):printerr("FAIL: fresh report required");quit(1);return
	var file=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("HERO_R14_OBSTACLES checks=",checks," failures=",failures.size()," details=",JSON.stringify(output))
	quit(1 if failures.size() else 0)
