extends SceneTree
## Actual gameplay consumers must retain paper assets, readable ink and input contracts.
var assertions := 0
var failures := 0

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	_run.call_deferred()

func _paper(panel: Control, description: String) -> void:
	var style := panel.get_theme_stylebox("panel")
	check(style is StyleBoxTexture and style.texture != null, description + " draws the generated paper resource")
	if style is StyleBoxTexture and style.texture:
		check(style.texture.get_width() > 32 and style.texture.get_height() > 32, description + " texture has usable source pixels")

func _ink(label: Label, description: String) -> void:
	var color := label.get_theme_color("font_color")
	var linear := color.srgb_to_linear()
	var luminance := linear.r * 0.2126 + linear.g * 0.7152 + linear.b * 0.0722
	check(luminance < 0.24 and color.a >= 0.9, description + " uses opaque readable ink on pale paper")

func _decorations_ignore(node: Node) -> bool:
	if node is TextureRect and node.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return false
	for child in node.get_children():
		if not _decorations_ignore(child): return false
	return true

func _run() -> void:
	var career = load("res://game/ui/mingqi/mingqi_interface.gd").new()
	root.add_child(career)
	await process_frame
	_paper(career.find_child("hud", true, false), "career HUD")
	_paper(career.find_child("operation", true, false), "career operation folio")
	_ink(career.find_child("title", true, false), "career title")
	_ink(career.find_child("identity", true, false), "career body")
	_ink(career.find_child("keys", true, false), "career secondary text")
	_ink(career.find_child("notice", true, false), "career notice")
	check(career.find_child("MingqiScreen", true, false).mouse_filter == Control.MOUSE_FILTER_IGNORE, "career fullscreen root leaves sea input available")
	check(_decorations_ignore(career), "career decorative textures do not intercept sea or form input")
	career.free()

	var practice = load("res://game/ui/naval_practice.gd").new()
	root.add_child(practice)
	await process_frame
	_paper(practice.get("_panel"), "practice HUD")
	_paper(practice.get("_modal"), "practice result and pause folio")
	_ink(practice.get("_status"), "practice status")
	_ink(practice.get("_notice"), "practice notice")
	check(practice.get("_screen").mouse_filter == Control.MOUSE_FILTER_IGNORE, "practice fullscreen root leaves sea input available")
	var intents: Array = []
	practice.command_requested.connect(func(intent): intents.append(intent))
	practice.find_child("trim", true, false).pressed.emit()
	check(intents == [{"type": "trim"}], "paper action still emits the canonical handling intent exactly once")
	check(_decorations_ignore(practice), "practice decorative textures do not intercept controls")
	practice.free()

	var trial = load("res://game/ui/sailing_hud.gd").new()
	root.add_child(trial)
	await process_frame
	_paper(trial.get_child(0), "trial HUD")
	_ink(trial.get("_status"), "trial status")
	var trial_intents: Array = []
	trial.command_requested.connect(func(intent): trial_intents.append(intent))
	trial.get("_pause").pressed.emit()
	check(trial_intents == [{"type": "pause"}], "trial paper action retains its pause intent")
	trial.free()

	var encounter = load("res://game/ui/encounters/encounter_interface.gd").new()
	root.add_child(encounter)
	await process_frame
	var battle = load("res://game/domain/encounters/land_battle.gd").new(1661)
	encounter.apply_snapshot({"id": "paper-grid", "generation": 1, "kind": "landBattle", "state": battle.snapshot()}, 9)
	_paper(encounter.find_child("encounter_panel", true, false), "encounter folio")
	_ink(encounter.find_child("encounter_heading", true, false), "encounter title")
	var friendly: Button = encounter.find_child("cell_1_2", true, false)
	var hostile: Button = encounter.find_child("cell_7_2", true, false)
	var ground: Button = encounter.find_child("cell_2_2", true, false)
	check(friendly.modulate != hostile.modulate and friendly.modulate != ground.modulate and hostile.modulate != ground.modulate, "paper grid keeps selected friend, enemy and neutral ground visually distinct")
	check(friendly.text.begins_with("我") and hostile.text.begins_with("敌"), "grid labels preserve friend/enemy meaning independently of color")
	check(encounter.mouse_filter == Control.MOUSE_FILTER_IGNORE, "encounter fullscreen root preserves its existing input boundary")
	encounter.free()
	await process_frame
	print("PARCHMENT_GAMEPLAY_UI_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
