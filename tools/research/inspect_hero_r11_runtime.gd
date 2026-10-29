extends SceneTree
## Read actual R9b imported canvas COLOR_0 and runtime damage shader bindings.
const Provider=preload("res://game/research/fixtures/hero_palette_provider.gd")
const Damage=preload("res://game/presentation/ships/ship_damage.gd")
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func run()->void:
	var output:=""
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):output=argument.trim_prefix("--output=")
	if output.is_empty() or FileAccess.file_exists(output):printerr("fresh output required");quit(1);return
	var rows:Array=[]
	var provider:=Provider.new("art_r6",true,"r9b")
	for lod in range(3):
		var model:Node3D=provider.instantiate_ship("fuchuan",lod)
		if model==null:failures.append("LOD%d failed to load"%lod);continue
		var damage=Damage.new();damage.configure([model])
		for index in range(3):
			var sail:=model.find_child("sail_%d"%index,true,false) as MeshInstance3D
			if sail==null:failures.append("missing sail%d"%index);continue
			var found:=false
			for surface in sail.mesh.get_surface_count():
				var original=sail.mesh.surface_get_material(surface)
				if not original is StandardMaterial3D or original.resource_name!="canvas":continue
				found=true
				var colors:PackedColorArray=sail.mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]
				var current=sail.get_active_material(surface)
				var active:bool=current is ShaderMaterial and current.get_shader_parameter("use_original_vertex_color")==true
				var low:=Vector3(INF,INF,INF);var high:=Vector3(-INF,-INF,-INF)
				for color:Color in colors:
					low=low.min(Vector3(color.r,color.g,color.b));high=high.max(Vector3(color.r,color.g,color.b))
				if not original.vertex_color_use_as_albedo or not active or colors.is_empty():failures.append("canvas color not consumed LOD%d sail%d"%[lod,index])
				rows.append({"lod":lod,"sail":index,"count":colors.size(),"minimum":str(low),"maximum":str(high),"materialVertexColorEnabled":original.vertex_color_use_as_albedo,"damageShaderVertexColorEnabled":active})
			if not found:failures.append("canvas missing LOD%d sail%d"%[lod,index])
		damage.dispose();model.free()
	var report={"scope":"headless actual R9b imported material/color and damage shader bindings, no visual/GPU claim","rows":rows,"failures":failures}
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if not file:printerr("report open failed");quit(1);return
	file.store_string(JSON.stringify(report,"\t"));file.close()
	print("R11_RUNTIME_COLOR rows=",rows.size()," failures=",failures.size())
	for error:String in failures:printerr("FAIL: ",error)
	quit(1 if not failures.is_empty() else 0)
