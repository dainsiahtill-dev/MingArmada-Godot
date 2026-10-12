extends RefCounted
## Game art layout; reusable terrain modules know no port names or catalogue.
static func options() -> Dictionary:
	# Formal campaign uses accepted natural v1 islands around unchanged game
	# anchors. Ships, charts, navigation and rendering share cached triangles.
	return {"natural_islands":true,"natural_radius_scale":0.8,"natural_resolution":257,
		"natural_radius_by_port":{"kinmen":0.65,"forward-supply":0.6},
		"natural_seeds":{"xiamen":1661,"kinmen":1662,"forward-supply":1663}}

static func source_options() -> Dictionary:
	# A sheltered town needs a broad bay/backland; the narrow ridge fits an
	# outpost, while the supply route benefits from separate shallow islets.
	return {"reference_islands":true,"reference_profiles":{"xiamen":"coastal2","kinmen":"cat_island","forward-supply":"virgin_islands"},
		"reference_art":{"sea_index":127.5,"height_gain":0.35,"smoothing_radius":1},
		# Only the mainland extract needs its artificial boundary closed. The
		# already sea-surrounded islands keep their original coast margins.
		"reference_art_by_profile":{"coastal2":{"border_rounding":0.30,"border_fade_pixels":14.0},
			"virgin_islands":{"harbor_land_half_width":6.0,"harbor_land_fade_width":4.0}}}
