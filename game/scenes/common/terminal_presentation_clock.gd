extends RefCounted
## Scene-only accepted physics time after a frozen native terminal result.
## Native authority, events, ship state and save clocks remain unchanged.
const MAX_SECONDS := 10.0
const MAX_CALLBACK_SECONDS := 0.25
var _has_identity := false
var _battle_id := ""
var _native_time := 0.0
var _native_status := ""
var _anchored := false
var _elapsed := 0.0
var _playback_allowed := false

func advance(native: Dictionary, pause_reasons: Array, delta: float, native_consumed: float = 0.0) -> float:
	if not _synchronize(native): return 0.0
	if not _terminal_sinking(native): return 0.0
	_playback_allowed = _result_only(pause_reasons)
	if not is_finite(delta) or delta < 0.0 or not is_finite(native_consumed) or native_consumed < 0.0:
		return 0.0
	if not _anchored:
		if pause_reasons.has("result"):
			_anchored = true
		# The first callback presents death at its native birth, including when
		# that callback already consumed an authoritative lethal physics step.
		return 0.0
	if not allows_playback() or native_consumed > 0.0 or _elapsed >= MAX_SECONDS:
		return 0.0
	var accepted := minf(minf(delta, MAX_CALLBACK_SECONDS), MAX_SECONDS - _elapsed)
	_elapsed = minf(MAX_SECONDS, _elapsed + accepted)
	return accepted

func snapshot(native: Dictionary) -> Dictionary:
	var valid := _synchronize(native)
	var visual := native.duplicate(true)
	if valid and _anchored:
		visual.time = _native_time + _elapsed
	return visual

func is_anchored() -> bool:
	return _anchored

func allows_playback() -> bool:
	# Permission survives the final accepted interval. Callers combine it
	# with that interval or is_playing() when gating presentation audio.
	return _anchored and _playback_allowed

func is_playing() -> bool:
	return allows_playback() and _elapsed < MAX_SECONDS

func reset() -> void:
	_has_identity = false
	_battle_id = ""
	_native_time = 0.0
	_native_status = ""
	_clear_tail()

func diagnostics() -> Dictionary:
	return {"battleId": _battle_id, "nativeTime": _native_time, "visualTime": _native_time + _elapsed, "elapsed": _elapsed, "maxSeconds": MAX_SECONDS, "anchored": is_anchored(), "allowsPlayback": allows_playback(), "playing": is_playing()}

func _synchronize(native: Dictionary) -> bool:
	var supplied_time: Variant = native.get("time")
	var supplied_id: Variant = native.get("battleId")
	if not (supplied_time is float or supplied_time is int) or not is_finite(float(supplied_time)) or float(supplied_time) < 0.0 or not supplied_id is String or supplied_id.is_empty():
		reset()
		return false
	var seconds := float(supplied_time)
	var battle_id := String(supplied_id)
	var status := str(native.get("status", ""))
	if not _has_identity or battle_id != _battle_id or seconds != _native_time or status != _native_status:
		reset()
		_has_identity = true
		_battle_id = battle_id
		_native_time = seconds
		_native_status = status
	if not _terminal_sinking(native): _clear_tail()
	return true

func _terminal_sinking(native: Dictionary) -> bool:
	if not _native_status in ["victory", "defeat"]: return false
	var fleet: Variant = native.get("ships")
	if not fleet is Array: return false
	for candidate: Variant in fleet:
		if not candidate is Dictionary: continue
		var hull: Variant = candidate.get("hull")
		if (hull is float or hull is int) and is_finite(float(hull)) and float(hull) <= 0.0:
			return true
	return false

func _result_only(pause_reasons: Array) -> bool:
	if not pause_reasons.has("result"): return false
	for reason: Variant in pause_reasons:
		if reason != "result": return false
	return true

func _clear_tail() -> void:
	_anchored = false
	_elapsed = 0.0
	_playback_allowed = false
