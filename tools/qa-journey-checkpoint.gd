extends RefCounted
## Mirrors reviewed capture material checks. Pure reads; never repairs state.
const Codec = preload("res://game/domain/persistence/save_codec.gd")
static func differences(before: Variant, after: Variant, path: String = "state") -> Array:
	var result: Array = []
	if before is Dictionary and after is Dictionary:
		var keys: Array = before.keys()
		for key: String in after:
			if not key in keys: keys.append(key)
		for key: String in keys:
			if not before.has(key) or not after.has(key): result.append({"path":path+"."+key,"beforeExists":before.has(key),"afterExists":after.has(key),"before":before.get(key),"after":after.get(key)})
			else: result.append_array(differences(before[key],after[key],path+"."+key))
	elif before is Array and after is Array:
		if before.size()!=after.size(): result.append({"path":path,"before":before,"after":after})
		else:
			for index in before.size(): result.append_array(differences(before[index],after[index],path+"["+str(index)+"]"))
	elif not Codec._equal(before,after): result.append({"path":path,"before":before,"after":after})
	return result
static func assess(before: Dictionary, after: Dictionary) -> Dictionary:
	var violations: Array = []
	if before.keys()!=after.keys(): violations.append("campaign field membership")
	for field: String in before:
		if field in ["revision","nextId","nearTicks","vessels"]: continue
		if not Codec._equal(before[field],after.get(field)): violations.append("state."+field)
	for field: String in ["revision","nextId"]:
		if after.get(field,-1)<before.get(field,0): violations.append("state."+field+" decreased")
	for epoch: String in before.nearTicks:
		if not Codec._equal(before.nearTicks[epoch],after.nearTicks.get(epoch)): violations.append("state.nearTicks."+epoch)
	if before.vessels.keys()!=after.vessels.keys(): violations.append("vessel membership")
	for id: String in before.vessels:
		var old: Dictionary = before.vessels[id]
		var now: Dictionary = after.vessels.get(id,{})
		if old.keys()!=now.keys(): violations.append("state.vessels."+id+" field membership")
		for field: String in old:
			if field in ["revision","controlsProjection","controlsObserved"]: continue
			if field=="pose" and old.pose is Dictionary and now.get("pose") is Dictionary:
				if not Codec._equal(old.pose.position,now.pose.position) or old.pose.heading!=now.pose.heading or absf(float(old.pose.speed)-float(now.pose.speed))>=1e-8: violations.append("state.vessels."+id+".pose")
			elif not Codec._equal(old[field],now.get(field)): violations.append("state.vessels."+id+"."+field)
	return {"ok":violations.is_empty(),"violations":violations,"differences":differences(before,after),"allowedOwnerChanges":["campaign revision","native epoch allocation nextId","new nearTicks epochs; old epochs exact","vessel revision","vessel controlsProjection","vessel controlsObserved","pose speed native roundoff below 1e-8; position and heading exact"]}
