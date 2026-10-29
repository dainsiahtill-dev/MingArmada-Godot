extends "res://game/presentation/combat/combat_atmosphere.gd"
## Candidate live-fire projection. Only canonical fireControl.heat creates a fire.
## Emission uses observed accepted deck poses; skipped frames are not backfilled.
const Fire=preload("res://modules/naval_simulation/combat/fire_control.gd")
const MAX_LIVE_FIRES:=16
const EMISSION_SECONDS:=0.25
var _live:Dictionary={}
var _episode:=0

func apply_snapshot(native:Dictionary)->void:
	if not _ready_state or not _number(native.get("time")) or float(native.time)<0.0 or not native.get("ships",[]) is Array:return
	super.apply_snapshot(native)
	var live_ids:Dictionary={}
	if _enabled:
		for ship:Variant in native.get("ships",[]):
			if not ship is Dictionary or not ship.get("id") is String or not _number(ship.get("hull")):continue
			if float(ship.hull)<=0.0 or not Fire.valid(ship.get("fireControl")) or float(ship.fireControl.heat)<=0.0:continue
			var id:String=ship.id
			if live_ids.has(id):continue
			if not _live.has(id):
				if _live.size()>=MAX_LIVE_FIRES:continue
				_episode+=1
				_live[id]={"heat":float(ship.fireControl.heat),"episode":_episode,"slot":-1,"available":false,"anchor_time":-1.0,"point":Vector3.ZERO}
			var row:Dictionary=_live[id]
			row.heat=float(ship.fireControl.heat)
			if float(row.anchor_time)!=_time:row.available=false
			live_ids[id]=true
	for id:String in _live.keys():
		if not live_ids.has(id):_live.erase(id)
	_render()

func refresh_anchors()->void:
	super.refresh_anchors()
	if not _ready_state or not _enabled or not _anchor_provider.is_valid():return
	for id:String in _live:
		var row:Dictionary=_live[id]
		row.available=false
		var source:Variant=_anchor_provider.call(id)
		if not source is Dictionary or not _number(source.get("time")) or float(source.time)!=_time or str(source.get("shipId",""))!=id:continue
		var point:Variant=_point(source.get("position"))
		if not point is Vector3 or not _water.is_valid():continue
		var height:Variant=_water.call(point.x,point.z,_time)
		if not _number(height) or point.y<=float(height):continue
		row.available=true;row.point=point;row.anchor_time=_time
		var slot:int=int(floor(_time/EMISSION_SECONDS+0.00000001))
		if slot==int(row.slot):continue
		row.slot=slot
		var token:String="live:"+id+":"+str(row.episode)+":"+str(slot)
		var strength:float=clampf(float(row.heat)/100.0,0.0,1.0)
		for index in 3:
			var phase:float=float(absi((token+str(index)).hash())%6283)/1000.0
			var offset:=Vector3(sin(phase)*.45,.15,cos(phase)*.45)
			var velocity:=Vector3(sin(phase)*.25,1.1+strength,cos(phase)*.25)
			_add(token+":smoke:"+str(index),"smoke",_time,6.0,point+offset,velocity,1.1+strength*1.8,.65,Color(.34,.32,.28,.22+strength*.22))
		for index in 4:
			var offset:=Vector3(sin(index*1.7)*.65,.2,cos(index*1.7)*.55)
			_add(token+":flame:"+str(index),"flame",_time,.5,point,Vector3.ZERO,1.8+strength*2.5,0.0,Color(1,.75,.38,.8),{"living_ship":id,"living_offset":offset,"wind":Vector3.ZERO})
	_render()

func _sample(item:Dictionary)->Dictionary:
	if not item.has("living_ship"):return super._sample(item)
	var id:String=item.living_ship
	if not _live.has(id):return {}
	var row:Dictionary=_live[id]
	if not row.available or float(row.anchor_time)!=_time:return {}
	var sample:Dictionary=super._sample(item)
	if sample.is_empty():return {}
	var phase:float=float(item.phase)
	var point:Vector3=row.point+item.living_offset
	point.x+=sin(_time*7.0+phase)*.12
	point.y+=sin(_time*9.0+phase)*.12
	sample.position=[point.x,point.y,point.z]
	sample.size*=.9+.1*sin(_time*11.0+phase)
	sample.alpha*=clampf(float(row.heat)/28.0,0.0,1.0)
	return sample

func diagnostics()->Dictionary:
	var result:Dictionary=super.diagnostics()
	result.living_fires=_live.size()
	result.live_emission_policy="current accepted observed pose; no historical frame-gap backfill"
	return result

func _clear_timeline()->void:
	super._clear_timeline()
	_live.clear();_episode=0
