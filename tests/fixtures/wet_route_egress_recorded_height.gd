extends "res://modules/scene_engine/terrain/height_field.gd"
## Test-only terrain basis for journey-second-corrected.json. The recorded map
## used reference_island_profile.gd at 891ab75ff8a507612ea4ecd087f963f56f4d93ce.
## Commit 1c3fb5996f5712c038240b1dc2bbcb16927b1162 reversed both source axes.
## Frozen raw sea-index/scale/layout still use the real profile numeric oracle;
## production navigation, triangle caches and current geography stay untouched.
const SOURCE_COMMIT="891ab75ff8a507612ea4ecd087f963f56f4d93ce"
func configure_ports(ports: Array, include_shoal_shelf: bool = true, options: Dictionary = {}) -> bool:
	if not super.configure_ports(ports,include_shoal_shelf,options): return false
	for profile: RefCounted in _reference_profiles:
		profile._source_outward=-profile._source_outward
		profile._source_across=-profile._source_across
	return true
func sample_height(x: float,z: float) -> float:
	# Current render triangles were cached before the historical basis change.
	# The retained original-reference API reads the actual accepted profile basis.
	return sample_original_reference_height(x,z)
