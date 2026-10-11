extends RefCounted
## Disk transaction adapter. Rules validate bytes; failed writes never adopt a game.
const Codec = preload("res://game/domain/persistence/save_codec.gd")
var path: String
var validator: Callable
func _init(checkpoint_path: String = "user://saves/mingqi-v2.json", validate: Callable = Callable()) -> void:
	path = checkpoint_path; validator = validate if validate.is_valid() else Codec.decode
static func _no(reason: String) -> Dictionary: return {"ok":false,"reason":reason}
func read_checkpoint() -> Dictionary:
	var actual := path
	if not FileAccess.file_exists(actual) and FileAccess.file_exists(path+".rollback"): actual = path+".rollback"
	if not FileAccess.file_exists(actual): return _no("save-not-found")
	var file := FileAccess.open(actual,FileAccess.READ)
	if file == null: return _no("save-read-failed")
	var bytes := file.get_as_text(); file.close()
	var decoded: Dictionary = validator.call(bytes)
	return {"ok":true,"json":bytes} if decoded.get("ok",false) else {"ok":false,"reason":"save-invalid","json":bytes}
func read_backup() -> Dictionary:
	var actual := path+".backup"
	if FileAccess.file_exists(path+".rollback"): actual = path+".rollback"
	if not FileAccess.file_exists(actual): return _no("backup-not-found")
	var file := FileAccess.open(actual,FileAccess.READ)
	if file == null: return _no("backup-read-failed")
	var bytes := file.get_as_text(); file.close()
	return {"ok":true,"json":bytes}
func _rename(from: String,to: String) -> Error:
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(from),ProjectSettings.globalize_path(to))
func _remove(file: String) -> void:
	if FileAccess.file_exists(file): DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
func write_checkpoint(json: String) -> Dictionary:
	var decoded: Dictionary = validator.call(json)
	if not decoded.get("ok",false): return _no("save-invalid")
	var directory := ProjectSettings.globalize_path(path.get_base_dir())
	if DirAccess.make_dir_recursive_absolute(directory) != OK: return _no("save-directory-failed")
	var temporary := path+".staged"
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file == null: return _no("save-write-failed")
	file.store_string(json); file.flush()
	var failed := file.get_error() != OK; file.close()
	if failed: _remove(temporary); return _no("save-write-failed")
	if FileAccess.get_file_as_string(temporary) != json: _remove(temporary); return _no("save-readback-failed")
	# Recover an interrupted previous transaction before beginning the next one.
	if FileAccess.file_exists(path+".rollback"):
		if not FileAccess.file_exists(path):
			if _rename(path+".rollback",path) != OK: _remove(temporary); return _no("save-recovery-failed")
		else:
			_remove(path+".backup")
			if _rename(path+".rollback",path+".backup") != OK: _remove(temporary); return _no("save-backup-failed")
	var had_previous := FileAccess.file_exists(path)
	if had_previous and _rename(path,path+".rollback") != OK: _remove(temporary); return _no("save-replace-failed")
	if _rename(temporary,path) != OK:
		if had_previous: _rename(path+".rollback",path)
		_remove(temporary); return _no("save-replace-failed")
	if FileAccess.get_file_as_string(path) != json:
		_remove(path)
		if had_previous: _rename(path+".rollback",path)
		return _no("save-readback-failed")
	# The new checkpoint is confirmed. Leave rollback bytes available if backup
	# rotation fails; read_backup() prefers them and the next write recovers them.
	if had_previous:
		_remove(path+".backup")
		if _rename(path+".rollback",path+".backup") != OK: return {"ok":true,"warning":"save-backup-rotation-pending"}
	return {"ok":true}
