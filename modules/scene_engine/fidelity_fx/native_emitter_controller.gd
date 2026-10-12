extends RefCounted
## Original 5AD920 visibility-window callbacks; rate is current or window midpoint.
const Math = preload("res://modules/scene_engine/fidelity_fx/native_particle_math.gd")
const Shared = preload("res://modules/scene_engine/fidelity_island/native_math.gd")
var fields: Dictionary
var data: Dictionary
var clock
var previous_mapped = null
var previous_visible := false
var last_app = null
var last_mapped = null
var force_update := false
var calls := 0

func _init(controller: Dictionary, source: Dictionary) -> void:
	fields = controller.duplicate(true)
	fields.start_time = Math.f32(fields.start_time)
	fields.stop_time = Math.f32(fields.stop_time)
	data = source.duplicate(true)
	for key in data.float_keys.keys:
		key.time = Math.f32(key.time)
		key.value = Math.f32(key.value)
		if key.has("forward"): key.forward = Math.f32(key.forward)
		if key.has("backward"): key.backward = Math.f32(key.backward)
	for key in data.visibility_keys: key.time = Math.f32(key.time)
	clock = Shared.ControllerClock.new(fields)
	reset()

func reset() -> void:
	clock.reset()
	previous_mapped = null
	previous_visible = false
	last_app = null
	last_mapped = null
	force_update = false
	calls = 0

static func emission_window(timestamp: float, now: float, previous: float, active_start: float, active_end: float, birth_rate: float):
	timestamp = Math.f32(timestamp)
	now = Math.f32(now)
	previous = Math.f32(previous)
	active_start = Math.f32(active_start)
	active_end = Math.f32(active_end)
	birth_rate = Math.f32(birth_rate)
	if not (birth_rate > 0.0 and active_start < active_end and now > active_start and previous < active_end): return null
	var elapsed: float = Math.f32(minf(now,active_end)-active_start)
	var low: int = int(maxf(0.0,previous-active_start)*birth_rate)
	var high: int = int(elapsed*birth_rate)&65535
	var count: int = high-low
	var inverse: float = Math.f32(1.0/birth_rate)
	var ages := []
	for _i in (count&65535):
		low = (low+1)&65535
		ages.append(Math.f32(elapsed-low*inverse))
	return {"timestamp":timestamp,"count":count,"ages":ages}

func advance(app_time: float, system_previous_time: float) -> Array:
	app_time = Math.f32(app_time)
	if not int(fields.flags)&8: return []
	if last_app == app_time and not force_update: return []
	var previous_app = last_app
	var mapped: float = Math.f32(clock.advance(app_time))
	if previous_app != null and previous_app > app_time: previous_mapped = null
	if last_mapped == mapped and not force_update:
		last_app = app_time
		return []
	last_mapped = mapped
	return step_mapped(mapped,app_time,system_previous_time)

func step_mapped(mapped: float, app_time: float, system_previous_time: float) -> Array:
	mapped = Math.f32(mapped)
	app_time = Math.f32(app_time)
	system_previous_time = Math.f32(system_previous_time)
	if not int(fields.flags)&8: return []
	if last_app != null and last_app > app_time: previous_mapped = null
	if last_app == app_time and not force_update: return []
	var keys: Array = data.visibility_keys
	var visible: bool = Math.visibility_at(keys,mapped)
	last_app = app_time
	force_update = false
	if previous_mapped == null:
		previous_mapped = mapped
		previous_visible = visible
		return []
	var previous: float = previous_mapped
	var was_visible: bool = previous_visible
	previous_mapped = mapped
	previous_visible = visible
	var packets := []
	for _iteration in (keys.size()+1):
		var start_index: int
		if was_visible:
			start_index = keys.size()
			while start_index > 0:
				var key: Dictionary = keys[start_index-1]
				if key.time <= previous and not bool(key.value): break
				start_index -= 1
		else:
			start_index = -1
			for i in keys.size():
				var key: Dictionary = keys[i]
				if key.time > previous and (previous > mapped or key.time <= mapped) and bool(key.value):
					start_index = i
					break
			if start_index < 0:
				if previous <= mapped: return packets
				for i in keys.size():
					if keys[i].time < mapped and bool(keys[i].value):
						start_index = i
						break
				if start_index < 0: return packets
		var end_index: int = start_index
		while end_index < keys.size() and bool(keys[end_index].value): end_index += 1
		if end_index == keys.size(): end_index -= 1
		assert(start_index < keys.size() and end_index >= 0,"Invalid original visibility interval")
		var start: float = Math.f32(keys[start_index].time)
		var native_end: float = Math.f32(keys[end_index].time)
		var end: float = native_end
		var window_now: float
		var window_previous: float
		var rate_time: float
		if previous > mapped:
			if native_end > previous:
				window_now = Math.f32(keys[-1].time)
				window_previous = previous
				rate_time = Math.f32((end-start)*0.5+start)
			else:
				window_now = mapped
				window_previous = Math.f32(keys[0].time)
				end = mapped if native_end >= mapped else native_end
				rate_time = Math.f32((end-start)*0.5+start)
		else:
			window_previous = previous
			if native_end < mapped:
				window_now = native_end
				rate_time = Math.f32((end-start)*0.5+start)
			else:
				window_now = mapped
				rate_time = mapped
		var rate: float = Math.sample_keys(data.float_keys,rate_time)
		var system_base: float = system_previous_time+fields.stop_time-fields.start_time if previous > mapped else system_previous_time
		var timestamp: float = Math.f32(system_base+mapped-previous)
		var packet = emission_window(timestamp,window_now,window_previous,start,end,rate)
		if packet != null:
			packet.window = {"start":start,"end":end,"now":window_now,"previous":window_previous,"rateTime":rate_time,"rate":rate}
			packets.append(packet)
			calls += 1
		if native_end >= mapped: return packets
		previous = window_now
		was_visible = Math.visibility_at(keys,window_now)
	assert(false,"Original visibility schedule did not terminate")
	return packets

func fork():
	var out = get_script().new(fields,data)
	out.previous_mapped = previous_mapped
	out.previous_visible = previous_visible
	out.last_app = last_app
	out.last_mapped = last_mapped
	out.force_update = force_update
	out.calls = calls
	out.clock.last = clock.last
	out.clock.accumulated = clock.accumulated
	out.clock.started = clock.started
	return out
