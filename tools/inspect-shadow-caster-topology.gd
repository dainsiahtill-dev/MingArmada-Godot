extends "res://tools/diagnose-voyage-ship-line.gd"
## Read-only CPU geometry capture of the actual GPU-isolated culprit.
const CASTER_ID="player:native_hull_56_component_03"
func vector(p:Vector3)->Array:return [p.x,p.y,p.z]
func matrix(t:Transform3D)->Array:return [vector(t.basis.x),vector(t.basis.y),vector(t.basis.z),vector(t.origin)]
func run()->void:
	output="res://Temp/research/shadow-caster-topology.json"
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	root.size=Vector2i(1600,1000);root.content_scale_size=root.size
	var main:Node=Main.instantiate();root.add_child(main);await frames(4)
	main.menu.find_child("fidelity-island",true,false).pressed.emit()
	for wait in 150:
		await process_frame
		if is_instance_valid(main.current_scene):break
	var scene:Control=main.current_scene
	if not is_instance_valid(scene) or not scene.startup_receipt.ok:printerr("FAIL actual shared world unavailable");quit(1);return
	scene.set_process(false);scene.paused=true;scene.seconds=24.0;scene._render();await frames(4)
	var sea:Node3D=scene.sea
	var volume:Dictionary=sea.source_shadows._volumes[CASTER_ID]
	var mesh:MeshInstance3D=sea.ships.player.get_model().find_child(CASTER_ID.get_slice(":",1),true,false)
	var source:Dictionary=sea._rigid_casters._mesh_geometry(mesh.mesh)
	var part:Dictionary=sea._rigid_casters._parts[CASTER_ID]
	var light:=Vector3(part.light[0],part.light[1],part.light[2])
	var faces:Array=[];var edge_faces:Dictionary={};var degrees:Dictionary={};var screen:Array=[]
	for i in source.faces.size():
		var face:Dictionary=source.faces[i];var dot:float=face.normal.dot(light)
		faces.append({"index":i,"indices":face.indices,"normal":vector(face.normal),"dotLight":dot,"selected":dot<0})
		for side in 3:
			var a:int=face.indices[side];var b:int=face.indices[(side+1)%3];var key:="%s:%s"%[mini(a,b),maxi(a,b)]
			if not edge_faces.has(key):edge_faces[key]=[]
			edge_faces[key].append({"face":i,"a":a,"b":b,"selected":dot<0})
	for edge:Array in part.edges:
		degrees[edge[0]]=degrees.get(edge[0],0)+1;degrees[edge[1]]=degrees.get(edge[1],0)-1
	for p:Array in source.positions:
		var world:Vector3=mesh.global_transform*Vector3(p[0],p[1],p[2]);var uv:Vector2=scene.camera.unproject_position(world)
		screen.append([uv.x,uv.y])
	var apex:Array=volume.geometry.positions[0]
	var apex_world:Vector3=mesh.global_transform*Vector3(apex[0],apex[1],apex[2]);var apex_screen:Vector2=scene.camera.unproject_position(apex_world)
	var projection:Projection=scene.camera.get_camera_projection()
	var pcols:Array=[]
	for column in 4:pcols.append([projection[column].x,projection[column].y,projection[column].z,projection[column].w])
	var metadata:Dictionary={}
	for key in mesh.get_meta_list():metadata[key]=mesh.get_meta(key)
	var proof:={"caster":CASTER_ID,"scope":"Headless read-only extraction; same real Main/fidelity-island at24s. Projection is Camera3D CPU projection, not claimed actual GPU rasterization.","camera":matrix(scene.camera.global_transform),"projectionColumns":pcols,"viewport":[scene.view.size.x,scene.view.size.y],"meshTransform":matrix(mesh.global_transform),"modelFamily":sea.ships.player.get_model().get_meta("source_family"),"meshMetadata":metadata,"localLight":part.light,"positions":source.positions,"faces":faces,"selectedEdges":part.edges,"selectedCaps":part.caps,"edgeFaces":edge_faces,"edgeVertexDirectedBalance":degrees,"screenPositions":screen,"apexScreen":[apex_screen.x,apex_screen.y],"volume":volume.geometry,"sourceHashes":{}}
	for path:String in ["res://game/presentation/world/target_rigid_shadow_caster.gd","res://modules/scene_engine/fidelity_fx/source_shadow_math.gd","res://tools/inspect-shadow-caster-topology.gd"]:proof.sourceHashes[path]=FileAccess.get_sha256(path)
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(proof,"\t"));file.close()
	print("SHADOW_CASTER_TOPOLOGY vertices=",source.positions.size()," faces=",faces.size()," edges=",part.edges.size()," apexScreen=",apex_screen," output=",output)
	main.free();await frames(3);quit(0)
