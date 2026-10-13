extends SceneTree
## Actual configured surf/native curves/material output first; allocation RED
## uses object identity, with no new production diagnostic API or time threshold.
const Surf=preload("res://modules/scene_engine/terrain/natural_shore_surf.gd")
const Field=preload("res://modules/scene_engine/terrain/natural_island_field.gd")
const Source=preload("res://modules/scene_engine/fidelity_island/mesh_asset.gd")
const Authored=preload("res://modules/scene_engine/fidelity_island/shore.gd")
const Native=preload("res://modules/scene_engine/fidelity_island/native_math.gd")
var assertions:=0
var failures:=0
func _initialize()->void:_run.call_deferred()
func check(ok:bool,reason:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL shore state reuse: ",reason)
func _bits(value:float)->int:
	var bytes:=PackedByteArray();bytes.resize(4);bytes.encode_float(0,value);return bytes.decode_u32(0)
func _basis_bytes(basis:Basis)->PackedByteArray:
	return PackedFloat32Array([basis.x.x,basis.x.y,basis.x.z,basis.y.x,basis.y.y,basis.y.z,basis.z.x,basis.z.y,basis.z.z]).to_byte_array()
func _oracle(surf:Node3D,source:Dictionary,seconds:float)->bool:
	var info:Dictionary=surf.diagnostics()
	if info.time!=seconds or info.states.size()!=info.packets.size():return false
	for i in info.packets.size():
		var packet:Dictionary=info.packets[i]
		var time:float=seconds*packet.clockSpeed+packet.clockOffset
		var mesh:Dictionary=source.meshes[int(packet.sourceIndex)]
		var expected:Dictionary=Authored.authored_state(mesh,source.curves,time)
		var clock:=Native.ControllerClock.new(mesh.controllers.alpha)
		var mapped:float=clock.advance(time)
		var phase:float=(mapped-float(mesh.controllers.alpha.start_time))/(float(mesh.controllers.alpha.stop_time)-float(mesh.controllers.alpha.start_time))
		var envelope:float=smoothstep(0.07,0.29,phase)*(1.0-smoothstep(0.32,0.88,phase))
		var alpha:float=clampf(expected.alpha,0.0,1.0)*envelope*Surf.DISPLAY_ALPHA_PEAK
		var state:Dictionary=info.states[i]
		for key:String in ["translationU","scaleU","alpha"]:
			if _bits(state[key])!=_bits(expected[key]):return false
		var extent:Vector4=packet.uvBounds
		var front:float=float(packet.offshoreStart)+float(packet.span)*(extent.z-(0.5+expected.translationU+0.25/expected.scaleU))/(extent.z-extent.x)
		if state.frontDistance!=front or state.nativeFrontDistance!=front or state.nativeAlpha!=expected.alpha or state.visibleAlpha!=alpha or state.lifeEnvelope!=envelope or state.lifePhase!=phase or state.packetTime!=time or state.sourceIndex!=packet.sourceIndex or state.pairId!=packet.pairId:return false
		var material:ShaderMaterial=surf.get_child(i).material_override
		if _basis_bytes(material.get_shader_parameter("texture_matrix"))!=Native.texture_transform(mesh.texture,expected).to_byte_array():return false
		if material.get_shader_parameter("controller_alpha")!=alpha or material.get_shader_parameter("packet_u_metres")!=float(packet.span)/(extent.z-extent.x)/float(expected.scaleU):return false
	return true
func _run()->void:
	var source:Dictionary=Source.read_json("res://assets/data/fidelity_island/shore-scene.json")
	var field:=Field.new();check(field.configure({"resolution":65}),"actual accepted triangle terrain configures")
	var surf:=Surf.new();root.add_child(surf);check(surf.configure(field),"actual source-textured packets configures")
	var initial:Dictionary=surf.diagnostics()
	var detached_initial:Dictionary=initial.duplicate(true)
	check(initial.patchCount>16 and initial.states.size()==initial.patchCount,"every original seeded patch has initial native state")
	check(_oracle(surf,source,0.0),"baseline real t0 source bits/matrix/front/envelope and material outputs agree before allocation RED")
	var states:Array=surf.get("_states").duplicate()
	var meshes:Array=[];var materials:Array=[]
	for node:MeshInstance3D in surf.get_children():meshes.append(node.mesh);materials.append(node.material_override)
	var all_reused:=true
	for seconds:float in [0.000001,0.2,12.0,12.000000001,29.966665,29.96666717529297,30.0,60.0,6.0,0.0,18000.0]:
		surf.apply_snapshot({"time":seconds},0.0)
		check(_oracle(surf,source,seconds),"changed native time retains exact independent source/material outputs: "+str(seconds))
		var current:Array=surf.get("_states")
		all_reused=all_reused and current.size()==states.size()
		for i in mini(current.size(),states.size()):all_reused=all_reused and is_same(states[i],current[i])
		var paused:Dictionary=surf.diagnostics()
		surf.apply_snapshot({"time":seconds,"focus":Vector2(1000,-250)},20.0)
		check(surf.diagnostics().states==paused.states,"same-time focus/delta never advances controller samples")
	check(all_reused,"one owner state Dictionary per patch is reused across native time changes; fresh per-patch allocations are RED")
	check(initial==detached_initial,"old public diagnostics stay detached from reused mutable internal states")
	var before_invalid:Dictionary=surf.diagnostics();surf.apply_snapshot({"time":NAN},0.0)
	check(surf.diagnostics()==before_invalid,"invalid time preserves accepted output")
	var identities:=true
	for i in surf.get_child_count():
		var node:MeshInstance3D=surf.get_child(i)
		identities=identities and node.mesh==meshes[i] and node.material_override==materials[i]
	check(identities and surf.diagnostics().geometryBuilds==initial.geometryBuilds and surf.diagnostics().packets==initial.packets,"state reuse preserves exact source population, mesh/material identity and clocks")
	surf.dispose();check(surf.get_child_count()==0,"dispose releases configured source patches")
	check(surf.configure(field) and _oracle(surf,source,0.0),"reconfigure restarts identical native t0 outputs")
	surf.dispose();surf.free()
	print("NATURAL_SHORE_STATE_REUSE_TESTS assertions=",assertions," failures=",failures," baselinePatches=",initial.patchCount)
	quit(1 if failures else 0)
