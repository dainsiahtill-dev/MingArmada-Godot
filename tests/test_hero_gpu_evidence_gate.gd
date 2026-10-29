extends SceneTree
## Use two real archived GPU status snapshots; perturb failure cases so the
## evidence gate cannot confuse a callback/quad with geometry contribution.
const GATE_PATH="res://tools/research/hero_gpu_evidence_gate.gd"
const FIXTURE="res://docs/research/evidence/hero-fuchuan/rig-frequency-20261026/r8b-stage-candidate-01/LIGHT_STUDY.json"
var assertions:=0
var failures:=0

func _initialize() -> void: run.call_deferred()
func check(ok: bool, detail: String) -> void:
	assertions+=1
	if not ok: failures+=1;printerr("FAIL: ",detail)

func run() -> void:
	var fixture: Variant=JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	check(fixture is Dictionary and fixture.valid and fixture.captures.size()==3,"real archived GPU evidence is available")
	check(ResourceLoader.exists(GATE_PATH),"verifier exposes its actual compositor evidence gate")
	if fixture is Dictionary and fixture.valid and fixture.captures.size()==3 and ResourceLoader.exists(GATE_PATH):
		var verifier = load(GATE_PATH).new()
		var before: Dictionary=fixture.captures[1].inputs.shadowDiagnostics
		var after: Dictionary=fixture.captures[2].inputs.shadowDiagnostics
		# JSON number parsing yields floats; the actual live diagnostics expose
		# integer counters. Restore their documented runtime types for this test.
		for status: Dictionary in [before,after]:
			status.renderer.volumeCount=int(status.renderer.volumeCount)
			status.adapter.activeCasters=int(status.adapter.activeCasters)
			for key: String in ["frames","draws","cachedMeshes"]: status.renderer.gpu[key]=int(status.renderer.gpu[key])
		check(verifier.shadow_evidence(before,after).ok,"real progressing initialized compositor is accepted")
		var bad: Dictionary=after.duplicate(true)
		bad.renderer.gpu.initialized=false
		check(not verifier.shadow_evidence(before,bad).ok,"uninitialized native fallback is rejected")
		bad=after.duplicate(true);bad.renderer.gpu.error="pipeline failure"
		check(not verifier.shadow_evidence(before,bad).ok,"compositor error is rejected")
		bad=after.duplicate(true);bad.renderer.errors=["bad geometry"]
		check(not verifier.shadow_evidence(before,bad).ok,"renderer errors are rejected")
		bad=after.duplicate(true);bad.adapter.errors=["bad caster"]
		check(not verifier.shadow_evidence(before,bad).ok,"caster errors are rejected")
		bad=after.duplicate(true);bad.renderer.gpu.frames=before.renderer.gpu.frames
		check(not verifier.shadow_evidence(before,bad).ok,"stale GPU frame counter is rejected")
		bad=after.duplicate(true);bad.renderer.gpu.draws=before.renderer.gpu.draws+1
		check(not verifier.shadow_evidence(before,bad).ok,"a fullscreen quad without caster geometry is rejected")
		bad=after.duplicate(true);bad.renderer.gpu.draws=before.renderer.gpu.draws+(bad.renderer.gpu.frames-before.renderer.gpu.frames)
		check(not verifier.shadow_evidence(before,bad).ok,"several quad-only callbacks cannot impersonate caster geometry")
		bad=after.duplicate(true);bad.renderer.volumeCount=0
		check(not verifier.shadow_evidence(before,bad).ok,"empty volume submission is rejected")
		bad=after.duplicate(true);bad.renderer.gpu.cachedMeshes=0
		check(not verifier.shadow_evidence(before,bad).ok,"missing GPU caster meshes are rejected")
		bad=after.duplicate(true);bad.adapter.activeCasters=0
		check(not verifier.shadow_evidence(before,bad).ok,"missing target rigid casters are rejected")
	print("HERO_GPU_EVIDENCE_GATE assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
