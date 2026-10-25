extends "res://modules/scene_engine/fidelity_fx/cloud_render_compiler.gd"
## Research bridge for Atmosphere's inferred production-compiler property type.
## The injected adapter is type-compatible; actual work belongs to its delegate.
var _implementation:RefCounted
func _init(implementation:RefCounted)->void:_implementation=implementation
func implementation()->RefCounted:return _implementation
func use_implementation(value:RefCounted)->bool:
	var changed:bool=value!=_implementation
	_implementation=value
	return changed
func compile_asset(asset:Dictionary)->Dictionary:return _implementation.compile_asset(asset)
func bind_sequence(asset:Dictionary,sequence:Dictionary)->Dictionary:return _implementation.bind_sequence(asset,sequence)
func controller_snapshot(compiled:Dictionary)->Array:return _implementation.controller_snapshot(compiled)
func restore_controllers(compiled:Dictionary,snapshot:Array)->bool:return _implementation.restore_controllers(compiled,snapshot)
func _transform_vector(matrix:Array,vector:Array)->Array:return _implementation._transform_vector(matrix,vector)
func render_minimum_states(compiled:Dictionary,outer:Dictionary,camera:Dictionary)->Array:return _implementation.render_minimum_states(compiled,outer,camera)
func render_states(compiled:Dictionary,time:float=0.0,outer:Dictionary={},animate:bool=false,camera:Dictionary={},include_vertices:bool=false,minimum_z:bool=false,persistent:bool=false)->Array:
	return _implementation.render_states(compiled,time,outer,animate,camera,include_vertices,minimum_z,persistent)
