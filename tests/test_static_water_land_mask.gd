extends SceneTree
const World=preload("res://modules/scene_engine/world/world_view.gd")
const Height=preload("res://modules/scene_engine/terrain/height_field.gd")
const Geography=preload("res://game/scenes/common/reference_geography.gd")
func _initialize()->void: _run.call_deferred()
func _run()->void:
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/reference/mingqi-geography.json"))
	var heights:=Height.new(); heights.configure_ports(fixture.ports,true,Geography.source_options())
	var camera:=Camera3D.new(); root.add_child(camera); camera.position=Vector3(0,150,-250); camera.look_at(Vector3.ZERO)
	var world:=World.new(); root.add_child(world)
	var ready:bool=world.configure(heights.sample_height,[],{"camera":camera,"ports":fixture.ports,"vegetation":false,"island_details":false,"static_shore_resolution":128})
	var enabled:bool=ready and world.get_ocean().material_override.get_shader_parameter("mask_dry_terrain")==true
	world.dispose(); world.free(); camera.free()
	print("STATIC_WATER_LAND_MASK_TESTS assertions=1 failures=",0 if enabled else 1)
	quit(0 if enabled else 1)
