extends SceneTree
## Actual owner cold initialization, no fire/hit/active SourceFx or time advance.
const Fx = preload("res://modules/scene_engine/fidelity_fx/presentation.gd")
const Effects = preload("res://game/presentation/combat/combat_effects.gd")
const Waves = preload("res://modules/physics_engine/ocean/coastal_wave_field.gd")
const SOURCES := ["fx_cannon_fire_01.nif","cannon_ball_splash_01.nif","cannon_ball_splash_02.nif","cannon_ball_splash_03.nif"]
const DDS := ["fx_cannon_smoke_01.dds","fx_cannon_smoke_02.dds","fx_cannon_smoke_03.dds","fx_mist_01.dds","fx_streakin_001.dds","fx_water_splash_004.dds","fx_water_splash_rings_01.dds"]
const CACHES := ["_prepared_sources","_assets","_textures"]
var assertions := 0
var failures := 0
var _script: Script
func check(ok: bool,detail: String) -> bool:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL FX prewarm: ",detail)
	return ok
func _initialize() -> void: _run.call_deferred()
func _height(_x: float,_z: float) -> float: return -80.0
func _cache(key: String) -> Dictionary:
	var value: Variant = _script.get(key)
	return value if value is Dictionary else {}
func _owner(waves: RefCounted) -> Node3D:
	var effects := Effects.new(); root.add_child(effects); effects.set_water_sampler(waves.sample_height)
	var d: Dictionary = effects.diagnostics()
	check([d.source_fire,d.splashes,d.events,d.projectiles,d.puffs] == [0,0,0,0,0] and effects.get("_time") == 0.0,"prewarm creates no living source/event and accepts no time")
	check(effects.get_child_count() == 1 and effects.get_node("WaterSplashes").get_child_count() == 0,"only the existing empty water owner is added, no active SourceFx nodes")
	return effects
func _prepared() -> void:
	var cache := _cache("_prepared_sources")
	check(cache.size() == 4 and SOURCES.all(func(source: String): return cache.has(source)),"actual owner initialization prepares all four original source assets")
	check(_cache("_textures").size() == 7 and DDS.all(func(name: String): return _cache("_textures").has(name)),"actual owner initialization uploads seven original NiSourceTexture DDS dependencies")
	for template: RefCounted in cache.values():
		check(template.get("_canonical") == null and template.get("_native") == null and template.get("_replay") == null,"prepared templates contain no canonical/native pool, fork or birth update")
func _images() -> void:
	var manifest: Dictionary = Fx.load_manifest()
	for entry: Dictionary in manifest.textures:
		if String(entry.name).to_lower() not in DDS or not _cache("_textures").has(String(entry.name).to_lower()): continue
		var texture: Texture2D = _cache("_textures")[String(entry.name).to_lower()]
		var image: Image = texture.get_image()
		check(image != null and image.get_width() == int(entry.width) and image.get_height() == int(entry.height) and image.has_mipmaps() == bool(entry.mipmaps),"actual prewarmed DDS dimensions and authored mip flags match manifest")
		if image != null: check(image.get_format() == Image.FORMAT_DXT5 and image.get_data() == FileAccess.get_file_as_bytes(String(entry.compressedMipPath)),"all original BC3 pixels/mip bytes stay unchanged during prewarm")
func _run() -> void:
	_script = load("res://modules/scene_engine/fidelity_fx/presentation.gd")
	var saved: Dictionary = {}
	for key: String in CACHES: saved[key] = _script.get(key); _script.set(key,{})
	var waves := Waves.new(); waves.configure(_height)
	var first := _owner(waves); _prepared()
	var report: Dictionary = first.diagnostics().get("sourcePrewarm",{})
	check(report.get("ok",false) and report.get("sources",[]).size() == 4 and report.get("textures",[]).size() == 7 and report.get("errors",[]).is_empty(),"actual owner exposes a successful deep-owned prewarm receipt")
	var templates := _cache("_prepared_sources").duplicate(); var textures := _cache("_textures").duplicate()
	var second := _owner(waves)
	for source: String in SOURCES:
		if templates.has(source): check(is_same(templates[source],_cache("_prepared_sources").get(source)),"second actual owner reuses the identical prepared template")
	for name: String in DDS:
		if textures.has(name): check(is_same(textures[name],_cache("_textures").get(name)),"second actual owner reuses the identical original texture")
	if not report.get("sources",[]).is_empty(): report.sources[0] = "caller-mutated"
	if not report.get("textures",[]).is_empty(): report.textures[0] = "caller-mutated"
	check(not first.diagnostics().get("sourcePrewarm",{}).get("sources",[]).has("caller-mutated") and not first.diagnostics().get("sourcePrewarm",{}).get("textures",[]).has("caller-mutated"),"caller receipt mutation cannot corrupt owner prewarm state")
	var ready := check(_script.has_method("prewarm_game_sources"),"actual SourceFx static prewarm API exists")
	if ready:
		var direct: Dictionary = _script.call("prewarm_game_sources")
		check(direct.get("ok",false) and direct.get("errors",[]).is_empty(),"actual direct prewarm API reports success")
		_images()
		for key: String in CACHES: _script.set(key,{})
		Fx._assets[SOURCES[0]] = {"name":SOURCES[0],"blocks":[],"roots":[]}
		var failed: Dictionary = _script.call("prewarm_game_sources")
		check(not failed.get("ok",true) and not failed.get("errors",[]).is_empty() and not _cache("_prepared_sources").has(SOURCES[0]),"actual damaged source reports failed preparation without caching a bad template")
		for key: String in CACHES: _script.set(key,{})
		var retried: Dictionary = _script.call("prewarm_game_sources")
		check(retried.get("ok",false),"real repaired source retries successfully after failed preparation")
	first.dispose(); second.dispose(); first.free(); second.free()
	for key: String in CACHES: _script.set(key,saved[key])
	print("FIDELITY_FX_PREWARM_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
