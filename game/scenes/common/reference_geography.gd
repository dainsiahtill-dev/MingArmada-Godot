extends RefCounted
## Game art layout; reusable terrain modules know no port names or catalogue.
static func options() -> Dictionary:
	# A sheltered town needs a broad bay/backland; the narrow ridge fits an
	# outpost, while the supply route benefits from separate shallow islets.
	return {"reference_islands":true,"reference_profiles":{"xiamen":"coastal2","kinmen":"cat_island","forward-supply":"virgin_islands"}}
