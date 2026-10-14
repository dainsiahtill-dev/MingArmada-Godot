extends "res://tools/shadow_candidate_probe.gd"
## Single-factor actual GPU candidate. Every caster stays; only near-cap indices flip.
class CapWindingBackend extends "res://modules/scene_engine/fidelity_fx/source_shadow_rd.gd":
	const Candidate=preload("res://game/research/shadow_cap_winding_candidate.gd")
	var mesh_calls:=0
	var altered_calls:=0
	var rejected_calls:=0
	var cap_triangles:=0
	var _converted:Dictionary={}
	var _records:Dictionary={}
	static func digest(value:Variant)->String:
		var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(var_to_bytes(value));return hash.finish().hex_encode()
	func _mesh_record(volume:Dictionary,retained:Dictionary)->Dictionary:
		mesh_calls+=1
		var key:=str(volume.get("id",""))+":"+str(volume.get("geometryRevision",-1))
		if not _converted.has(key):
			var converted:Dictionary=Candidate.adapt(volume.geometry)
			_converted[key]=converted
			var record:={"id":volume.get("id",""),"geometryRevision":volume.get("geometryRevision",-1),"ok":converted.ok,"reason":converted.reason,"sourceIndicesSHA256":digest(volume.geometry.indices)}
			if converted.ok:
				record.sideTriangles=converted.sideTriangles;record.capTriangles=converted.capTriangles
				record.candidateIndicesSHA256=digest(converted.geometry.indices)
				record.positionsSharedUnchanged=is_same(converted.geometry.positions,volume.geometry.positions)
				record.directionUnchanged=converted.geometry.direction==volume.geometry.direction
				cap_triangles+=converted.capTriangles
			_records[key]=record
		var converted:Dictionary=_converted[key]
		if not converted.ok:rejected_calls+=1;return super._mesh_record(volume,retained)
		if converted.capTriangles>0:altered_calls+=1
		var changed:Dictionary=volume.duplicate(false);changed.geometry=converted.geometry
		return super._mesh_record(changed,retained)
	func candidate_diagnostics()->Dictionary:
		return {"mode":"near-cap-winding-only","meshCalls":mesh_calls,"alteredCalls":altered_calls,"rejectedCalls":rejected_calls,"uniqueGeometry":_converted.size(),"uniqueCapTrianglesFlipped":cap_triangles,"vertexSHA256":VERTEX_SOURCE.sha256_text(),"fragmentSHA256":FRAGMENT_SOURCE.sha256_text(),"records":_records.values().duplicate(true)}
func _initialize()->void:
	output="res://docs/research/evidence/shadow-edges/cap-winding-candidate"
	super._initialize()
func _make_backend()->RefCounted:return CapWindingBackend.new()
