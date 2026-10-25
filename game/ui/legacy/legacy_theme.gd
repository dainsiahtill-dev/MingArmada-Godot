extends RefCounted
const Parchment = preload("res://game/ui/shared/parchment_theme.gd")

static func create() -> Theme:
	return Parchment.create()
