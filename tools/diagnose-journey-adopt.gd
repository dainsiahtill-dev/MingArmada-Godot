extends SceneTree
## Detached zero-advance adoption only. Immutable historical source; no Storage.
const Runtime = preload("res://game/runtime/mingqi_runtime.gd")
const Codec = preload("res://game/domain/persistence/save_codec.gd")
const Height = preload("res://modules/scene_engine/terrain/height_field.gd")
const Layout = preload("res://game/scenes/common/reference_geography.gd")
const CheckpointAudit = preload("res://tools/qa-journey-checkpoint.gd")
const INPUT := "res://docs/migration/evidence/opening-story/journey-formal-manual-fire-return.json"
const OUTPUT := "res://build/port-approach-work/qa-tooling-adopt-diagnostic.json"
var runtime := Runtime.new()
var assertions := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> bool:
	assertions+=1
	if not value: failures+=1; printerr("FAIL: ",label)
	return value
func run() -> void:
	if not check(not FileAccess.file_exists(OUTPUT),"fresh build diagnostic output"): runtime.dispose(); quit(1); return
	var source := FileAccess.get_file_as_string(INPUT)
	var record: Dictionary = JSON.parse_string(source)
	var checkpoint: String = record.confirmedCheckpointJson
	var decoded: Dictionary = Codec.decode(checkpoint)
	if not check(decoded.get("ok",false) and Codec._equal(decoded.get("state"),record.final.campaign),"original raw full-precision checkpoint equals immutable first final exactly"): runtime.dispose(); quit(1); return
	var height := Height.new()
	check(height.configure_ports(JSON.parse_string(FileAccess.get_file_as_string("res://game/data/mingqi_geography.json")),true,Layout.options()),"formal geography")
	runtime.enable_reference_enhancements()
	check(runtime.configure(height.sample_height).get("ok",false),"native configure")
	var adopted: Dictionary = runtime.adopt_save(checkpoint,null)
	check(adopted.get("ok",false),"normal native adoption")
	var packet: Dictionary = runtime.snapshot()
	var audit: Dictionary = CheckpointAudit.assess(decoded.state,packet.campaign)
	check(audit.ok,"exact material campaign preserved")
	check(packet.campaign.simulationSeconds==decoded.state.simulationSeconds and packet.runtime.acceptedSeconds==0.0,"zero accepted native advance")
	check(FileAccess.get_file_as_string(INPUT)==source,"historical input byte exact")
	var result: Dictionary = {"mode":"headless detached normal adoption diagnosis only; zero runtime.advance calls; no convoy acceptance, Storage, GPU or performance claim","journeyPath":INPUT,"journeySha256":source.sha256_text(),"rawCheckpointSha256":checkpoint.sha256_text(),"rawCheckpointEqualsFirstFinalExactly":Codec._equal(decoded.state,record.final.campaign),"rawCheckpointEqualsPostAdoptExactly":Codec._equal(decoded.state,packet.campaign),"materialAudit":audit,"preacceptCampaign":packet.campaign,"nativeAcceptedSeconds":packet.runtime.acceptedSeconds,"assertions":assertions,"failures":failures}
	var file := FileAccess.open(OUTPUT,FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify(result,"\t",false,true)); file.close()
	else: failures+=1
	runtime.dispose()
	print("JOURNEY_ADOPT_DIAGNOSTIC assertions=",assertions," failures=",failures," differences=",audit.differences.size()," acceptedSeconds=",packet.runtime.acceptedSeconds)
	quit(1 if failures else 0)
