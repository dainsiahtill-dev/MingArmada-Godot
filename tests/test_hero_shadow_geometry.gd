extends SceneTree
## A separate same-frame Mesh controls only stencil input, never visible detail.
const Adapter=preload("res://game/presentation/world/target_rigid_shadow_caster.gd")
const Hero=preload("res://modules/scene_engine/assets/hero_ship_provider.gd")
class Actor extends Node3D:
	var model:Node3D
	func get_model()->Node3D:return model
var assertions:=0
var failures:=0
func check(value:bool,detail:String)->void:
	assertions+=1
	if not value:failures+=1;printerr("FAIL hero shadow geometry: ",detail)
func _initialize()->void:run.call_deferred()
func as_array_mesh(source:PrimitiveMesh)->ArrayMesh:
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,source.get_mesh_arrays());return mesh
func closed_composite(geometry:Dictionary)->bool:
	var incidence:Dictionary={}
	for face:Dictionary in geometry.faces:
		for i in 3:
			var a:int=face.indices[i];var b:int=face.indices[(i+1)%3]
			var edge:=Vector2i(mini(a,b),maxi(a,b));incidence[edge]=int(incidence.get(edge,0))+1
	for count:int in incidence.values():
		if count<2 or count%2!=0:return false
	return not incidence.is_empty()
func run()->void:
	var actor:=Actor.new();root.add_child(actor);actor.model=Node3D.new();actor.add_child(actor.model)
	var full_detail:=as_array_mesh(SphereMesh.new())
	var visible:=MeshInstance3D.new();visible.name="hull";visible.mesh=full_detail;visible.position=Vector3(7,2,-4);visible.rotation.y=.4
	visible.set_meta("target_rigid_shadow_caster",true);actor.model.add_child(visible)
	var proxy:=as_array_mesh(BoxMesh.new());visible.set_meta("target_shadow_geometry",proxy)
	var adapter:=Adapter.new();var packet:Dictionary=adapter.compose({}, {"hero":actor},Vector3(.3,-.8,.5).normalized(),true,true)
	var caster:Dictionary=packet.native.sourceShadows.casters[0]
	check(caster.positions.size()==8,"uses the closed box resource instead of the visible sphere")
	check(caster.worldTransform==visible.global_transform,"retains actual visible component local-to-world frame")
	check(visible.visible and visible.mesh==full_detail,"full detail remains visible and unchanged")
	check(visible.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"stencil suppresses duplicate native shadow on the full detail node")
	adapter.compose({}, {"hero":actor},Vector3.DOWN,false,true)
	check(visible.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_ON,"native fallback restores full detail shadow policy")
	adapter.dispose();actor.free()
	for lod in 3:
		var model:Node3D=Hero.new("art_r6",true).instantiate_ship("fuchuan",lod);root.add_child(model)
		var count:=0;var triangles:=0
		for node:Node in model.find_children("*","MeshInstance3D",true,false):
			if node.get_meta("hero_shadow_resource",false):
				check(not node.visible,"proxy has no color/native draw: "+str(node.name))
				check(not node.get_meta("target_rigid_shadow_caster",false),"resource node cannot duplicate a caster")
			if not node.get_meta("target_rigid_shadow_caster",false):continue
			count+=1
			var geometry:Mesh=node.get_meta("target_shadow_geometry",null)
			check(geometry!=null,"authored geometry attached: "+str(node.name))
			if geometry==null:continue
			var prepared:Dictionary=adapter._mesh_geometry(geometry)
			triangles+=prepared.faces.size()
			check(closed_composite(prepared),"exact-welded composite has no open boundary: "+str(node.name))
			var bounded:=true
			for point:Array in prepared.positions:bounded=bounded and node.mesh.get_aabb().grow(.1).has_point(Vector3(point[0],point[1],point[2]))
			check(bounded,"projection geometry remains in visible component bounds: "+str(node.name))
		check(count==5 and triangles<3000,"five authored closed components stay below 3000 source triangles LOD"+str(lod))
		actor=Actor.new();root.add_child(actor);actor.model=model;model.reparent(actor)
		for light:Vector3 in [Vector3.UP,Vector3.DOWN,Vector3.LEFT,Vector3.RIGHT,Vector3.FORWARD,Vector3.BACK,Vector3(.35,-.8,.5).normalized(),Vector3(-.5,.8,.3).normalized()]:
			packet=adapter.compose({}, {"hero":actor},light,true,true)
			for part:Dictionary in packet.native.sourceShadows.casters:
				var volume:Dictionary=part.preparedRigid.build_volume(part.localLight)
				check(not volume.has("error") and int(volume.get("vertexCount",65535))<65535,"directional volume stays inside uint16 scope: "+part.id)
			check(adapter.diagnostics().errors.is_empty(),"all directional composites classify without error")
		adapter.dispose();actor.free()
	print("HERO_SHADOW_GEOMETRY_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
