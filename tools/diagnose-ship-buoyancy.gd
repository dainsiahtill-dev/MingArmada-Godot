extends SceneTree
const Body=preload("res://modules/physics_engine/ships/ship_dynamics.gd")
const Coastal=preload("res://modules/physics_engine/ocean/coastal_wave_field.gd")
const Ship=preload("res://game/presentation/ships/ship_view.gd")
const Profile=preload("res://game/presentation/ships/hull_waterline_profile.gd")
const Types=preload("res://modules/contracts/physics_types.gd")
const Height=preload("res://modules/scene_engine/terrain/height_field.gd")
const Catalog=preload("res://game/domain/legacy/catalog.gd")
const Geography=preload("res://game/scenes/common/reference_geography.gd")
var coast:=false
var output:="res://Temp/buoyancy-baseline.json"
func _initialize()->void:run.call_deferred()
func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg=="--coast":coast=true
	var field:=Height.new();field.configure_ports(Catalog.DATA.PORTS,false,Geography.options())
	var records:Array=[]
	for kind:String in Types.SHIP_SPECS:
		if coast and kind!="fuchuan":continue
		var actor:=Ship.new();root.add_child(actor);actor.configure(kind)
		var points:Array[Vector3]=[]
		var model:Node3D=actor.get_model()
		for node:Node in model.find_children("*","MeshInstance3D",true,false):
			if str(node.get_meta("damage_surface",""))!="hull":continue
			var frame:Transform3D=model.transform*Profile._relative_transform(node,model)
			for surface in node.mesh.get_surface_count():
				for local:Vector3 in node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
					points.append(frame*local)
		# Each longitudinal bin keeps the actual lowest hull vertex.
		var loz:=INF;var hiz:=-INF;var low:=INF
		for p:Vector3 in points:loz=minf(loz,p.z);hiz=maxf(hiz,p.z);low=minf(low,p.y)
		var keel:Dictionary={}
		for p:Vector3 in points:
			var bin:=clampi(int((p.z-loz)/(hiz-loz)*24),0,23)
			if not keel.has(bin) or p.y<keel[bin].y:keel[bin]=p
		for depth:float in ([-350,-340,-330,-320,-310,-300,-290,-280] if coast else [3.0,20.0]):
			var ground:=func(_x:float,_z:float)->float:return -depth
			if coast:ground=field.sample_height
			var waves:=Coastal.new();waves.configure(ground)
			var body:=Body.new();body.configure({"kind":kind,"position":{"x":depth if coast else -160.0,"z":-10.0 if coast else -60.0},"heading":0.45,"sailDeployment":0.0},ground,waves)
			var row:={"kind":kind,"depth":depth,"actualKeelY":low,"draft":Types.ship_spec(kind).draft,"maxOriginAboveSea":-INF,"maxLowestKeelClearance":-INF,"airFrames":0,"worst":{}}
			for tick in 7200:
				var s:Dictionary=body.step_buoyancy(1.0/60.0)
				if tick%6!=0:continue
				var b:=Basis.from_euler(Vector3(-s.pitch,PI/2-s.heading,s.heel),EULER_ORDER_YXZ)
				var origin:=Vector3(s.position.x,s.position.y,s.position.z)
				var clearance:=INF
				for p:Vector3 in keel.values():
					var wp:Vector3=origin+b*p
					clearance=minf(clearance,wp.y-waves.sample_height(wp.x,wp.z,s.time))
				row.maxOriginAboveSea=maxf(row.maxOriginAboveSea,s.position.y-waves.sample_height(s.position.x,s.position.z,s.time))
				if clearance>0:row.airFrames+=1
				if clearance>row.maxLowestKeelClearance:row.maxLowestKeelClearance=clearance;row.worst=s
			records.append(row)
			print("BUOYANCY_SCAN ",JSON.stringify(row))
		actor.dispose();actor.free()
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify({"sources":{"dynamics":FileAccess.get_sha256("res://modules/physics_engine/ships/ship_dynamics.gd")},"records":records},"\t"));file.close()
	print("BUOYANCY_DIAGNOSTIC_DONE");quit()
