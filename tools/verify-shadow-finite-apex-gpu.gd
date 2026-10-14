extends "res://tools/shadow_candidate_probe.gd"
## One factor diagnostic: finite 10000-world-metre GPU apex; original Math untouched.
class FiniteApexBackend extends "res://modules/scene_engine/fidelity_fx/source_shadow_rd.gd":
	var mesh_calls:=0
	var altered_apices:=0
	var max_before_world:=0.0
	var max_after_world:=0.0
	func _mesh_record(volume:Dictionary,retained:Dictionary)->Dictionary:
		mesh_calls+=1
		var changed:Dictionary=volume.duplicate(false)
		var geometry:Dictionary=volume.geometry
		if geometry.positions.size()>1:
			var apex:Array=geometry.positions[0];var anchor:Array=geometry.positions[1]
			var a:=Vector3(apex[0],apex[1],apex[2]);var origin:=Vector3(anchor[0],anchor[1],anchor[2])
			if a.distance_to(origin)>1000000.0:
				var direction:=Vector3(geometry.direction[0],geometry.direction[1],geometry.direction[2]).normalized()
				var transform:Transform3D=volume.get("transform",Transform3D.IDENTITY)
				var metres_per_unit:float=(transform.basis*direction).length()
				if metres_per_unit>0.0000001:
					altered_apices+=1;max_before_world=maxf(max_before_world,(transform.basis*(a-origin)).length())
					var candidate:=origin+direction*(10000.0/metres_per_unit)
					max_after_world=maxf(max_after_world,(transform.basis*(candidate-origin)).length())
					changed.geometry=geometry.duplicate(false);changed.geometry.positions=geometry.positions.duplicate(false)
					changed.geometry.positions[0]=[candidate.x,candidate.y,candidate.z]
		return super._mesh_record(changed,retained)
	func candidate_diagnostics()->Dictionary:return {"mode":"finite-apex-10000-world-metres","meshCalls":mesh_calls,"alteredApices":altered_apices,"maxBeforeWorld":max_before_world,"maxAfterWorld":max_after_world,"vertexSHA256":VERTEX_SOURCE.sha256_text(),"fragmentSHA256":FRAGMENT_SOURCE.sha256_text()}
func _initialize()->void:
	output="res://docs/research/evidence/shadow-edges/finite-apex-candidate"
	super._initialize()
func _make_backend()->RefCounted:return FiniteApexBackend.new()
