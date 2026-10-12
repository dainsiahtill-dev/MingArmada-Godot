extends SceneTree
const Height=preload("res://modules/scene_engine/terrain/height_field.gd")
const Mingqi=preload("res://game/runtime/mingqi_runtime.gd")
const Practice=preload("res://game/runtime/naval_practice_runtime.gd")
const Catalog=preload("res://game/domain/legacy/catalog.gd")
const Layout=preload("res://game/scenes/common/reference_geography.gd")
var assertions:=0
var failures:=0
func check(value: bool,detail: String) -> void:
	assertions+=1
	if not value: failures+=1; printerr("FAIL: ",detail)
func check_fleet(height: RefCounted,native: Dictionary,label: String) -> void:
	for ship: Dictionary in native.ships:
		if ship.hull<=0: continue
		var x:=float(ship.visual.position.x); var z:=float(ship.visual.position.z)
		var ground:=float(height.sample_height(x,z))
		check(ground<0.0,"healthy "+label+" vessel "+ship.id+" starts in actual reference water; ground="+str(ground))
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var ports: Array=JSON.parse_string(FileAccess.get_file_as_string("res://game/data/mingqi_geography.json"))
	var height:=Height.new()
	check(height.configure_ports(ports,true,Layout.source_options()),"explicit source comparison geography enables original profiles")
	check(height.reference_profiles().size()==ports.size(),"all campaign islands use actual reference indices")
	check(height.reference_profiles()[0].id=="coastal2" and height.reference_profiles()[1].id=="cat_island","harbor town uses broad bay and outpost uses narrow ridge")
	var before: Array=height.reference_profiles()
	check(not height.configure_ports(ports,true,{"reference_islands":true,"reference_profiles":{"xiamen":"missing"}}) and height.reference_profiles()==before,"invalid art layout cannot replace accepted world geometry")
	var runtime:=Mingqi.new()
	check(runtime.configure(height.sample_height).get("ok",false),"campaign authority accepts reference world")
	check_fleet(height,runtime.snapshot().naval,"campaign")
	runtime.dispose()
	var training:=Height.new()
	check(training.configure_ports(Catalog.DATA.PORTS,false,Layout.source_options()),"all practice/legacy ports use reference geography")
	for mode: String in ["sail","duel","fleet"]:
		var practice:=Practice.new()
		check(practice.configure(training.sample_height,{"mode":mode}).get("ok",false),"real "+mode+" authority starts")
		check_fleet(training,practice.snapshot().naval,mode)
		practice.dispose()
	print("REFERENCE_FORMAL_GEOGRAPHY_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
