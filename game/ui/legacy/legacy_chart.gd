extends "res://game/ui/charts/nautical_chart.gd"
## Old adventure API supplies overlays; fleet comes only from native snapshots.
const Catalog=preload("res://game/domain/legacy/catalog.gd")
var snapshot: Dictionary = {}
func apply_snapshot(value: Dictionary) -> void:
	snapshot=value.duplicate(true)
	apply_naval_snapshot(_native)
func apply_naval_snapshot(native: Dictionary, overlays: Dictionary = {}) -> void:
	var annotations={"activeObjectives":snapshot.get("activeObjectives",[]),"waypoint":snapshot.get("waypoint",{}),"landSites":Catalog.DATA.LAND_SITES}
	annotations.merge(overlays,true)
	super.apply_naval_snapshot(native,annotations)
func dispose() -> void:
	snapshot.clear()
	super.dispose()
