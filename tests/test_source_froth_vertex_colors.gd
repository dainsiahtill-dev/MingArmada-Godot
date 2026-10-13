extends SceneTree
## Real NIF -> compiled controller state -> production SourceFroth -> ARRAY_COLOR.
const Froth=preload("res://modules/scene_engine/water/source_froth.gd")
const Compiler=preload("res://modules/scene_engine/fidelity_fx/cloud_render_compiler.gd")
var assertions:=0
var failures:=0

func check(ok:bool,message:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: ",message)
func _initialize()->void:_run.call_deferred()
func _water(_x:float,_z:float,_time:float)->float:return 0.0

func _mesh_colors(froth:RefCounted,prefix:String)->PackedColorArray:
	for node:Node in froth.get("_container").get_children():
		if node is MeshInstance3D and str(node.name).begins_with(prefix):
			return node.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	return PackedColorArray()

func _original_colors(asset:Dictionary)->Array:
	for block:Dictionary in asset.blocks:
		if str(block.type) in ["NiTriShapeData","NiTriStripsData"]:return block.fields.vertex_colors
	return []

func _render(froth:RefCounted,time:float)->void:
	froth.apply_snapshot({"sourcePosition":[0,0,0],"sourceBowPosition":[0,0,0],"modelScale":1.0,"sourceToWorld":0.02,"controllerAppTime":time,"enabled":true},time,_water,Callable())

func _assert_original(colors:PackedColorArray,expected:Array,alpha:float,label:String)->void:
	check(colors.size()==expected.size(),label+" retains full authored color array")
	if colors.size()!=expected.size():return
	var transparent:=0
	for i in expected.size():
		var original:Dictionary=expected[i]
		if float(original.a)==0.0:transparent+=1
		check(absf(colors[i].a-float(original.a)*alpha)<=1.0/255.0+0.00001,label+" authored alpha reaches mesh vertex "+str(i))
		check(absf(colors[i].r-float(original.r))<=1.0/255.0+0.00001,label+" source ambient/diffuse replaces material RGB at vertex "+str(i))
	check(transparent>0,label+" fixture contains transparent borders, not only opaque vertices")

func _run()->void:
	var parent:=Node3D.new();root.add_child(parent)
	var compiler:=Compiler.new()
	for family in Froth.FAMILIES.size():
		var asset:Dictionary=Froth.asset("fx_ship_sidefroth_"+Froth.FAMILIES[family]+".nif")
		var graph:Dictionary=compiler.compile_asset(asset)
		var state:Dictionary=compiler.render_states(graph,0.0,{},true,{},true)[0]
		check(state.get("vertexMode",-1)==2 and state.get("lightingMode",-1)==1,"actual sidefroth leaf overrides root ignore property: "+Froth.FAMILIES[family])
		check(state.get("authoredVertexColors",[]).size()==150,"compiler retains original 150 authored RGBA values: "+Froth.FAMILIES[family])
		var froth:=Froth.new();check(froth.configure(parent,family,1).ok,"configure original source family")
		_render(froth,0.0)
		_assert_original(_mesh_colors(froth,"side_"),_original_colors(asset),1.0,Froth.FAMILIES[family])
		_assert_original(_mesh_colors(froth,"bow_"),_original_colors(Froth.asset("fx_ship_bowfroth.nif")),1.0,"bow")
		froth.dispose()
	# Reuse the real sloop topology, texture and source UV controller. Only the
	# NIF property under test changes; no renderer mocks or white quad fixtures.
	var source:Dictionary=Froth.asset("fx_ship_sidefroth_sloop.nif")
	var froth:=Froth.new();froth.configure(parent,0,1)
	for mode in [0,1,2]:
		var asset:Dictionary=source.duplicate(true)
		for block:Dictionary in asset.blocks:
			if int(block.id)==6:block.fields.vertex_mode=mode;block.fields.lighting_mode=0 if mode==2 else 1
			if int(block.id)==5:block.fields.alpha=0.4
		froth.set("_side",compiler.compile_asset(asset));_render(froth,0.1+mode*0.1)
		var colors:=_mesh_colors(froth,"side_")
		check(colors.size()==150,"alternate property retains real source topology")
		if colors.size()!=150:continue
		for color:Color in colors:check(absf(color.a-0.4)<=1.0/255.0+0.00001,"ignore/emissive source modes preserve material alpha instead of enabling diffuse vertex alpha")
		if mode==0:check(absf(colors[0].r-0.4941176772)<0.005,"ignore mode retains source diffuse RGB")
		elif mode==1:check(colors[0].r==0.0 and colors[1].r>0.5,"emissive mode selects authored emission RGB without diffuse alpha")
		else:check(absf(colors[0].r-0.1568627506)<0.005,"emissive lighting selects material emission instead of diffuse vertex color")
	var controlled:Dictionary=source.duplicate(true)
	for block:Dictionary in controlled.blocks:
		if int(block.id)==5:block.fields.alpha=0.4;block.fields.controller={"ref":100,"type":"NiAlphaController"}
	controlled.blocks.append({"id":100,"type":"NiAlphaController","fields":{"flags":8,"frequency":1.0,"phase":0.0,"start_time":0.0,"stop_time":1.0,"next_controller":null,"data":{"ref":101,"type":"NiFloatData"}}})
	controlled.blocks.append({"id":101,"type":"NiFloatData","fields":{"data":{"interpolation":1,"keys":[{"time":0.0,"value":0.8},{"time":1.0,"value":0.2}]}}})
	froth.set("_side",compiler.compile_asset(controlled));_render(froth,0.5)
	_assert_original(_mesh_colors(froth,"side_"),_original_colors(source),0.5,"controlled alpha")
	froth.dispose();parent.free()
	print("SOURCE_FROTH_VERTEX_COLORS_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
