extends RefCounted
## Exact original Mingqi ridge + shelf formula; geometry arrives as plain data.
## This module owns no business port catalog and imports no simulation rules.

var _ports: Array = []
var _home_x := 0.0
var _home_z := 0.0
var _length := 0.0
var _ux := 0.0
var _uz := 0.0

func configure_ports(ports: Array) -> bool:
	for port in ports:
		if not port is Dictionary:
			return false
		for key in ["x", "z", "islandX", "islandZ", "radius", "peak"]:
			if not port.has(key) or not is_finite(float(port[key])):
				return false
		if float(port.radius) <= 0.0:
			return false
	_ports = ports.duplicate(true)
	_length = 0.0
	if _ports.size() >= 2:
		_home_x = float(_ports[0].x)
		_home_z = float(_ports[0].z)
		var dx := float(_ports[1].x) - _home_x
		var dz := float(_ports[1].z) - _home_z
		_length = sqrt(dx * dx + dz * dz)
		if _length > 0.0:
			_ux = dx / _length
			_uz = dz / _length
	return true

func sample_height(x: float, z: float) -> float:
	if not is_finite(x) or not is_finite(z):
		return NAN
	var height := -24.0
	for island: Dictionary in _ports:
		var dx := (x - float(island.islandX)) / float(island.radius)
		var dz := (z - float(island.islandZ)) / (float(island.radius) * 0.82)
		var d2 := dx * dx + dz * dz
		if d2 < 1.0:
			var body := pow(1.0 - d2, 1.65)
			var ridge := (sin(x * 0.044 + z * 0.018) + sin(z * 0.056 - x * 0.013)) * 2.2 * body
			height = maxf(height, -24.0 + (float(island.peak) + 24.0) * body + ridge)
	if _length > 0.0:
		var along := (x - _home_x) * _ux + (z - _home_z) * _uz
		var across := -(x - _home_x) * _uz + (z - _home_z) * _ux
		var end_distance := maxf(maxf(_length * 0.32 - along, 0.0), along - _length * 0.68)
		var distance := sqrt(across * across + end_distance * end_distance)
		if distance < 135.0:
			var t := clampf((135.0 - distance) / 45.0, 0.0, 1.0)
			height = maxf(height, -24.0 + 21.6 * t * t * (3.0 - 2.0 * t))
	return height

func sample_data(x: float, z: float) -> Dictionary:
	var height := sample_height(x, z)
	return {"height": height, "normalized": 0.6 + height / (50.0 if height < 0.0 else 150.0), "isUnderwater": height < 0.0}
