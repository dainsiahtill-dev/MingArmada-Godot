extends "res://game/research/fixtures/cloud_billboard_baseline.gd"
## Independent candidate: memo lives only within one static minimum invocation.
## Keep exact matrix bytes, original arithmetic, and independent result arrays.
var _minimum_scope:=false
var _billboard_values:Dictionary={}

func render_minimum_states(compiled:Dictionary,outer:Dictionary,camera:Dictionary)->Array:
	var previous_scope:=_minimum_scope
	var previous_values:=_billboard_values
	_minimum_scope=true;_billboard_values={}
	var states:Array=super.render_minimum_states(compiled,outer,camera)
	_minimum_scope=previous_scope;_billboard_values=previous_values
	return states

func _billboard_mode0(rotation:Array,camera:Dictionary)->Array:
	if not _minimum_scope:return super._billboard_mode0(rotation,camera)
	# No numeric equality or hash-only shortcut: PackedByteArray keys compare
	# all nine double stores and preserve signed zero before original math.
	var key:=PackedFloat64Array(rotation).to_byte_array()
	if _billboard_values.has(key):
		var cached:Array=_billboard_values[key]
		return cached.duplicate()
	var value:Array=super._billboard_mode0(rotation,camera)
	_billboard_values[key]=value.duplicate()
	return value
