extends "res://tests/test_hero_fuchuan_art.gd"
## Run the complete hull/deck/gunport/window/rudder contracts on the new asset.
func make_provider()->RefCounted:return Art.new("art_r7c")
func finish()->void:
	super.finish()
	print("HERO_PALETTE_ART_TESTS assertions=",assertions," failures=",failures)
