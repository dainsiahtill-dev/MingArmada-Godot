extends "res://modules/scene_engine/assets/hero_ship_provider.gd"
## Explicit research candidate redirected from the preserved R6 comparison path.
const OwnedLibrary=preload("res://modules/scene_engine/assets/asset_library.gd")
var _palette_variant:="r7c"
var _source_compatible:=false
func _init(source_variant:String="art_r6",authored_shadows:bool=true,palette_variant:String="r7c")->void:
	super(source_variant,authored_shadows)
	_palette_variant=palette_variant
	_source_compatible=source_variant=="art_r6"
class RedirectLibrary extends RefCounted:
	var delegate:RefCounted
	var variant:String
	func _init(owner:RefCounted,palette_variant:String)->void:delegate=owner;variant=palette_variant
	func instantiate_model(path:String)->Node3D:
		return delegate.instantiate_model(path.replace("/hero_fuchuan_v3_r6/","/hero_fuchuan_v3_%s/"%variant))
func instantiate_ship(kind:String,lod:int,library:RefCounted=null)->Node3D:
	if kind!="fuchuan" or lod not in [0,1,2]:return super.instantiate_ship(kind,lod,library)
	if not _source_compatible or _palette_variant not in ["r7a","r7b","r7c","r8b","r9","r9b","r11","r11b","r12","r13","r14b"]:return null
	var owner:RefCounted=library if library!=null else OwnedLibrary.new()
	var model:Node3D=super.instantiate_ship(kind,lod,RedirectLibrary.new(owner,_palette_variant))
	if library==null:owner.dispose()
	if model!=null:
		model.set_meta("source_path","res://assets/models/hero_fuchuan_v3_%s/fuchuan-lod%d.glb"%[_palette_variant,lod])
		model.set_meta("art_revision",14 if _palette_variant=="r14b" else 13 if _palette_variant=="r13" else 12 if _palette_variant=="r12" else 11 if _palette_variant in ["r11","r11b"] else 9 if _palette_variant in ["r9","r9b"] else 8 if _palette_variant=="r8b" else 7)
		model.set_meta("texture_style","imagegen_weathered_cinnabar_sail_r13" if _palette_variant=="r13" else "imagegen_sunwashed_palette_r7c" if _palette_variant in ["r12","r14b"] else "imagegen_sunfaded_cinnabar_sail_r11b_weathered" if _palette_variant=="r11b" else "imagegen_sunfaded_cinnabar_sail_r11_weathered" if _palette_variant=="r11" else "imagegen_sunfaded_cinnabar_sail_r9b" if _palette_variant=="r9b" else "imagegen_cinnabar_sail_r9" if _palette_variant=="r9" else "imagegen_sunwashed_palette_"+_palette_variant)
	return model
