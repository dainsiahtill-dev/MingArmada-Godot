extends RefCounted

# Frozen naval-core SPECS at 9ad6a44. Values are physical SI quantities;
# guns and crew are metadata consumed by higher layers, never physics masses.
const SHIP_SPECS := {
	"fuchuan": {"length": 32.0, "width": 9.0, "draft": 2.0, "freeboard": 1.9, "mass": 95000.0, "sailArea": 430.0, "guns": 4, "crew": 100},
	"fisherman": {"length": 14.0, "width": 4.2, "draft": 1.0, "freeboard": 1.15, "mass": 18000.0, "sailArea": 110.0, "guns": 0, "crew": 100},
	"merchant": {"length": 36.0, "width": 10.0, "draft": 2.8, "freeboard": 2.3, "mass": 150000.0, "sailArea": 450.0, "guns": 0, "crew": 100},
	"voc": {"length": 40.0, "width": 11.0, "draft": 3.2, "freeboard": 2.7, "mass": 170000.0, "sailArea": 580.0, "guns": 4, "crew": 100},
	"patrol": {"length": 24.0, "width": 6.0, "draft": 1.4, "freeboard": 1.35, "mass": 50000.0, "sailArea": 290.0, "guns": 3, "crew": 60},
	"heavy": {"length": 52.0, "width": 14.5, "draft": 4.2, "freeboard": 4.2, "mass": 330000.0, "sailArea": 950.0, "guns": 8, "crew": 160},
}
const DEFAULT_CONFIG := {
	"waterCd": 0.35, "waterAreaFactor": 0.8,
	"rudderLiftSlope": 3.5, "rudderStallDeg": 30.0, "rudderAreaFactor": 0.2, "rudderArmFactor": -0.54,
	"yawDamp": 0.5, "maxYawRate": 0.8, "lateralDampCoeff": 0.08,
	"keelLiftSlope": 5.0, "keelStallDeg": 22.0, "keelAreaFactor": 0.25, "keelCd0": 0.03, "keelInducedDragFactor": 0.12,
	"sailPressureScale": 5.0, "noGoZoneDeg": 35.0, "noGoFadeDeg": 15.0,
	"buoyancyEnabled": true, "heaveDamp": 2.5,
}
const MIN_DRAFT_METERS := 0.05

static func ship_spec(kind: String) -> Dictionary:
	return SHIP_SPECS.get(kind, {}).duplicate(true)

static func default_config() -> Dictionary:
	return DEFAULT_CONFIG.duplicate(true)

static func finite_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func finite_or(value: Variant, fallback: float) -> float:
	return float(value) if finite_number(value) else fallback

static func normalized_angle(value: float) -> float:
	if not is_finite(value):
		return 0.0
	if value >= -PI and value < PI:
		return value
	var wrapped := fmod(value + PI, TAU)
	if wrapped < 0.0:
		wrapped += TAU
	return wrapped - PI

static func valid_draft(draft: float, beam: float, mass: float, heave_damp: float, water_area_factor: float) -> bool:
	var area := beam * draft
	return is_finite(draft) and draft >= MIN_DRAFT_METERS and is_finite(area) and area > 0.0 and is_finite(mass) and mass > 0.0 and is_finite(mass * 9.81 / draft) and is_finite(heave_damp) and heave_damp >= 0.0 and is_finite(mass * heave_damp / 4.0) and is_finite(water_area_factor) and water_area_factor >= 0.0 and is_finite(area * water_area_factor) and is_finite(draft * 2.0)
