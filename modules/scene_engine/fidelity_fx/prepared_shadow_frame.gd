extends RefCounted
## Main-thread publication certificate. No mutable input holder reaches the render thread.
## Only a live PreparedRigidShadow owner certifies its exact current immutable output.
const Prepared = preload("res://game/presentation/world/prepared_rigid_shadow.gd")
var _snapshot:Array=[]
func _init()->void:_snapshot.make_read_only()

static func _has_reference(value:Variant)->bool:
	if typeof(value) in [TYPE_OBJECT,TYPE_CALLABLE,TYPE_SIGNAL]:return true
	if value is Array:
		for item in value:
			if _has_reference(item):return true
	if value is Dictionary:
		for key in value:
			if _has_reference(key) or _has_reference(value[key]):return true
	return false

static func _frozen_copy(value:Variant)->Variant:
	if value is Array:
		var result:Array=[]
		for item in value:result.append(_frozen_copy(item))
		result.make_read_only();return result
	if value is Dictionary:
		var result:Dictionary={}
		for key in value:result[key]=_frozen_copy(value[key])
		result.make_read_only();return result
	return value

func configure(volumes:Array)->bool:
	var result:Array=[]
	for volume:Dictionary in volumes:
		var copied:Dictionary={}
		var owner:Variant=volume.get("preparedOwner")
		for key in volume:
			if key=="preparedOwner":continue
			if key=="geometry" and owner is Prepared and owner.owns_volume(volume.geometry):copied[key]=volume.geometry
			else:
				if _has_reference(key) or _has_reference(volume[key]):return false
				copied[key]=_frozen_copy(volume[key])
		copied.make_read_only();result.append(copied)
	result.make_read_only();_snapshot=result
	return true

func snapshot()->Array:return _snapshot
