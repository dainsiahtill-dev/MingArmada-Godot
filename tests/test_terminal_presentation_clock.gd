extends SceneTree
## Finite scene presentation time must never unfreeze the native encounter.
const CLOCK_PATH := "res://game/scenes/common/terminal_presentation_clock.gd"
const EXPECTED_CAP_SECONDS := 10.0
var assertions := 0
var failures := 0

func check(value: bool, detail: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL: ", detail)

func close(value: float, expected: float) -> bool:
	return absf(value - expected) < 1.0e-8

func _initialize() -> void:
	_run.call_deferred()

func _native(status: String = "defeat", hull: float = 0.0, time: float = 10.0, battle_id: String = "terminal-a") -> Dictionary:
	return {
		"battleId": battle_id,
		"status": status,
		"time": time,
		"tick": 600,
		"playerId": "player",
		"ships": [{"id": "player", "hull": hull, "visual": {"position": {"x": 2.0, "y": 0.0, "z": 3.0}}}],
		"projectiles": [],
	}

func _clock():
	return load(CLOCK_PATH).new()

func _finish() -> void:
	print("TERMINAL_PRESENTATION_CLOCK_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)

func _run() -> void:
	# Missing production API is a deliberate assertion RED, not an invalid preload.
	check(ResourceLoader.exists(CLOCK_PATH), "finite terminal presentation clock exists")
	if not ResourceLoader.exists(CLOCK_PATH):
		_finish()
		return
	var clock = _clock()
	for method: String in ["advance", "snapshot", "is_playing", "is_anchored", "allows_playback", "reset", "diagnostics"]:
		check(clock.has_method(method), "terminal clock exposes " + method)
		if not clock.has_method(method):
			_finish()
			return

	var native := _native()
	var original := native.duplicate(true)
	check(clock.snapshot(native) == original and not clock.is_anchored() and not clock.allows_playback(), "manual first snapshot cannot anchor or play a death without an accepted callback")
	check(close(clock.advance(native, ["result"], 0.1, 0.1), 0.0), "lethal native callback only anchors presentation and never double-counts its accepted delta")
	check(close(clock.snapshot(native).time, 10.0), "first death snapshot retains native event birth time")
	check(clock.is_playing(), "result pause with a sunk ship permits a finite visual tail")
	check(clock.is_anchored() and clock.allows_playback(), "first terminal callback exposes its cheap anchored result-only playback gate")
	check(close(clock.advance(native, ["result"], 0.1), 0.1), "next accepted physics callback advances terminal visual time")
	check(close(clock.snapshot(native).time, 10.1), "visual snapshot carries terminal elapsed time")
	check(native == original, "terminal advance and snapshot preserve every authoritative native field")
	var visual: Dictionary = clock.snapshot(native)
	visual.ships[0].visual.position.x = 999.0
	visual.projectiles.append({"id": "visual-only"})
	check(native == original, "visual snapshot owns nested ship and projectile data without mutating authority")
	check(visual.tick == 600 and visual.status == "defeat", "visual clone retains native tick and result")
	for unused in 4:
		check(close(clock.snapshot(native).time, 10.1), "manual same-time presentation cannot invent a visual interval")
	check(close(clock.diagnostics().elapsed, 0.1), "diagnostics report accepted presentation time")

	for reason: String in ["blur", "menu", "player", "loading", "chart", "dialog", "hidden", "error", "rate-zero", "unknown"]:
		check(close(clock.advance(native, ["result", reason], 0.25), 0.0), reason + " pause blocks terminal presentation")
		check(not clock.is_playing() and close(clock.snapshot(native).time, 10.1), reason + " pause retains last accepted visual time")
		check(clock.is_anchored() and not clock.allows_playback(), reason + " closes playback permission without discarding the death anchor")
	check(close(clock.advance(native, [], 0.25), 0.0), "terminal status without result pause cannot advance presentation")
	check(close(clock.snapshot(native).time, 10.1), "missing result pause cannot rewind already accepted presentation")
	check(not clock.allows_playback(), "missing result pause closes the cheap playback gate")
	check(close(clock.advance(native, ["result"], 0.1), 0.1), "focus and menu resume continue only newly accepted physics time")
	check(close(clock.snapshot(native).time, 10.2), "resume excludes all paused intervals")

	for invalid: float in [-0.1, NAN, INF, -INF]:
		check(close(clock.advance(native, ["result"], invalid), 0.0), "invalid physics interval is rejected: " + str(invalid))
		check(close(clock.snapshot(native).time, 10.2), "invalid interval preserves finite visual time")
	check(close(clock.advance(native, ["result"], 0.0), 0.0), "zero physics interval cannot advance a terminal tail")
	for invalid_consumed: float in [-0.1, NAN, INF]:
		check(close(clock.advance(native, ["result"], 0.1, invalid_consumed), 0.0), "invalid native accepted interval cannot fabricate presentation time")
	check(close(clock.advance(native, ["result"], 0.1, 0.1), 0.0) and close(clock.snapshot(native).time, 10.2), "already consumed native interval is not billed to terminal time at the same native snapshot")
	check(close(clock.advance(native, ["result"], 1000.0), 0.25), "one callback cannot add a stall-sized visual interval")
	check(close(clock.snapshot(native).time, 10.45), "large callback accepts only the bounded quarter second")

	var bounded = _clock()
	check(close(bounded.advance(native, ["result"], 0.25), 0.0), "terminal-first presentation anchors even when no native interval was consumed")
	for unused in 39:
		bounded.advance(native, ["result"], 0.25)
	check(close(bounded.snapshot(native).time, 10.0 + EXPECTED_CAP_SECONDS - 0.25) and bounded.is_playing(), "visual tail retains the later froth interval beyond completed crew ragdolls")
	check(close(bounded.advance(native, ["result"], 0.24), 0.24), "tail accepts the remaining interval before its finite end")
	check(close(bounded.advance(native, ["result"], 0.25), 0.01), "final callback accepts only time remaining in ten-second tail")
	check(close(bounded.snapshot(native).time, 10.0 + EXPECTED_CAP_SECONDS) and not bounded.is_playing(), "tail ends after source sinking, crew and later froth effects complete")
	check(bounded.is_anchored() and bounded.allows_playback(), "final positive tail interval retains result-only permission after playing ends")
	for unused in 8:
		check(close(bounded.advance(native, ["result"], 0.25), 0.0), "finished terminal clock cannot restart itself")
		check(close(bounded.snapshot(native).time, 10.0 + EXPECTED_CAP_SECONDS), "finished snapshot retains final visual time without replaying death")
	bounded.advance(native, ["result", "menu"], 0.25)
	check(not bounded.allows_playback() and close(bounded.snapshot(native).time, 10.0 + EXPECTED_CAP_SECONDS), "menu also blocks completed terminal playback while preserving its final phase")
	bounded.advance(native, ["result"], 0.25)
	check(bounded.allows_playback() and not bounded.is_playing() and close(bounded.snapshot(native).time, 10.0 + EXPECTED_CAP_SECONDS), "resumed completed tail cannot restart or rewind")

	for status: String in ["victory", "defeat"]:
		var outcome = _clock()
		var outcome_native := _native(status)
		outcome.advance(outcome_native, ["result"], 0.1)
		check(close(outcome.advance(outcome_native, ["result"], 0.1), 0.1), status + " with a sunk ship accepts the visual tail")
	for status: String in ["active", "sailing", "ready", "surrender", "surrendered"]:
		var active = _clock()
		var active_native := _native(status)
		active.advance(active_native, ["result"], 0.1)
		check(close(active.advance(active_native, ["result"], 0.1), 0.0), status + " cannot open a terminal presentation tail")
		check(active.snapshot(active_native) == active_native and not active.is_playing(), status + " keeps the full native snapshot")
	var surrender = _clock()
	var survivor := _native("defeat", 5.0)
	surrender.advance(survivor, ["result"], 0.1)
	check(close(surrender.advance(survivor, ["result"], 0.1), 0.0) and surrender.snapshot(survivor) == survivor, "surrender outcome without an actual sunk ship has no fabricated visual tail")
	var enemy_sink := _native("victory", 5.0)
	enemy_sink.ships.append({"id": "enemy", "hull": -1.0})
	var victory = _clock()
	victory.advance(enemy_sink, ["result"], 0.1)
	check(close(victory.advance(enemy_sink, ["result"], 0.1), 0.1), "victory tail follows any sunk native ship rather than only the player")

	var restarted := _native("active", 50.0, 0.0)
	check(bounded.snapshot(restarted) == restarted and not bounded.is_playing(), "native rewind and restart discard finished visual time immediately")
	check(close(bounded.advance(restarted, [], 0.1), 0.0), "restarted active encounter receives no old terminal interval")
	var new_death := _native("defeat", 0.0, 0.1)
	check(close(bounded.advance(new_death, ["result"], 0.1), 0.0), "restarted lethal callback receives a fresh event-time anchor")
	check(close(bounded.advance(new_death, ["result"], 0.1), 0.1) and close(bounded.snapshot(new_death).time, 0.2), "restarted battle starts its own finite tail")
	var new_epoch := _native("defeat", 0.0, 0.1, "terminal-b")
	check(close(bounded.snapshot(new_epoch).time, 0.1) and not bounded.is_playing(), "new battle identity clears same-time terminal presentation")
	check(close(bounded.advance(new_epoch, ["result"], 0.1), 0.0), "new battle identity anchors before accepting any visual interval")
	check(close(bounded.advance(new_epoch, ["result"], 0.1), 0.1), "new battle identity can play an independent terminal tail")
	var restored_time := _native("defeat", 0.0, 5.0, "terminal-b")
	check(close(bounded.snapshot(restored_time).time, 5.0), "externally advanced authority clears the old visual offset")
	check(close(bounded.advance(restored_time, ["result"], 0.1, 0.1), 0.0), "externally accepted terminal state anchors without double counting authority")
	check(close(bounded.advance(restored_time, ["result"], 0.1), 0.1), "external native time creates a fresh terminal tail")
	bounded.reset()
	check(not bounded.is_playing() and not bounded.is_anchored() and not bounded.allows_playback() and close(bounded.snapshot(restored_time).time, 5.0), "explicit scene reset clears old visual time and activity")
	check(close(bounded.advance(restored_time, ["result"], 0.1), 0.0), "reset terminal state anchors before accepting its next interval")

	var blocked_birth = _clock()
	blocked_birth.advance(native, ["result", "rate-zero"], 0.1)
	check(blocked_birth.is_anchored() and not blocked_birth.allows_playback() and close(blocked_birth.snapshot(native).time, 10.0), "blocked lethal callback remembers death birth without accepting rate-zero time")
	check(close(blocked_birth.advance(native, ["result"], 0.1), 0.1), "removing rate-zero resumes from the original terminal anchor")
	var invalid_birth = _clock()
	invalid_birth.advance(native, ["result"], NAN)
	check(not invalid_birth.is_anchored() and not invalid_birth.allows_playback(), "invalid first callback cannot establish a terminal playback anchor")
	check(close(invalid_birth.advance(native, ["result"], 0.1), 0.0), "first valid callback still anchors after rejected invalid delta")

	var missing_time := _native()
	missing_time.erase("time")
	var missing_battle := _native()
	missing_battle.erase("battleId")
	var invalid_ships := _native()
	invalid_ships.ships = {"player": {"hull": 0.0}}
	var missing_hull := _native()
	missing_hull.ships[0].erase("hull")
	var string_hull := _native()
	string_hull.ships[0].hull = "0"
	var bad_hull := _native()
	bad_hull.ships[0].hull = NAN
	for malformed: Dictionary in [missing_time, missing_battle, invalid_ships, missing_hull, string_hull, bad_hull, _native("defeat", 0.0, NAN), _native("defeat", 0.0, INF), _native("defeat", 0.0, -1.0)]:
		var rejected = _clock()
		check(close(rejected.advance(malformed, ["result"], 0.1), 0.0) and not rejected.is_anchored(), "malformed native snapshot cannot establish a death tail")
		check(close(rejected.advance(malformed, ["result"], 0.1), 0.0) and not rejected.allows_playback(), "malformed native data cannot advance terminal presentation")
	var corrupted = _clock()
	corrupted.advance(native, ["result"], 0.1)
	corrupted.advance(native, ["result"], 0.1)
	corrupted.snapshot(missing_time)
	check(not corrupted.is_anchored() and close(corrupted.snapshot(native).time, 10.0), "invalid native identity discards stale visual offset before any later valid battle")
	var active_same_time := _native("active", 0.0, 5.0, "terminal-b")
	bounded.advance(restored_time, ["result"], 0.1)
	check(bounded.snapshot(active_same_time) == active_same_time and not bounded.is_anchored(), "active native state clears a terminal tail even without relying on a time rewind")
	_finish()
