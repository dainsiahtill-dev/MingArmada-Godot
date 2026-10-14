extends "res://tools/shadow_candidate_probe.gd"
## Parked single-factor GPU candidate: append only the isolated missing sides.
## All other caster packets, original triangles, cap winding and shaders stay.
class DirectedBoundaryBackend extends "res://modules/scene_engine/fidelity_fx/source_shadow_rd.gd":
	const Candidate=preload("res://game/research/shadow_directed_boundary_candidate.gd")
	const CASTER_ID="player:native_hull_56_component_03"
	var mesh_calls:=0
	var target_calls:=0
	var altered_calls:=0
	var rejected_calls:=0
	var _converted:Dictionary={}
	var _records:Dictionary={}
	static func digest(value:Variant)->String:
		var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(var_to_bytes(value));return hash.finish().hex_encode()
	func _mesh_record(volume:Dictionary,retained:Dictionary)->Dictionary:
		mesh_calls+=1
		if volume.get("id","")!=CASTER_ID:return super._mesh_record(volume,retained)
		target_calls+=1
		var key:=str(volume.id)+":"+str(volume.get("geometryRevision",-1))
		if not _converted.has(key):
			var changed:Dictionary=Candidate.adapt(volume.geometry);_converted[key]=changed
			var record:={"id":volume.id,"geometryRevision":volume.get("geometryRevision",-1),"ok":changed.ok,"sourceIndicesSHA256":digest(volume.geometry.indices),"sourcePositionsSHA256":digest(volume.geometry.positions)}
			if changed.ok:
				record.addedSides=changed.addedSides;record.missing=changed.missing
				record.candidateIndicesSHA256=digest(changed.geometry.indices);record.candidatePositionsSHA256=digest(changed.geometry.positions)
				record.originalIndicesUnchanged=changed.geometry.indices.slice(0,volume.geometry.indices.size())==volume.geometry.indices
				record.originalPositionsUnchanged=changed.geometry.positions.slice(0,volume.geometry.positions.size())==volume.geometry.positions
				record.directionUnchanged=changed.geometry.direction==volume.geometry.direction
			else:record.reason=changed.reason
			_records[key]=record
		var changed:Dictionary=_converted[key]
		if not changed.ok:rejected_calls+=1;return super._mesh_record(volume,retained)
		if changed.addedSides>0:altered_calls+=1
		var packet:Dictionary=volume.duplicate(false);packet.geometry=changed.geometry
		return super._mesh_record(packet,retained)
	func candidate_diagnostics()->Dictionary:
		return {"mode":"isolated-caster-missing-directed-sides-only","caster":CASTER_ID,"meshCalls":mesh_calls,"targetCalls":target_calls,"alteredCalls":altered_calls,"rejectedCalls":rejected_calls,"vertexSHA256":VERTEX_SOURCE.sha256_text(),"fragmentSHA256":FRAGMENT_SOURCE.sha256_text(),"candidateSHA256":FileAccess.get_sha256("res://game/research/shadow_directed_boundary_candidate.gd"),"driverSHA256":FileAccess.get_sha256("res://tools/verify-shadow-directed-boundary-gpu.gd"),"records":_records.values().duplicate(true)}
func _initialize()->void:
	output="res://docs/research/evidence/shadow-edges/directed-boundary-candidate"
	super._initialize()
func _make_backend()->RefCounted:return DirectedBoundaryBackend.new()
