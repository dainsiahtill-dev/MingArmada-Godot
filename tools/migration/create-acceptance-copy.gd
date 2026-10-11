extends SceneTree
## Preparation only: byte-identical release EXE/PCK plus external Node driver.
## Editor --headless --path <repo> --script tools/migration/create-acceptance-copy.gd
## -- --exe=<absolute.exe> --pack=<absolute.pck> --driver=<absolute.gd> --out=<new absolute directory>
## Launch the resulting EXE normally. Release templates do not need --script.
var failures: Array[String] = []
func _initialize() -> void:
	var arguments := {}
	for argument in OS.get_cmdline_user_args():
		var equal := argument.find("=")
		if argument.begins_with("--") and equal > 2: arguments[argument.substr(2,equal-2)] = argument.substr(equal+1).replace("\\","/").simplify_path()
	for key in ["exe","pack","driver","out"]:
		if not arguments.has(key) or not String(arguments[key]).is_absolute_path(): fail("required absolute argument --"+key); return
	var exe: String = arguments.exe; var pack: String = arguments.pack
	var driver: String = arguments.driver; var output: String = arguments.out
	for source in [exe,pack,driver]:
		if not FileAccess.file_exists(source): fail("source missing: "+source); return
	if exe.get_extension().to_lower() != "exe" or pack.get_extension().to_lower() != "pck": fail("expected release EXE and sidecar PCK"); return
	if output.to_lower() == exe.get_base_dir().to_lower() or output.to_lower() == pack.get_base_dir().to_lower(): fail("acceptance copy must have a separate directory"); return
	if DirAccess.dir_exists_absolute(output): fail("refusing to overwrite an existing acceptance directory"); return
	var driver_text := FileAccess.get_file_as_string(driver)
	if not driver_text.strip_edges().begins_with("extends Node\n") and not driver_text.strip_edges().begins_with("extends Node\r\n"):
		fail("verification driver must extend Node, not SceneTree"); return
	var before_exe := FileAccess.get_sha256(exe); var before_pack := FileAccess.get_sha256(pack)
	if DirAccess.make_dir_recursive_absolute(output) != OK: fail("cannot create acceptance directory"); return
	var copied_exe := output.path_join(exe.get_file())
	var copied_pack := output.path_join(exe.get_file().get_basename()+".pck")
	var copied_driver := output.path_join("acceptance-driver.gd")
	for pair in [[exe,copied_exe],[pack,copied_pack],[driver,copied_driver]]:
		if DirAccess.copy_absolute(pair[0],pair[1]) != OK: fail("copy failed: "+pair[0]); return
	var scene_path := output.path_join("acceptance-driver.tscn")
	var scene_text := "[gd_scene load_steps=2 format=3]\n\n[ext_resource type=\"Script\" path=%s id=\"1\"]\n\n[node name=\"ReleaseAcceptanceDriver\" type=\"Node\"]\nscript = ExtResource(\"1\")\n" % JSON.stringify(copied_driver)
	if not write_file(scene_path,scene_text): return
	var override_text := "[application]\nrun/main_scene=%s\n" % JSON.stringify(scene_path)
	if not write_file(output.path_join("override.cfg"),override_text): return
	for directory in ["empty-cwd","roaming","local","evidence"]:
		if DirAccess.make_dir_recursive_absolute(output.path_join(directory)) != OK: fail("cannot create isolated verification directory: "+directory); return
	var exe_hash := FileAccess.get_sha256(copied_exe); var pack_hash := FileAccess.get_sha256(copied_pack)
	var sources_unchanged := FileAccess.get_sha256(exe) == before_exe and FileAccess.get_sha256(pack) == before_pack
	var identical := exe_hash == before_exe and pack_hash == before_pack
	var receipt := {
		"status":"PASS" if sources_unchanged and identical else "FAIL",
		"scope":"verification driver: byte-identical release EXE/PCK copy, external Node scene and EXE-adjacent override.cfg; production entrypoint and production files unchanged",
		"preparationEngine":Engine.get_version_info().string,
		"releaseExecuted":false,
		"launchDirectories":{"cwd":output.path_join("empty-cwd"),"APPDATA":output.path_join("roaming"),"LOCALAPPDATA":output.path_join("local"),"evidence":output.path_join("evidence")},
		"production":{"exe":exe,"pack":pack,"exeSha256":before_exe,"packSha256":before_pack,"sourceHashesUnchanged":sources_unchanged},
		"verification":{"exe":copied_exe,"pack":copied_pack,"exeSha256":exe_hash,"packSha256":pack_hash,"externalDriver":copied_driver,"driverSha256":FileAccess.get_sha256(copied_driver),"mainSceneOverride":scene_path},
		"productionResourceHashes":{"match":pack_hash == before_pack,"basis":"entire PCK is byte-identical by SHA256; resource inventory and bytes necessarily identical; no individual-resource hash enumeration or repacking"},
		"officialSource":"https://github.com/godotengine/godot/blob/4.7.2-stable/core/config/project_settings.cpp#L689-L703"
	}
	if not write_file(output.path_join("acceptance-copy-proof.json"),JSON.stringify(receipt,"\t")): return
	if not sources_unchanged or not identical: fail("production preservation or copy hash check failed"); return
	print("ACCEPTANCE_COPY_PASS productionResourceHashes=match exeSha256=",exe_hash," packSha256=",pack_hash," executable=",copied_exe)
	quit(0)
func write_file(path: String, content: String) -> bool:
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null: fail("cannot write verification-only file: "+path); return false
	file.store_string(content); file.flush()
	var ok := file.get_error() == OK; file.close()
	if not ok: fail("verification file write failed: "+path)
	return ok
func fail(detail: String) -> void:
	printerr("ACCEPTANCE_COPY_FAIL ",detail)
	quit(1)
