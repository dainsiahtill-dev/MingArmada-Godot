extends SceneTree
## Read-only source geometry census. No thresholds are changed in production here.
const Hero = preload("res://modules/scene_engine/assets/hero_ship_provider.gd")
const Library = preload("res://modules/scene_engine/assets/asset_library.gd")
const Deck = preload("res://game/presentation/crew/deck_stations.gd")
const Cargo = preload("res://game/presentation/cargo/cargo_deck_view.gd")
const KINDS := ["fuchuan","merchant","fisherman","voc","patrol","heavy"]
var output := "res://docs/research/evidence/cargo-deck-drift/support-probe-01.json"
var matrix_mode := false
var merchant_fine := false
var crew_bounds := AABB()
var crew_ready := false

func _initialize() -> void: run.call_deferred()
func vec(v: Vector3) -> Array: return [v.x,v.y,v.z]
func box(b: AABB) -> Dictionary: return {"position":vec(b.position),"size":vec(b.size)}

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
		if arg=="--matrix":matrix_mode=true
		if arg=="--merchant-fine":matrix_mode=true;merchant_fine=true
	if not output.begins_with("res://docs/research/evidence/cargo-deck-drift/") or output.contains("..") or FileAccess.file_exists(output):
		printerr("CARGO_SUPPORT_PROBE requires fresh confined output");quit(2);return
	var provider := Hero.new(); var library := Library.new()
	var crew_info:Dictionary=read_crew_bounds(library)
	var rows: Array = []
	for kind: String in KINDS:
		if merchant_fine and kind!="merchant":continue
		var model: Node3D=provider.instantiate_ship(kind,0,library)
		if model==null: rows.append({"kind":kind,"error":"source load failed"});continue
		root.add_child(model)
		var deck := Deck.new()
		if not deck.configure(kind,model): rows.append({"kind":kind,"error":"no deck stations/support"});model.free();continue
		var cargo := Cargo.new();root.add_child(cargo)
		var receipt: Dictionary=cargo.configure(model,kind)
		var meshes: Array=[]
		for node:MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
			if node.get_meta("deck_support",false): meshes.append({"name":str(node.name),"bounds":box(deck._bounds(node,model)),"faces":node.mesh.get_faces().size()/3})
		var bins: Dictionary={}
		for index in range(0,deck.faces.size(),3):
			var a:Vector3=deck.faces[index];var b:Vector3=deck.faces[index+1];var c:Vector3=deck.faces[index+2]
			var cross:Vector3=(b-a).cross(c-a)
			if cross.length_squared()<1e-12:continue
			var normal:Vector3=cross.normalized()
			if absf(normal.y)<Cargo.MIN_NORMAL_Y:continue
			var y:float=(a.y+b.y+c.y)/3.0
			var key:int=int(floor(y*10.0))
			if not bins.has(key): bins[key]={"y_bin_low":key*.1,"area_xz":0.0,"up_area":0.0,"down_area":0.0,"triangles":0,"min_y":INF,"max_y":-INF}
			var row:Dictionary=bins[key];var area:float=absf(cross.y)*.5
			row.area_xz+=area;row.triangles+=1;row.min_y=minf(row.min_y,minf(a.y,minf(b.y,c.y)));row.max_y=maxf(row.max_y,maxf(a.y,maxf(b.y,c.y)))
			if normal.y>=0:row.up_area+=area
			else:row.down_area+=area
		var areas:Array=bins.values();areas.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.area_xz>b.area_xz)
		var samples:Array=[];var histogram:Dictionary={}
		var nx:=maxi(0,int(floor((deck.bounds.size.x-Cargo.BOX_SIZE.x)/Cargo.SCAN_STEP))+1)
		var nz:=maxi(0,int(floor((deck.bounds.size.z-Cargo.BOX_SIZE.z)/Cargo.SCAN_STEP))+1)
		for iz in nz:
			for ix in nx:
				var x:float=deck.bounds.position.x+Cargo.HALF_FOOTPRINT+ix*Cargo.SCAN_STEP
				var z:float=deck.bounds.position.z+Cargo.HALF_FOOTPRINT+iz*Cargo.SCAN_STEP
				var support:Dictionary=deck.sample(x,z)
				if support.is_empty() or support.normal.y<Cargo.MIN_NORMAL_Y:continue
				var p:Vector3=support.point;samples.append(p)
				var key:int=int(floor(p.y*10.0));histogram[str(key)]=int(histogram.get(str(key),0))+1
		var bands:Array=best_bands(samples)
		for band:Dictionary in bands:
			band.safe_slots=pack_band(deck,cargo,float(band.low),float(band.high))
		if not matrix_mode and kind in ["merchant","fisherman"] and not bands.is_empty():
			bands[0].classification=classify_band(deck,cargo,float(bands[0].low),float(bands[0].high),Cargo.SCAN_STEP,false)
			bands[0].half_grid=classify_band(deck,cargo,float(bands[0].low),float(bands[0].high),Cargo.SCAN_STEP*.5,true)
			if bands[0].half_grid.safe_slots.size()<12:
				bands[0].fine_grid=classify_band(deck,cargo,float(bands[0].low),float(bands[0].high),Cargo.SCAN_STEP*.2,true)
		if matrix_mode and kind in ["merchant","fisherman","patrol"] and not bands.is_empty():
			var matrix:Array=[]
			var choices:Array=[]
			if merchant_fine:choices=[{"scale":.5,"clearance":.65,"step":.325}]
			else:
				for clearance:float in [.65,.55]:
					for scale:float in [.72,.6,.5]:choices.append({"scale":scale,"clearance":clearance,"step":Cargo.SCAN_STEP})
			for choice:Dictionary in choices:
				var profile:Dictionary={"model_scale":choice.scale,"clearance":choice.clearance,"box_size":Cargo.BOX_SIZE*(float(choice.scale)/Cargo.MODEL_SCALE)}
				var result:Dictionary=classify_band(deck,cargo,float(bands[0].low),float(bands[0].high),float(choice.step),true,profile)
				result.model_scale=choice.scale;result.clearance=choice.clearance;result.box_size=vec(profile.box_size)
				matrix.append(result)
			bands[0].profile_matrix=matrix
		var stations:Array=[]
		for station:Dictionary in deck.stations:stations.append({"role":station.role,"position":vec(station.position),"patrol":vec(station.patrol) if station.has("patrol") else []})
		rows.append({"kind":kind,"source":model.get_meta("source_path",""),"source_family":model.get_meta("source_family",""),"model_scale":vec(model.scale),"bounds":box(deck.bounds),"support_meshes":meshes,"current_receipt":receipt,"triangle_height_bins_by_area":areas.slice(0,30),"exposed_flat_samples":samples.size(),"exposed_height_bins_0_1m":histogram,"dominant_exposed_bands":bands,"stations":stations,"obstacles":deck._obstacles.map(func(v:AABB)->Dictionary:return box(v))})
		var summaries:Array=[]
		for band:Dictionary in bands:
			summaries.append({"low":band.low,"high":band.high,"samples":band.samples,"coarse_slots":band.safe_slots.size(),"coarse_rejections":band.get("classification",{}).get("counts",{}),"half_slots":band.get("half_grid",{}).get("safe_slots",[]).size(),"fine_slots":band.get("fine_grid",{}).get("safe_slots",[]).size()})
		print("CARGO_SUPPORT_PROBE ",kind," samples=",samples.size()," bands=",JSON.stringify(summaries))
		if not bands.is_empty() and bands[0].has("profile_matrix"):
			var brief:Array=[]
			for candidate:Dictionary in bands[0].profile_matrix:brief.append({"scale":candidate.model_scale,"clearance":candidate.clearance,"slots":candidate.safe_slots.size(),"counts":candidate.counts})
			print("CARGO_SUPPORT_MATRIX ",kind," ",JSON.stringify(brief))
		cargo.dispose();cargo.free();model.free()
	library.dispose()
	var report:Dictionary={"scope":"Actual Hero provider LOD0 meshes and DeckSupport sample. Read-only census; proposed bands use existing .65m height allowance. Matrix explicitly explores requested package scales and crew clearance, retaining support/slope/height/obstacle/walkway checks plus original sailor rest mesh AABB. Rest bounds are not a full animated-pose proof; GPU work-pose validation remains required.","crew_source":crew_info,"kinds":rows}
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file==null:printerr("probe output unavailable");quit(2);return
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("CARGO_SUPPORT_PROBE_COMPLETE ",output);quit(0)

func best_bands(samples:Array)->Array:
	var remaining:Array=samples.duplicate()
	remaining.sort_custom(func(a:Vector3,b:Vector3)->bool:return a.y<b.y)
	var result:Array=[]
	for _rank in 3:
		if remaining.is_empty():break
		var best_start:=0;var best_end:=0;var end:=0
		for start in remaining.size():
			end=maxi(end,start)
			while end<remaining.size() and float(remaining[end].y)-float(remaining[start].y)<=Cargo.MAIN_DECK_ALLOWANCE:end+=1
			if end-start>best_end-best_start:best_start=start;best_end=end
		var low:float=remaining[best_start].y
		result.append({"low":low,"high":low+Cargo.MAIN_DECK_ALLOWANCE,"observed_high":remaining[best_end-1].y,"samples":best_end-best_start,"sampled_area_m2":(best_end-best_start)*Cargo.SCAN_STEP*Cargo.SCAN_STEP})
		var next:Array=[]
		for index in remaining.size():
			if index<best_start or index>=best_end:next.append(remaining[index])
		remaining=next
	return result

func pack_band(deck, cargo, low:float, high:float)->Array:
	var selected:Array=[]
	var nx:=maxi(0,int(floor((deck.bounds.size.x-Cargo.BOX_SIZE.x)/Cargo.SCAN_STEP))+1)
	var nz:=maxi(0,int(floor((deck.bounds.size.z-Cargo.BOX_SIZE.z)/Cargo.SCAN_STEP))+1)
	for iz in nz:
		for ix in nx:
			var x:float=deck.bounds.position.x+Cargo.HALF_FOOTPRINT+ix*Cargo.SCAN_STEP
			var z:float=deck.bounds.position.z+Cargo.HALF_FOOTPRINT+iz*Cargo.SCAN_STEP
			var footprint:=AABB(Vector3(x-Cargo.HALF_FOOTPRINT,0,z-Cargo.HALF_FOOTPRINT),Cargo.BOX_SIZE)
			if footprint.position.x<Cargo.WALKWAY_HALF_WIDTH and footprint.end.x>-Cargo.WALKWAY_HALF_WIDTH:continue
			var blocked:=false
			for station:Dictionary in deck.stations:
				var p:Vector3=station.position
				if cargo._point_box_distance(Vector2(p.x,p.z),footprint)<Cargo.STATION_CLEARANCE:blocked=true;break
				if station.has("patrol"):
					var end:Vector3=station.patrol
					if cargo._segment_box_distance(Vector2(p.x,p.z),Vector2(end.x,end.z),footprint)<Cargo.STATION_CLEARANCE:blocked=true;break
			if blocked:continue
			var min_y:=INF;var max_y:=-INF
			for offset:Vector2 in [Vector2.ZERO,Vector2(-.475,-.475),Vector2(-.475,.475),Vector2(.475,-.475),Vector2(.475,.475)]:
				var support:Dictionary=deck.sample(x+offset.x,z+offset.y)
				if support.is_empty() or support.normal.y<Cargo.MIN_NORMAL_Y or support.point.y<low-1e-5 or support.point.y>high+1e-5:blocked=true;break
				min_y=minf(min_y,support.point.y);max_y=maxf(max_y,support.point.y)
			if blocked or max_y-min_y>Cargo.MAX_HEIGHT_SPREAD:continue
			var bounds:=AABB(Vector3(x-.475,max_y+Cargo.SUPPORT_LIFT,z-.475),Cargo.BOX_SIZE)
			for obstacle:AABB in deck._obstacles:
				if bounds.intersects(obstacle.grow(Cargo.OBSTACLE_MARGIN)):blocked=true;break
			for other:Dictionary in selected:
				var other_bounds:=AABB(Vector3(other.position[0]-.475,other.position[1],other.position[2]-.475),Cargo.BOX_SIZE)
				if bounds.intersects(other_bounds):blocked=true;break
			if blocked:continue
			selected.append({"position":[x,max_y+Cargo.SUPPORT_LIFT,z]})
			if selected.size()==12:return selected
	return selected

func count_reason(counts:Dictionary,reason:String)->void:
	counts[reason]=int(counts.get(reason,0))+1

func read_crew_bounds(library)->Dictionary:
	var path:="res://assets/models/sailors/sailor-lod0.glb"
	var model:Node3D=library.instantiate_model(path)
	if model==null:return {"error":"original sailor unavailable"}
	root.add_child(model)
	var first:=true
	for mesh:MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh==null:continue
		var bounds:AABB=(model.global_transform.affine_inverse()*mesh.global_transform)*mesh.mesh.get_aabb()
		crew_bounds=bounds if first else crew_bounds.merge(bounds);first=false
	crew_ready=not first
	var radius:=0.0
	for index in 8:
		var p:Vector3=crew_bounds.get_endpoint(index);radius=maxf(radius,Vector2(p.x,p.z).length())
	var info:Dictionary={"path":path,"sha256":FileAccess.get_sha256(path),"mesh_bounds":box(crew_bounds),"rest_horizontal_radius":radius,"scope":"Actual imported original sailor mesh rest bounds. No animation sweep claimed."}
	model.free();return info

func classify_band(deck,cargo,low:float,high:float,step:float,stop_at_capacity:bool,profile:Dictionary={})->Dictionary:
	var selected:Array=[];var examples:Array=[];var counts:Dictionary={};var obstacle_counts:Dictionary={};var station_counts:Dictionary={}
	var size:Vector3=profile.get("box_size",Cargo.BOX_SIZE)
	var half_x:float=size.x*.5;var half_z:float=size.z*.5
	var clearance:float=profile.get("clearance",Cargo.STATION_CLEARANCE)
	var nx:=maxi(0,int(floor((deck.bounds.size.x-size.x)/step))+1)
	var nz:=maxi(0,int(floor((deck.bounds.size.z-size.z)/step))+1)
	var visited:=0
	for iz in nz:
		for ix in nx:
			visited+=1
			var x:float=deck.bounds.position.x+half_x+ix*step
			var z:float=deck.bounds.position.z+half_z+iz*step
			var center:Dictionary=deck.sample(x,z)
			if center.is_empty():count_reason(counts,"center_no_support");continue
			if center.normal.y<Cargo.MIN_NORMAL_Y:count_reason(counts,"center_slope");continue
			if center.point.y<low-1e-5 or center.point.y>high+1e-5:count_reason(counts,"center_other_height");continue
			var min_y:float=center.point.y;var max_y:float=center.point.y;var failure:=""
			for offset:Vector2 in [Vector2(-half_x,-half_z),Vector2(-half_x,half_z),Vector2(half_x,-half_z),Vector2(half_x,half_z)]:
				var support:Dictionary=deck.sample(x+offset.x,z+offset.y)
				if support.is_empty():failure="corner_no_support";break
				if support.normal.y<Cargo.MIN_NORMAL_Y:failure="corner_slope";break
				if support.point.y<low-1e-5 or support.point.y>high+1e-5:failure="corner_other_height";break
				min_y=minf(min_y,support.point.y);max_y=maxf(max_y,support.point.y)
			if not failure.is_empty():count_reason(counts,failure);continue
			if max_y-min_y>Cargo.MAX_HEIGHT_SPREAD:count_reason(counts,"height_spread");continue
			count_reason(counts,"five_point_support_valid")
			var bounds:=AABB(Vector3(x-half_x,max_y+Cargo.SUPPORT_LIFT,z-half_z),size)
			var walkway:bool=bounds.position.x<Cargo.WALKWAY_HALF_WIDTH and bounds.end.x>-Cargo.WALKWAY_HALF_WIDTH
			var stations:Array=[];var elevated_only:=true;var crew_intersections:Array=[]
			for index in deck.stations.size():
				var station:Dictionary=deck.stations[index];var p:Vector3=station.position
				var distance:float=cargo._point_box_distance(Vector2(p.x,p.z),bounds)
				if station.has("patrol"):
					var end:Vector3=station.patrol
					distance=minf(distance,cargo._segment_box_distance(Vector2(p.x,p.z),Vector2(end.x,end.z),bounds))
				if distance<clearance:
					var overlaps_height:bool=bounds.end.y>p.y+.02 and bounds.position.y<p.y+1.71
					elevated_only=elevated_only and not overlaps_height
					stations.append({"index":index,"distance":distance,"height_overlap":overlaps_height,"y":p.y})
					station_counts[str(index)]=int(station_counts.get(str(index),0))+1
				if crew_ready and not profile.is_empty():
					var basis:Basis=Basis(Quaternion(Vector3.UP,station.normal))*Basis(Vector3.UP,station.heading)
					var body:AABB=Transform3D(basis,p)*crew_bounds.grow(.05)
					if station.has("patrol"):body=body.merge(AABB(body.position+(station.patrol-p),body.size))
					if bounds.intersects(body):crew_intersections.append(index)
			var obstacles:Array=[]
			for index in deck._obstacles.size():
				if bounds.intersects(deck._obstacles[index].grow(Cargo.OBSTACLE_MARGIN)):
					obstacles.append(index);obstacle_counts[str(index)]=int(obstacle_counts.get(str(index),0))+1
			if walkway:count_reason(counts,"walkway")
			if not stations.is_empty():count_reason(counts,"station_or_patrol")
			if not stations.is_empty() and elevated_only:count_reason(counts,"station_different_deck_height_only")
			if not obstacles.is_empty():count_reason(counts,"obstacle")
			if not crew_intersections.is_empty():count_reason(counts,"original_crew_rest_mesh")
			if not walkway and not stations.is_empty() and obstacles.is_empty():count_reason(counts,"only_crew")
			if not walkway and stations.is_empty() and not obstacles.is_empty():count_reason(counts,"only_obstacles")
			if examples.size()<24 and not walkway:examples.append({"position":[x,max_y+Cargo.SUPPORT_LIFT,z],"stations":stations,"obstacles":obstacles,"crew_mesh_intersections":crew_intersections})
			if walkway or not stations.is_empty() or not obstacles.is_empty() or not crew_intersections.is_empty():continue
			count_reason(counts,"eligible_before_packing")
			var intersects:=false
			for other:Dictionary in selected:
				var other_bounds:=AABB(Vector3(other.position[0]-half_x,other.position[1],other.position[2]-half_z),size)
				if bounds.intersects(other_bounds):intersects=true;break
			if intersects:continue
			selected.append({"position":[x,max_y+Cargo.SUPPORT_LIFT,z]})
			if stop_at_capacity and selected.size()==12:return {"step":step,"visited":visited,"complete_scan":false,"counts":counts,"station_rejections":station_counts,"obstacle_rejections":obstacle_counts,"examples":examples,"safe_slots":selected}
	return {"step":step,"visited":visited,"complete_scan":true,"counts":counts,"station_rejections":station_counts,"obstacle_rejections":obstacle_counts,"examples":examples,"safe_slots":selected}
