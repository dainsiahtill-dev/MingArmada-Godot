extends RefCounted
## Original indexed height geometry adapted to a game port. No render nodes,
## waves, clocks or business port catalogue. Sampling is the sole world contract.
const SOURCE_HASHES := {
	"cat_island":"d1b4f3b42347916ef7f85262e1ac16a65234c4981a374039b55ab0b417d30a1c",
	"coastal2":"ce35636beb51ec4865e8073bd0d0803c75c88e3633770517233c657a254d950d",
	"virgin_islands":"5224fcf8947623796cf50f4ffffbb1a59a385af3df9a4c8604a2ad3fbc6fe06f"}
const IDS := ["cat_island","coastal2","virgin_islands"]
const SEA_INDEX := 128.0
const OUTSIDE_HEIGHT := -24.0
const ART_DEFAULTS := {"sea_index":128.0,"height_gain":1.0,"smoothing_radius":0,"border_rounding":0.0,"border_fade_pixels":5.0}
var _values:=PackedByteArray()
var _sample_values:=PackedFloat64Array()
var _width:=0
var _height:=0
var _source_center:=Vector2.ZERO
var _source_outward:=Vector2.DOWN
var _source_across:=Vector2.RIGHT
var _center:=Vector2.ZERO
var _dock:=Vector2.ZERO
var _inward:=Vector2.LEFT
var _across:=Vector2.DOWN
var _scale:=1.0
var _peak:=1.0
var _minimum:=94.0
var _maximum:=172.0
var _id:=""
var _art: Dictionary=ART_DEFAULTS.duplicate()

static func load_source(id: String) -> Dictionary:
	if not SOURCE_HASHES.has(id): return {}
	var path: String="res://assets/data/reference_islands/"+id+"/height.json"
	if not FileAccess.file_exists(path) or FileAccess.get_sha256(path)!=SOURCE_HASHES[id]: return {}
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary and valid_source(data) else {}

static func valid_source(data: Dictionary) -> bool:
	for key: String in ["width","height"]:
		if not data.has(key) or not (data[key] is int or data[key] is float): return false
		if not is_finite(float(data[key])) or float(data[key])<2 or float(data[key])!=floor(float(data[key])): return false
	if not data.get("values") is Array or data.values.size()!=int(data.width)*int(data.height): return false
	for value: Variant in data.values:
		if not (value is int or value is float) or not is_finite(float(value)) or float(value)<0 or float(value)>255 or float(value)!=floor(float(value)): return false
	return true

static func valid_art_options(options: Dictionary) -> bool:
	for key: Variant in options:
		if not key is String or not ART_DEFAULTS.has(key) or not (options[key] is int or options[key] is float) or not is_finite(float(options[key])): return false
	var sea:=float(options.get("sea_index",128.0))
	var gain:=float(options.get("height_gain",1.0))
	var radius:=float(options.get("smoothing_radius",0))
	var rounding:=float(options.get("border_rounding",0.0))
	var fade:=float(options.get("border_fade_pixels",5.0))
	return sea>0.0 and sea<255.0 and gain>0.0 and gain<=1.0 and radius>=0.0 and radius<=8.0 and radius==floor(radius) and rounding>=0.0 and rounding<=.45 and fade>0.0 and fade<=32.0

static func _filtered_values(values: PackedByteArray,width: int,height: int,radius: int) -> PackedFloat64Array:
	var result:=PackedFloat64Array()
	result.resize(values.size())
	for index in values.size(): result[index]=float(values[index])
	if radius==0: return result
	var temporary:=PackedFloat64Array(); temporary.resize(values.size())
	var divisor:=float((radius+1)*(radius+1))
	# Cache one deterministic separable triangular neighborhood per configured
	# profile. Original bytes stay immutable; sampling does no filtering work.
	for row in height:
		for column in width:
			var sum:=0.0
			for offset in range(-radius,radius+1): sum+=result[row*width+clampi(column+offset,0,width-1)]*float(radius+1-absi(offset))
			temporary[row*width+column]=sum/divisor
	for row in height:
		for column in width:
			var sum:=0.0
			for offset in range(-radius,radius+1): sum+=temporary[clampi(row+offset,0,height-1)*width+column]*float(radius+1-absi(offset))
			result[row*width+column]=sum/divisor
	return result

func configure(port: Dictionary,data: Dictionary,id: String,art_options: Dictionary={}) -> bool:
	if id not in IDS or not valid_source(data) or not valid_art_options(art_options): return false
	var art: Dictionary=ART_DEFAULTS.duplicate(); art.merge(art_options,true)
	var sea:=float(art.sea_index)
	for key: String in ["x","z","islandX","islandZ","radius","peak"]:
		if not port.has(key) or not (port[key] is int or port[key] is float) or not is_finite(float(port[key])): return false
	if float(port.radius)<=0.0 or float(port.peak)<=0.0: return false
	var width:=int(data.width)
	var height:=int(data.height)
	var minimum:=255.0
	var maximum:=0.0
	var land_min:=Vector2(float(width),float(height))
	var land_max:=Vector2.ZERO
	var peak_point:=Vector2.ZERO
	var values:=PackedByteArray()
	values.resize(width*height)
	for index in values.size():
		var value:=float(data.values[index])
		values[index]=int(value)
		minimum=minf(minimum,value)
		maximum=maxf(maximum,value)
	if maximum<=sea or minimum>=sea: return false
	var samples:=_filtered_values(values,width,height,int(art.smoothing_radius))
	var filtered_maximum:=-INF
	for index in samples.size():
		var value:=samples[index]
		if value>filtered_maximum: filtered_maximum=value; peak_point=Vector2(float(index%width),float(index/width))
		if value>sea:
			var point:=Vector2(float(index%width),float(index/width))
			land_min=land_min.min(point); land_max=land_max.max(point)
	if filtered_maximum<=sea: return false
	var source_center: Vector2=(land_min+land_max)*.5
	var source_radius:=0.0
	for index in samples.size():
		if samples[index]>sea:
			source_radius=maxf(source_radius,Vector2(float(index%width),float(index/width)).distance_to(source_center))
	if source_radius<=0.0: return false
	var outward: Vector2=(peak_point-source_center).normalized()
	if outward==Vector2.ZERO: outward=Vector2.DOWN
	var center:=Vector2(float(port.islandX),float(port.islandZ))
	var dock:=Vector2(float(port.x),float(port.z))
	var inward: Vector2=(center-dock).normalized()
	if inward==Vector2.ZERO: inward=Vector2.LEFT
	# All validation and shape derivation above precede the atomic accepted state.
	_values=values; _sample_values=samples; _width=width; _height=height; _art=art
	_source_center=source_center; _source_outward=outward
	_source_across=Vector2(-outward.y,outward.x)
	_center=center; _dock=dock; _inward=inward; _across=Vector2(-inward.y,inward.x)
	_scale=float(port.radius)*.92/source_radius
	_peak=float(port.peak); _minimum=minimum; _maximum=maximum; _id=id
	return true

func sample_height(x: float,z: float) -> float:
	if not is_finite(x) or not is_finite(z): return NAN
	if _values.is_empty(): return OUTSIDE_HEIGHT
	var offset:=Vector2(x,z)-_center
	var point: Vector2=_source_center+_source_outward*offset.dot(-_inward)/_scale+_source_across*offset.dot(_across)/_scale
	var h:=_source_height(point)
	var relative:=Vector2(x,z)-_dock
	var along: float=relative.dot(_inward)
	var lateral:=absf(relative.dot(_across))
	# A local navigable approach and pier landing. The source silhouette remains
	# unmodified everywhere outside this narrow harbor adaptation.
	var width_mask:=1.0-smoothstep(18.0,35.0,lateral)
	var along_mask:=smoothstep(-120.0,-80.0,along)*(1.0-smoothstep(55.0,95.0,along))
	var landward:=smoothstep(20.0,43.0,along)
	var target:=lerpf(-8.0,2.1,landward)+maxf(along-43.0,0.0)*.025
	return lerpf(h,target,width_mask*along_mask)

func _source_height(point: Vector2) -> float:
	if point.x<0.0 or point.y<0.0 or point.x>_width-1 or point.y>_height-1: return OUTSIDE_HEIGHT
	var ix:=mini(int(floor(point.x)),_width-2)
	var iy:=mini(int(floor(point.y)),_height-2)
	var f: Vector2=point-Vector2(ix,iy)
	var a:=_sample_values[iy*_width+ix]
	var b:=_sample_values[iy*_width+ix+1]
	var c:=_sample_values[(iy+1)*_width+ix]
	var d:=_sample_values[(iy+1)*_width+ix+1]
	var raw:=lerpf(lerpf(a,b,f.x),lerpf(c,d,f.x),f.y)
	var sea:=float(_art.sea_index)
	var h: float=(raw-sea)*(_peak/(_maximum-sea)*float(_art.height_gain) if raw>=sea else 24.0/(sea-_minimum))
	# coastal2 is a mainland extract. Close only its original rectangle border;
	# this is an explicit game adaptation, not an invented original sea level.
	var edge:=minf(minf(point.x,_width-1-point.x),minf(point.y,_height-1-point.y))
	if float(_art.border_rounding)>0.0:
		var half_size:=Vector2(float(_width-1),float(_height-1))*.5
		var round_radius: float=minf(_width-1,_height-1)*float(_art.border_rounding)
		var q: Vector2=(point-half_size).abs()-(half_size-Vector2.ONE*round_radius)
		edge=round_radius-q.max(Vector2.ZERO).length()-minf(maxf(q.x,q.y),0.0)
	return lerpf(OUTSIDE_HEIGHT,h,smoothstep(0.0,float(_art.border_fade_pixels),edge))

func diagnostics() -> Dictionary:
	return {"id":_id,"sourceHash":SOURCE_HASHES.get(_id,""),"width":_width,"height":_height,"scale":_scale,"sourceCenter":_source_center,"sourceOutward":_source_outward,"islandCenter":_center,"dock":_dock,"inward":_inward,"peak":_peak,"seaIndex":_art.sea_index,"heightGain":_art.height_gain,"smoothingRadius":_art.smoothing_radius,"borderRounding":_art.border_rounding,"borderFadePixels":_art.border_fade_pixels,"cachedSamples":_sample_values.size(),"scope":"Original indexed geometry with explicit optional game-art filtering/scale, border closure and local harbor adaptation; not an original engine reconstruction."}
