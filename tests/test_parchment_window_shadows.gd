extends SceneTree

var failures := 0
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("_run")

func _has_frame(style: StyleBox) -> bool:
	return style != null and style.has_method("get_body_style") and style.has_method("get_edge_style")

func _run() -> void:
	var factory = load("res://game/ui/shared/parchment_theme.gd")
	var theme: Theme = factory.create()
	for kind in ["PopupPanel", "PopupMenu", "TooltipPanel"]:
		check(_has_frame(theme.get_stylebox("panel", kind)), kind + " floating surface has generated outer frame")
	for kind in ["PanelContainer", "Panel"]:
		check(not _has_frame(theme.get_stylebox("panel", kind)), kind + " is neutral by default for nested surfaces")
	for state in ["embedded_border", "embedded_unfocused_border"]:
		var border: StyleBox = theme.get_stylebox(state, "Window")
		check(_has_frame(border), state + " uses generated outer frame")
		if _has_frame(border): check(border.get_expand_margin(SIDE_TOP) >= 32, state + " keeps opaque title backing")
	for kind in ["AcceptDialog", "FileDialog", "ItemList", "Tree"]:
		check(not _has_frame(theme.get_stylebox("panel", kind)), kind + " inner surface does not duplicate window frame")
	for kind in ["LineEdit", "TextEdit"]:
		check(not _has_frame(theme.get_stylebox("normal", kind)), kind + " field stays inset")
	check(factory.has_method("floating_panel"), "explicit parchment panel overrides can retain floating frame")
	if factory.has_method("floating_panel"):
		var style: StyleBox = factory.floating_panel(20)
		check(_has_frame(style), "explicit floating panel has frame")
		if _has_frame(style):
			var body: StyleBoxTexture = style.call("get_body_style")
			var edge: StyleBoxTexture = style.call("get_edge_style")
			check(body.texture != null and body.texture.resource_path == factory.PANEL_PATH, "floating panel retains existing paper artwork")
			check(edge.texture != null and edge.texture.resource_path.contains("quiet/framed/"), "frame uses generated transparent artwork")
			check(style.get_content_margin(SIDE_LEFT) == 20, "frame preserves original content margin")
	print("PARCHMENT_WINDOW_SHADOW_TEST checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
