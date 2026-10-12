extends SceneTree
## Actual corrected captain command from immutable new first checkpoint.
## Detached Runtime only; no advance, voyage, Storage or historical writes.
const Codec = preload("res://game/domain/persistence/save_codec.gd")
const Height = preload("res://modules/scene_engine/terrain/height_field.gd")
const Layout = preload("res://game/scenes/common/reference_geography.gd")
const Audit = preload("res://tools/qa-journey-checkpoint.gd")
const FIRST := "res://docs/migration/evidence/opening-story/port-approach-and-voyage-clarity/journey-first.json"
const FAILED := "res://docs/migration/evidence/opening-story/port-approach-and-voyage-clarity/journey-second.json"
var assertions := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	assertions+=1
	if not value: failures+=1; printerr("FAIL: ",label)
func run() -> void:
	var first_hash := FileAccess.get_sha256(FIRST)
	var failed_hash := FileAccess.get_sha256(FAILED)
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIRST))
	var decoded: Dictionary = Codec.decode(record.confirmedCheckpointJson)
	check(decoded.get("ok",false) and Codec._equal(decoded.get("state"),record.final.campaign),"immutable first raw checkpoint exactly equals actual first final")
	var captain = load("res://tools/play-continued-voyage.gd").new()
	var height := Height.new()
	check(height.configure_ports(JSON.parse_string(FileAccess.get_file_as_string("res://game/data/mingqi_geography.json")),true,Layout.options()),"same formal geography")
	captain.runtime.enable_reference_enhancements()
	check(captain.runtime.configure(height.sample_height).get("ok",false),"isolated real captain runtime configures")
	check(captain.runtime.adopt_save(record.confirmedCheckpointJson,null).get("ok",false),"normal strict raw checkpoint adoption")
	var before: Dictionary = captain.runtime.snapshot()
	var material: Dictionary = Audit.assess(decoded.state,before.campaign)
	check(material.ok,"exact preaccept material preserved with owner stamps recorded")
	captain.runtime.set_pause("loading",false)
	var receipt: Dictionary = captain.command("accept-convoy",{"contractId":"convoy-002"})
	var input_keys: Array = []
	for key in captain.commands[0].input: input_keys.append({"key":str(key),"type":type_string(typeof(key))})
	print("CONTINUED_ACCEPT_INPUT_KEYS ",JSON.stringify(input_keys))
	check(Codec.command_data(captain.commands[0].input),"actual command uses strict Codec-supported key types")
	check(typeof(captain.commands[0].input.expectedRevision)==TYPE_INT,"actual driver casts expectedRevision to integer")
	check(receipt.get("ok",false),"actual driver real twenty-grain acceptance succeeds")
	var after: Dictionary = captain.runtime.snapshot()
	var load_receipt: Dictionary = after.campaign.settlements.get(after.campaign.campaignId+"-convoy-002-accept",{})
	check(load_receipt.get("details",{}).get("loaded")==20 and load_receipt.get("details",{}).get("leasePaid")==0,"actual authority loads twenty without another lease")
	check(after.campaign.ports.kinmen.stock.grain==before.campaign.ports.kinmen.stock.grain-20 and after.campaign.captain.silver==before.campaign.captain.silver,"real source stock deducted; silver unchanged")
	check(after.campaign.contracts["convoy-002"].deadlineAt==before.campaign.simulationSeconds+1200,"original actual deadline retained")
	check(after.runtime.acceptedSeconds==0.0 and after.campaign.simulationSeconds==before.campaign.simulationSeconds,"no accepted simulation advancement")
	check(FileAccess.get_sha256(FIRST)==first_hash and FileAccess.get_sha256(FAILED)==failed_hash,"actual first and failed second evidence remain byte exact")
	var path := "res://build/port-approach-work/qa-continued-accept-regression-"+str(OS.get_process_id())+".json"
	check(not FileAccess.file_exists(path),"fresh build-only regression record")
	var result: Dictionary = {"mode":"detached real normal adoption and actual QA command acceptance only; no advance, voyage, Storage or GPU","firstJourneySha256":first_hash,"failedSecondJourneySha256":failed_hash,"driverSourceSha256":FileAccess.get_sha256("res://tools/play-continued-voyage.gd"),"materialAudit":material,"command":captain.commands[0],"inputKeyTypes":input_keys,"before":before.campaign,"after":after.campaign,"acceptedSeconds":after.runtime.acceptedSeconds,"assertions":assertions,"failures":failures}
	var bytes := JSON.stringify(result,"\t",false,true)
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file!=null:
		file.store_string(bytes); file.flush(); check(file.get_error()==OK,"regression record flushed"); file.close()
		check(FileAccess.get_file_as_string(path)==bytes,"regression bytes exact readback")
	else: check(false,"regression output opens")
	captain.runtime.dispose(); captain.free()
	print("CONTINUED_ACCEPT_REGRESSION assertions=",assertions," failures=",failures," acceptedSeconds=",after.runtime.acceptedSeconds," output=",path)
	quit(1 if failures else 0)
