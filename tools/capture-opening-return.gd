extends SceneTree
## Capture a genuine completed journey through strict native Continue and mouse UI.
## No campaign repair, teleport, cargo/health/history edit or save safety bypass.
const Router = preload("res://game/runtime/game_router.gd")
const Storage = preload("res://game/persistence/save_coordinator.gd")
const Settings = preload("res://game/persistence/user_settings.gd")
const Legacy = preload("res://game/runtime/legacy_runtime.gd")
const Runtime = preload("res://game/runtime/mingqi_runtime.gd")
const Codec = preload("res://game/domain/persistence/save_codec.gd")
const Story = preload("res://game/domain/mingqi/opening_story.gd")
const Height = preload("res://modules/scene_engine/terrain/height_field.gd")
const Layout = preload("res://game/scenes/common/reference_geography.gd")
const SOURCE_PATHS = ["tools/capture-opening-return.gd", "tools/play-opening-story-journey.gd", "game/scenes/main/main_scene.gd", "game/runtime/game_router.gd", "game/persistence/save_coordinator.gd", "game/domain/mingqi/opening_story.gd", "game/domain/mingqi/campaign.gd", "game/domain/persistence/save_codec.gd", "game/runtime/mingqi_runtime.gd", "game/runtime/near_field_bridge.gd", "game/runtime/native_readiness.gd", "game/runtime/sailing_simulation.gd", "game/ui/mingqi/mingqi_interface.gd", "game/ui/menu/main_menu.gd", "game/scenes/mingqi/mingqi_scene.gd", "modules/contracts/navigation_contract.gd", "modules/naval_simulation/encounter.gd", "modules/naval_simulation/combat/cannon_system.gd", "modules/naval_simulation/tactics/order_controller.gd", "game/data/mingqi_geography.json", "game/scenes/common/reference_geography.gd", "project.godot"]
var assertions := 0
var failures := 0
var errors: Array[String] = []
var captures: Array[Dictionary] = []
var main: Node
var scene: Node
var journey_path := ""
var directory := ""
var isolated_prefix := ""
var source_campaign: Dictionary = {}
var source_record: Dictionary = {}
var source_hashes: Dictionary = {}
var original_slots: Dictionary = {}
var summary: Dictionary = {}
var saved_json := ""
var preflight_only := false
var save_readback := false
var output_owned := false
var isolated_owned := false

class PresenterProbe extends Node:
	const Interface = preload("res://game/ui/mingqi/mingqi_interface.gd")
	const Overlay = preload("res://game/scenes/common/sea_chart_overlay.gd")
	var interface := Interface.new()
	var minimap := Overlay.new()
	var presentations := 0
	func _present(_delta: float) -> void:
		presentations += 1
		minimap.present({"ships": []}, {}, interface.is_panel_open())

func _initialize() -> void:
	if "--self-test" in OS.get_cmdline_user_args(): _guard_tests.call_deferred()
	else: run.call_deferred()

func check(value: bool, detail: String) -> bool:
	assertions += 1
	if not value:
		failures += 1
		errors.append(detail)
		printerr("FAIL: ", detail)
	return value

func journey_failure(record: Variant) -> String:
	if not record is Dictionary: return "journey-not-object"
	if not record.has("failures") or not record.failures is int and not record.failures is float or record.failures != 0: return "journey-has-failures"
	if not record.get("actualSafeReturn") is bool or record.actualSafeReturn != true: return "journey-safe-return-unconfirmed"
	if not record.get("final") is Dictionary or not record.final.get("campaign") is Dictionary: return "journey-final-campaign-missing"
	var state: Dictionary = record.final.campaign
	if state.get("currentPortId") != "kinmen": return "journey-not-at-kinmen"
	var flag: Dictionary = state.get("vessels", {}).get(state.get("flagshipId", ""), {})
	if float(flag.get("damage", {}).get("hull", 0)) <= 0: return "journey-flagship-unavailable"
	var first: Dictionary = state.get("contracts", {}).get("convoy-001", {})
	if first.get("status") != "settled": return "journey-first-convoy-unsettled"
	var cid := str(state.get("campaignId", ""))
	var claim: Dictionary = state.get("settlements", {}).get(cid + ":convoy-001:claim", {})
	if claim.get("kind") != "claim-convoy" or claim.get("details", {}).get("contractId") != "convoy-001" or float(claim.get("details", {}).get("delivered", 0)) <= 0: return "journey-first-convoy-receipt-missing"
	var receipt: Dictionary = state.get("settlements", {}).get(cid + ":story:first-return", {})
	var detail: Dictionary = receipt.get("details", {})
	if receipt.get("kind") != "story-choice" or detail.get("sceneId") != "first-return" or detail.get("portId") != "kinmen" or detail.get("convoyReceiptId") != claim.get("id"): return "journey-first-return-receipt-missing"
	if state.get("contracts", {}).get("convoy-002", {}).get("status") != "offered": return "journey-next-commission-not-offered"
	return str(transport_plan(state).get("reason", ""))

func transport_plan(state: Dictionary) -> Dictionary:
	var cid := str(state.get("campaignId", ""))
	var sunk := 0
	var surviving := 0
	var ids: Array[String] = []
	for suffix: String in ["grain-a", "grain-b"]:
		var vessel: Dictionary = state.get("vessels", {}).get(cid + "-" + suffix, {})
		if vessel.is_empty(): return {"ok": false, "reason": "journey-original-transport-missing"}
		if float(vessel.get("damage", {}).get("hull", 0)) <= 0: sunk += 1
		else:
			surviving += 1
			ids.append(cid + "-" + suffix)
	if surviving == 0: return {"ok": false, "reason": "journey-transports-sunk"}
	return {"ok": true, "sunk": sunk, "surviving": surviving, "shipIds": ids, "quantityPerShip": 20 if surviving == 1 else 10}

func frames(count: int = 5) -> void:
	for index in count: await process_frame

func file_hashes(paths: Array) -> Dictionary:
	var result: Dictionary = {}
	for path: String in paths:
		result[path] = {"exists": FileAccess.file_exists(path), "sha256": FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""}
	return result

func current_source_hashes() -> Dictionary:
	var result: Dictionary = {}
	for path: String in SOURCE_PATHS: result[path] = FileAccess.get_sha256("res://" + path)
	return result

func unchanged_sources() -> bool:
	return check(current_source_hashes() == source_hashes, "sources unchanged during capture") and check(FileAccess.get_sha256(journey_path) == summary.journeySha256, "immutable journey file unchanged")

func preserve_material(before: Dictionary, after: Dictionary, label: String, export_context: Dictionary = {}) -> bool:
	# Normal native restoration allocates an epoch and refreshes projection stamps.
	# Observe those owner changes; reject any material gameplay mutation.
	for field: String in ["campaignId", "seed", "randomState", "simulationSeconds", "macroRemainder", "macroSeconds", "clockCompensation", "calendar", "chapterId", "captain", "debt", "flagshipId", "currentPortId", "voyages", "ports", "orders", "contracts", "boardings", "works", "prizes", "casualtyOrdinals", "reputations", "people", "intelligence", "chronicle", "settlements"]:
		if not check(Codec._equal(before.get(field), after.get(field)), label + " preserves " + field): return false
	if not check(before.vessels.keys() == after.vessels.keys(), label + " preserves vessel membership"): return false
	for id: String in before.vessels:
		if not preserve_vessel(before.vessels[id], after.vessels[id], label + " preserves " + id, export_context): return false
	for epoch: String in before.nearTicks:
		if not check(after.nearTicks.get(epoch) == before.nearTicks[epoch], label + " preserves historical native epoch " + epoch): return false
	return true

func preserve_vessel(before: Dictionary, after: Dictionary, label: String, export_context: Dictionary = {}) -> bool:
	for field: String in before:
		if field in ["revision", "controlsProjection", "controlsObserved"]: continue
		if field == "representation" and allows_saved_ownership(before, after, export_context): continue
		var original: Variant = before[field]
		var observed: Variant = after.get(field)
		if field == "pose" and original is Dictionary and observed is Dictionary:
			if not check(Codec._equal(original.position, observed.position) and original.heading == observed.heading and absf(float(original.speed) - float(observed.speed)) < 1e-8, label + ".pose"): return false
		elif not check(Codec._equal(original, observed), label + "." + field): return false
	return true

func allows_saved_ownership(before: Dictionary, after: Dictionary, context: Dictionary) -> bool:
	if context.get("kind") != "normal-ui-save-checkpoint" or not context.get("safe", false) or context.get("portId") == null: return false
	if before.get("ownerId") != "enemy" or before.get("damage", {}).get("hull") != 0 or after.get("damage", {}).get("hull") != 0: return false
	if before.get("representation") != "near" or after.get("representation") != "route": return false
	if before.id in context.get("nativeIds", []) or before.id in context.get("capturedShipIds", []): return false
	if before.size() != after.size(): return false
	# This absent sunk enemy receives no native observations. Its exact complete
	# record must therefore differ in ownership representation alone, even stamps.
	for field: String in before:
		if not after.has(field) or field != "representation" and not Codec._equal(before[field], after[field]): return false
	return true

func focus_control(id: String) -> Control:
	var control: Control = scene.interface.find_child(id, true, false)
	if not check(control != null, "real native control exists: " + id): return null
	var parent: Node = control.get_parent()
	while parent:
		if parent is ScrollContainer: parent.ensure_control_visible(control)
		parent = parent.get_parent()
	await frames(3)
	control = scene.interface.find_child(id, true, false)
	if not check(control != null and control.is_visible_in_tree(), "native control visible: " + id): return null
	return control

func click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point; motion.global_position = point
	Input.parse_input_event(motion); await process_frame
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT; event.pressed = true; event.position = point; event.global_position = point
	Input.parse_input_event(event); await process_frame
	event = event.duplicate(); event.pressed = false
	Input.parse_input_event(event); await frames(4)

func button(id: String) -> bool:
	var control: Control = await focus_control(id)
	if not control: return false
	if not check(control is Button and not control.disabled, "real native button enabled: " + id): return false
	await click(control)
	if present_current_scene(): await frames(2)
	return true

func present_current_scene() -> bool:
	if not is_instance_valid(main) or not is_instance_valid(scene) or main.current_scene != scene: return false
	scene._present(0)
	return true

func casualty_consequence_matches(packet: Dictionary, text: String) -> bool:
	var state: Dictionary = packet.campaign
	var claim: Dictionary = state.settlements[state.campaignId + ":convoy-001:claim"]
	if claim.kind != "claim-convoy" or claim.details.contractId != "convoy-001" or claim.details.ships.is_empty(): return false
	var dead := 0; var wounded := 0
	for ship: Dictionary in claim.details.ships:
		dead += int(ship.dead); wounded += int(ship.wounded)
	var expected_relation := ""
	for relation: Dictionary in packet.story.relations:
		if relation.id == "xu-fu": expected_relation = "%s · %s\n%s" % [relation.name, relation.role, relation.stance]
	if expected_relation.is_empty() or text != expected_relation: return false
	var return_text := ""
	for chapter_scene: Dictionary in packet.story.scenes:
		if chapter_scene.id == "first-return": return_text = "\n".join(chapter_scene.text)
	if not return_text.contains("船员死亡%d人、伤员%d人" % [dead, wounded]): return false
	if dead > 0 or wounded > 0:
		return text.contains("死亡%d人" % dead) and text.contains("受伤%d人" % wounded)
	# Healthy wording is the production branch; its first-return projection still
	# reports 0/0. Verify actual receipt/current state, never invent duplicate UI.
	if text.contains("死亡") or text.contains("受伤") or text.contains("阵亡"): return false
	for person_id: String in ["steward-a", "steward-b"]:
		if not state.people.get(person_id, {}).get("alive", false): return false
		var alive_at_claim := false
		for person: Dictionary in claim.details.people:
			if person.personId == person_id: alive_at_claim = person.alive
		if not alive_at_claim: return false
	for ship: Dictionary in claim.details.ships:
		var vessel: Dictionary = state.vessels.get(ship.shipId, {})
		if vessel.is_empty() or vessel.damage.hull <= 0 or vessel.crew.wounded != 0 or state.casualtyOrdinals.get(ship.shipId, 0) != 0: return false
		var live: Dictionary = Runtime._ship(packet.naval, ship.shipId)
		if vessel.representation == "near" and (live.is_empty() or live.hull <= 0 or live.crew != vessel.crew.able): return false
	return true

func ui_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for node in scene.interface.find_children("*", "Control", true, false):
		if not (node is Label or node is Button): continue
		if not str(node.name).begins_with("story_") and not str(node.name).begins_with("contract_") and not str(node.name).begins_with("voyage_") and not str(node.name) in ["save_reason", "save_status", "depart_reason"]: continue
		var bounds: Rect2 = node.get_global_rect()
		result.append({"name": node.name, "text": node.text, "visible": node.is_visible_in_tree(), "rect": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y], "disabled": node.disabled if node is Button else null})
	return result

func capture(label: String, dimensions: Vector2i) -> bool:
	if not unchanged_sources(): return false
	if not check(present_current_scene(), "capture presents the actual active MainScene"): return false
	var panel_open: bool = scene.interface.is_panel_open() or scene.interface.is_menu_open()
	if panel_open and not check(scene.minimap != null and scene.minimap.chart != null and not scene.minimap.chart.visible, "open operation/menu panel hides actual compact chart: " + label): return false
	await frames(6); await RenderingServer.frame_post_draw
	var pixels: Image = root.get_texture().get_image()
	if not check(pixels != null and not pixels.is_empty(), "real GPU viewport has pixels: " + label): return false
	if not check(Vector2i(pixels.get_width(), pixels.get_height()) == dimensions, "actual screenshot dimensions: " + label): return false
	var destination := directory + "/" + label + ".png"
	if not check(pixels.save_png(destination) == OK, "actual GPU screenshot: " + label): return false
	var metadata: Dictionary = {"snapshot": scene.runtime.snapshot(), "ui": ui_snapshot(), "imageSha256": FileAccess.get_sha256(destination), "viewport": [pixels.get_width(), pixels.get_height()], "engine": Engine.get_version_info(), "gpu": RenderingServer.get_video_adapter_name(), "renderingMethod": RenderingServer.get_current_rendering_method(), "journey": summary.duplicate(true), "sourceHashes": source_hashes.duplicate(true), "scope": "Actual completed native captain-driver journey restored through MainScene Continue and strict native safety. Real mouse UI and Campaign transactions. This is automated native-game acceptance; no original-game footage, all-chapters, visual-equivalence or performance claim."}
	metadata.presentation = {"panelOpen": scene.interface.is_panel_open(), "menuOpen": scene.interface.is_menu_open(), "minimapVisible": scene.minimap.chart.visible}
	if not write_json(directory + "/" + label + ".json", metadata): return false
	captures.append({"label": label, "image": destination, "metadata": directory + "/" + label + ".json", "imageSha256": metadata.imageSha256})
	return true

func write_json(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not check(file != null, "metadata write: " + path): return false
	file.store_string(JSON.stringify(data, "\t")); file.flush()
	var okay := file.get_error() == OK
	file.close()
	return check(okay, "metadata flush: " + path)

func resume_entry() -> bool:
	for index in 600:
		if main.current_scene: break
		if main.recovery.visible or main.menu._phase == "error": break
		await process_frame
	if not check(main.current_scene != null, "MainScene strict Continue: " + str(main.router.recovery_snapshot().get("reason", main.menu._status.text))): return false
	scene = main.current_scene
	scene.set_process(false); scene.set_physics_process(false)
	if not check(scene.startup_receipt.get("ok", false), "real geography/native scene startup confirmed"): return false
	if not check(scene.runtime.check_safety().get("ok", false), "restored full native save safety: " + str(scene.runtime.check_safety().get("reason", ""))): return false
	return await button("menu_resume")

func run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--journey=") and journey_path.is_empty(): journey_path = argument.trim_prefix("--journey=")
		elif argument.begins_with("--output=") and directory.is_empty(): directory = argument.trim_prefix("--output=")
		elif argument == "--preflight-only": preflight_only = true
		elif argument == "--save-readback": save_readback = true
		else: check(false, "unknown or duplicate capture argument: " + argument)
	if not check(not journey_path.is_empty(), "explicit --journey= successful evidence required") or failures: await finish(); return
	if not check(FileAccess.file_exists(journey_path), "journey evidence exists: " + journey_path): await finish(); return
	var parser := Codec.new()
	var parsed: Variant = parser._parse(FileAccess.get_file_as_string(journey_path))
	if not check(parser.error.is_empty(), "input journey passes strict full-precision JSON parser: " + parser.error): await finish(); return
	var rejected := journey_failure(parsed)
	if not check(rejected.is_empty(), rejected): await finish(); return
	source_record = parsed
	source_campaign = source_record.final.campaign.duplicate(true)
	source_hashes = current_source_hashes()
	summary = {"journeyPath": journey_path, "journeySha256": FileAccess.get_sha256(journey_path), "inputCampaignSimulationSeconds": source_campaign.simulationSeconds, "journeyFailures": source_record.failures, "actualSafeReturn": source_record.actualSafeReturn, "journeySourceHashes": source_record.get("sourceHashes", {}), "captureSourceHashes": source_hashes.duplicate(true), "restoration": "SaveCodec.encode exact immutable final.campaign; Router validation; formal geography Runtime.adopt_save; actual MainScene Continue."}
	summary.originalTransportPlan = transport_plan(source_campaign)
	saved_json = Codec.encode(source_campaign, Time.get_datetime_string_from_system(true) + ".000Z")
	if saved_json.is_empty():
		var diagnostic := Codec.decode(JSON.stringify({"version": 2, "campaignId": source_campaign.campaignId, "mode": "mingqi-1650", "savedAtUtc": "2026-10-12T00:00:00.000Z", "simulationSeconds": source_campaign.simulationSeconds, "state": source_campaign}, "", false, true))
		check(false, "SaveCodec rejects unchanged journey: " + str(diagnostic.get("code", diagnostic.get("reason", "save-invalid"))))
		await finish(); return
	if not check(Codec._equal(Codec.decode(saved_json).state, source_campaign), "SaveCodec encodes exact immutable campaign"): await finish(); return
	var validator := Router.new()
	var receipt: Dictionary = validator._validate(saved_json, "mingqi")
	if not check(receipt.get("ok", false), "normal router full native safety: " + str(receipt.get("reason", receipt.get("code", "")))): await finish(); return
	var heights := Height.new()
	var geography: Array = JSON.parse_string(FileAccess.get_file_as_string("res://game/data/mingqi_geography.json"))
	if not check(heights.configure_ports(geography, true, Layout.options()), "formal geography preflight"): await finish(); return
	var probe := Runtime.new(); probe.enable_reference_enhancements()
	receipt = probe.configure(heights.sample_height)
	if receipt.get("ok", false): receipt = probe.adopt_save(saved_json, null)
	var accepted := check(receipt.get("ok", false), "formal native adopt safety: " + str(receipt.get("reason", receipt.get("code", ""))))
	if accepted: accepted = preserve_material(source_campaign, probe.snapshot().campaign, "preflight restore")
	probe.dispose()
	if not accepted: await finish(); return
	summary.preflight = receipt
	if preflight_only: await finish(); return
	if not check(DisplayServer.get_name() != "headless", "GPU capture requires visible native display"): await finish(); return
	if directory.is_empty(): directory = "res://docs/migration/evidence/opening-story/return-" + str(OS.get_process_id())
	if not check(directory.begins_with("res://docs/migration/evidence/opening-story/") and not ".." in directory, "output confined to opening-story evidence"): directory = ""; await finish(); return
	if not check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(directory)), "fresh capture output; never overwrite prior evidence"): directory = ""; await finish(); return
	if not check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) == OK, "create capture evidence directory"): directory = ""; await finish(); return
	output_owned = true
	var slot_paths: Array[String] = []
	for path: String in ["user://saves/mingqi-v2.json", "user://saves/legacy-v1.json", "user://settings.json"]:
		for suffix: String in ["", ".backup", ".rollback", ".staged"]: slot_paths.append(path + suffix)
	original_slots = file_hashes(slot_paths)
	isolated_prefix = "user://tests/opening-return-capture-" + str(OS.get_process_id())
	for suffix: String in ["-v2.json", "-v1.json", "-settings.json"]:
		for extension: String in ["", ".backup", ".rollback", ".staged"]:
			if not check(not FileAccess.file_exists(isolated_prefix + suffix + extension), "new isolated slot path"): await finish(); return
	isolated_owned = true
	var storage := Storage.new(isolated_prefix + "-v2.json")
	if not check(storage.write_checkpoint(saved_json).get("ok", false), "seed isolated slot with exact accepted encoded journey"): await finish(); return
	if not check(FileAccess.get_file_as_string(storage.path) == saved_json, "isolated checkpoint exact readback"): await finish(); return
	var copy := FileAccess.open(directory + "/input-native-save-v2.json", FileAccess.WRITE)
	if not check(copy != null, "preserve exact accepted input bytes as evidence"): await finish(); return
	copy.store_string(saved_json); copy.close()
	summary.inputNativeSaveSha256 = FileAccess.get_sha256(directory + "/input-native-save-v2.json")
	root.unresizable = true; root.size = Vector2i(1600, 900); root.content_scale_size = root.size
	var packed: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	main = packed.instantiate()
	main.router = Router.new({"mingqi_storage": storage, "legacy_storage": Storage.new(isolated_prefix + "-v1.json", Legacy.validate_save), "settings_storage": Settings.new(isolated_prefix + "-settings.json")})
	root.add_child(main); await frames(8)
	var entry: Button = main.menu.find_child("mingqi-continue", true, false)
	if not check(entry != null and not entry.disabled, "real main-menu Continue enabled"): await finish(); return
	main.menu._scroll.ensure_control_visible(entry); await frames(3); await click(entry)
	if not await resume_entry(): await finish(); return
	if not preserve_material(source_campaign, scene.runtime.snapshot().campaign, "visible restore"): await finish(); return
	for dimensions: Vector2i in [Vector2i(1600, 900), Vector2i(1280, 720)]:
		root.size = dimensions; root.content_scale_size = dimensions; await frames(8)
		if not await button("nav_story"): await finish(); return
		if not await focus_control("story_outcome_first-return"): await finish(); return
		if not await capture("first-return-consequence-" + str(dimensions.x), dimensions): await finish(); return
		var casualty: Control = await focus_control("story_relation_xu-fu")
		if not casualty: await finish(); return
		if not check(casualty_consequence_matches(scene.runtime.snapshot(), str(casualty.text)), "visible actual casualty consequence matches real claim and current snapshot"): await finish(); return
		if not await capture("actual-casualties-" + str(dimensions.x), dimensions): await finish(); return
		var steward: Control = await focus_control("story_relation_lin-steward")
		if not steward: await finish(); return
		var steward_dead: bool = not source_campaign.people["steward-a"].alive
		if not check(str(steward.text).contains("阵亡") == steward_dead, "visible steward consequence follows actual survival, without invented death"): await finish(); return
		if not await capture("steward-consequence-" + str(dimensions.x), dimensions): await finish(); return
		if not await button("nav_convoy"): await finish(); return
		if not await focus_control("contract_convoy-002"): await finish(); return
		if not await capture("next-commission-offered-" + str(dimensions.x), dimensions): await finish(); return
	var before: Dictionary = scene.runtime.snapshot().campaign
	var plan := transport_plan(before)
	if not await button("contract_accept_convoy-002"): await finish(); return
	var after: Dictionary = scene.runtime.snapshot().campaign
	var second: Dictionary = after.contracts["convoy-002"]
	if not check(second.status == "active" and second.voyageIds.size() == plan.surviving, "native mouse accepts actual surviving original transports: " + str(scene.runtime.snapshot().runtime.notice)): await finish(); return
	if not check(after.ports.kinmen.stock.grain == before.ports.kinmen.stock.grain - 20 and after.captain.silver == before.captain.silver, "actual Kinmen stock decreases 20; original lease charged once"): await finish(); return
	var transports: Array[Dictionary] = []
	var loaded_ids: Array[String] = []
	var loaded_total := 0
	for voyage_id: String in second.voyageIds:
		var voyage: Dictionary = after.voyages[voyage_id]
		var survivor: Dictionary = after.vessels[voyage.vesselId]
		if not check(survivor.cargo.get("grain", 0) == plan.quantityPerShip and voyage.status == "loading" and voyage.originId == "kinmen" and voyage.destinationId == "forward-supply" and voyage.routeId == "kinmen-supply-deep", "actual surviving transport carries %d grain on real next route: %s" % [plan.quantityPerShip, survivor.id]): await finish(); return
		loaded_ids.append(survivor.id); loaded_total += int(survivor.cargo.grain)
		transports.append({"shipId": survivor.id, "grain": survivor.cargo.grain, "voyage": voyage.duplicate(true)})
	loaded_ids.sort()
	var expected_ids: Array = plan.shipIds.duplicate(); expected_ids.sort()
	if not check(loaded_ids == expected_ids and loaded_total == 20, "only actual surviving original transports receive total twenty grain"): await finish(); return
	if not check(Codec._equal(before.people, after.people) and Codec._equal(before.casualtyOrdinals, after.casualtyOrdinals), "next acceptance retains deaths and casualty authority"): await finish(); return
	for id: String in before.settlements:
		if not check(Codec._equal(before.settlements[id], after.settlements.get(id)), "next acceptance preserves historical receipt " + id): await finish(); return
	for id: String in before.vessels:
		if before.vessels[id].damage.hull <= 0:
			if not preserve_vessel(before.vessels[id], after.vessels[id], "original sunk ship unchanged: " + id): await finish(); return
			for person: Dictionary in before.people.values():
				if person.shipId == id:
					if not check(not person.alive and not after.people[person.id].alive, "actual original death remains final: " + person.id): await finish(); return
	summary.nextCommission = {"beforeStock": before.ports.kinmen.stock.grain, "afterStock": after.ports.kinmen.stock.grain, "transportPlan": plan.duplicate(true), "transports": transports.duplicate(true), "loadedTotal": loaded_total, "receipt": after.settlements[second.receiptId].duplicate(true)}
	for dimensions: Vector2i in [Vector2i(1600, 900), Vector2i(1280, 720)]:
		root.size = dimensions; root.content_scale_size = dimensions; await frames(8)
		if not await focus_control("contract_convoy-002"): await finish(); return
		if not await capture("next-commission-accepted-" + str(dimensions.x), dimensions): await finish(); return
		for transport: Dictionary in transports:
			var route_control: Control = await focus_control("voyage_route_" + transport.voyage.id)
			if not check(route_control is OptionButton and route_control.get_selected_metadata() == "kinmen-supply-deep", "actual native route selector follows accepted transport voyage: " + transport.shipId): await finish(); return
			if not await capture("transport-route-" + transport.shipId + "-" + str(dimensions.x), dimensions): await finish(); return
	if save_readback:
		var safe: Dictionary = scene.runtime.check_safety()
		if not safe.get("ok", false): summary.saveReadback = {"skipped": true, "reason": safe.get("reason", "save-unverified")}
		else:
			var expected_packet: Dictionary = scene.runtime.snapshot()
			var expected: Dictionary = expected_packet.campaign
			var export_context := {"kind": "normal-ui-save-checkpoint", "safe": expected_packet.runtime.canSave, "portId": expected.currentPortId, "nativeIds": expected_packet.naval.ships.map(func(ship): return ship.id), "capturedShipIds": expected_packet.runtime.policy.capturedShipIds.duplicate()}
			if not await button("menu_open") or not await button("save_and_menu"): await finish(); return
			if not check(main.current_scene == null and main.menu.visible, "normal save-and-menu route completes"): await finish(); return
			var read: Dictionary = storage.read_checkpoint()
			if not check(read.get("ok", false), "normal UI save checkpoint readback"): await finish(); return
			var save_witness_path := directory + "/normal-ui-save-v2.json"
			var save_witness := FileAccess.open(save_witness_path, FileAccess.WRITE)
			if not check(save_witness != null, "preserve actual UI disk checkpoint before comparison"): await finish(); return
			save_witness.store_string(read.json); save_witness.flush()
			var witness_okay := save_witness.get_error() == OK; save_witness.close()
			if not check(witness_okay and FileAccess.get_file_as_string(save_witness_path) == read.json, "exact UI disk checkpoint witness readback"): await finish(); return
			var disk_state: Dictionary = Codec.decode(read.json).state
			summary.saveReadback = {"diskRead": true, "normalUiSavePath": save_witness_path, "normalUiSaveSha256": FileAccess.get_sha256(save_witness_path), "exportOwnershipContext": export_context.duplicate(true)}
			if not preserve_material(expected, disk_state, "saved checkpoint", export_context): await finish(); return
			summary.saveReadback.checkpointStateVerified = true
			entry = main.menu.find_child("mingqi-continue", true, false)
			main.menu._scroll.ensure_control_visible(entry); await frames(3); await click(entry)
			if not await resume_entry(): await finish(); return
			if not preserve_material(disk_state, scene.runtime.snapshot().campaign, "normal second Continue"): await finish(); return
			summary.saveReadback.ok = true; summary.saveReadback.slotSha256 = FileAccess.get_sha256(storage.path)
			if not await button("nav_convoy") or not await focus_control("contract_convoy-002"): await finish(); return
			if not await capture("save-readback-1280", Vector2i(1280, 720)): await finish(); return
	unchanged_sources()
	await finish()

func finish() -> void:
	if main:
		main.queue_free(); await frames(6)
	var after_slots: Dictionary = file_hashes(original_slots.keys()) if not original_slots.is_empty() else {}
	if not original_slots.is_empty():
		check(after_slots == original_slots, "user save/settings slots and backups unchanged")
	var cleaned := true
	if isolated_owned:
		for suffix: String in ["-v2.json", "-v1.json", "-settings.json"]:
			for extension: String in ["", ".backup", ".rollback", ".staged"]:
				var path := isolated_prefix + suffix + extension
				if FileAccess.file_exists(path): cleaned = DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK and cleaned
		check(cleaned, "cleanup only this process's isolated slots")
	if output_owned:
		write_json(directory + "/capture-result.json", {"assertions": assertions, "failures": failures, "errors": errors.duplicate(), "captures": captures.duplicate(true), "journey": summary.duplicate(true), "originalSlotsBefore": original_slots.duplicate(true), "originalSlotsAfter": after_slots.duplicate(true), "userDataDir": ProjectSettings.globalize_path("user://"), "originalSlotsUnchanged": after_slots == original_slots, "isolatedSlotsCleaned": cleaned, "preflightOnly": preflight_only})
	print("OPENING_RETURN_CAPTURE_COMPLETE captures=", captures.size(), " assertions=", assertions, " failures=", failures, " preflightOnly=", preflight_only)
	quit(1 if failures else 0)

func _guard_tests() -> void:
	check(journey_failure(null) == "journey-not-object", "reject non-object evidence")
	check(journey_failure({"failures": 1}) == "journey-has-failures", "reject failed journey before loading")
	check(journey_failure({"failures": 0}) == "journey-safe-return-unconfirmed", "reject unconfirmed return")
	check(journey_failure({"failures": 0, "actualSafeReturn": true}) == "journey-final-campaign-missing", "reject missing immutable campaign")
	var rejected := {"failures": 0, "actualSafeReturn": true, "final": {"campaign": {"currentPortId": "xiamen"}}}
	check(journey_failure(rejected) == "journey-not-at-kinmen", "reject another port")
	rejected.final.campaign.currentPortId = "kinmen"
	check(journey_failure(rejected) == "journey-flagship-unavailable", "reject missing flagship")
	rejected.final.campaign.flagshipId = "guard-flag"
	rejected.final.campaign.vessels = {"guard-flag": {"damage": {"hull": 0}}}
	check(journey_failure(rejected) == "journey-flagship-unavailable", "reject sunk flagship")
	rejected.final.campaign.vessels["guard-flag"].damage.hull = 1
	check(journey_failure(rejected) == "journey-first-convoy-unsettled", "reject missing settlement")
	# Incomplete ship-shape guard fixtures only. Never encoded or adopted as saves.
	var shape := {"campaignId": "guard-shape", "vessels": {"guard-shape-grain-a": {"damage": {"hull": 4}}, "guard-shape-grain-b": {"damage": {"hull": 100}}}}
	var plan := transport_plan(shape)
	check(plan.get("ok", false) and plan.get("surviving") == 2 and plan.get("quantityPerShip") == 10, "two real surviving transports allowed with ten grain each")
	shape.vessels["guard-shape-grain-a"].damage.hull = 0
	plan = transport_plan(shape)
	check(plan.get("ok", false) and plan.get("surviving") == 1 and plan.get("quantityPerShip") == 20, "one original survivor still takes twenty grain")
	shape.vessels["guard-shape-grain-b"].damage.hull = 0
	check(transport_plan(shape).get("reason") == "journey-transports-sunk", "both sunk transports remain rejected")
	shape.vessels.erase("guard-shape-grain-b")
	check(transport_plan(shape).get("reason") == "journey-original-transport-missing", "missing transport remains rejected")
	await _presenter_tests()
	_casualty_tests()
	_saved_ownership_tests()
	print("OPENING_RETURN_GUARD_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)

func _presenter_tests() -> void:
	# Actual UI panel flags and native overlay visibility, with no game campaign,
	# sea world, GPU window or saved state. Probe only replaces heavy scene owner.
	main = load("res://game/scenes/main/main_scene.gd").new()
	var probe := PresenterProbe.new()
	probe.add_child(probe.minimap); root.add_child(probe)
	scene = probe; main.current_scene = probe
	probe.interface.close_panel(); probe._present(0)
	check(probe.minimap.chart.visible, "native compact chart initially visible without an operation panel")
	probe.interface.open_panel("story")
	present_current_scene()
	check(not probe.minimap.chart.visible, "frozen-scene QA presenter refresh hides actual native chart after journal opens")
	var count := probe.presentations
	main.current_scene = null
	present_current_scene()
	check(probe.presentations == count, "QA refresh does not present a retired scene after MainScene switches")
	probe.interface.free(); probe.free(); main.free()
	scene = null; main = null
	check(not present_current_scene(), "QA refresh ignores freed current scene")

func _casualty_tests() -> void:
	# Detached assertion-only fixtures. Never adopted, encoded or written as saves.
	var ordinary := "许福 · 老水手\n工钱结清，愿意与你共担风险。"
	var fixture := {"campaign": {"campaignId": "qa-assertion", "settlements": {"qa-assertion:convoy-001:claim": {"kind": "claim-convoy", "details": {"contractId": "convoy-001", "ships": [{"shipId": "qa-assertion-grain-a", "dead": 0, "wounded": 0}], "people": [{"personId": "steward-a", "alive": true}, {"personId": "steward-b", "alive": true}]}}}, "vessels": {"qa-assertion-grain-a": {"representation": "near", "damage": {"hull": 100}, "crew": {"able": 20, "wounded": 0}}}, "people": {"steward-a": {"alive": true}, "steward-b": {"alive": true}}, "casualtyOrdinals": {}}, "naval": {"ships": [{"id": "qa-assertion-grain-a", "hull": 100, "crew": 20}]}, "story": {"relations": [{"id": "xu-fu", "name": "许福", "role": "老水手", "stance": "工钱结清，愿意与你共担风险。"}], "scenes": [{"id": "first-return", "text": ["船员死亡0人、伤员0人。"]}]}}
	check(casualty_consequence_matches(fixture, ordinary), "zero claim/snapshot accepts actual healthy relation without duplicate zero digits")
	check(not casualty_consequence_matches(fixture, ordinary + " 此趟死亡1人、受伤1人。"), "zero claim rejects invented casualty relation")
	var changed: Dictionary = fixture.duplicate(true)
	changed.campaign.people["steward-a"].alive = false
	check(not casualty_consequence_matches(changed, ordinary), "zero claim rejects currently dead steward")
	changed = fixture.duplicate(true); changed.campaign.vessels["qa-assertion-grain-a"].crew.wounded = 1
	check(not casualty_consequence_matches(changed, ordinary), "zero claim rejects currently wounded campaign crew")
	changed = fixture.duplicate(true); changed.campaign.casualtyOrdinals["qa-assertion-grain-a"] = 1
	check(not casualty_consequence_matches(changed, ordinary), "zero claim rejects current casualty authority")
	changed = fixture.duplicate(true); changed.naval.ships[0].crew = 19
	check(not casualty_consequence_matches(changed, ordinary), "zero claim rejects unreconciled native crew")
	changed = fixture.duplicate(true); changed.story.scenes[0].text = ["船员死亡1人、伤员0人。"]
	check(not casualty_consequence_matches(changed, ordinary), "zero claim rejects mismatched actual first-return projection")
	changed = fixture.duplicate(true)
	changed.campaign.settlements["qa-assertion:convoy-001:claim"].details.ships[0].dead = 1
	changed.campaign.settlements["qa-assertion:convoy-001:claim"].details.ships[0].wounded = 2
	var injury := " 此趟死亡1人、受伤2人，他希望先安置伤员。"
	changed.story.relations[0].stance += injury
	changed.story.scenes[0].text = ["船员死亡1人、伤员2人。"]
	check(casualty_consequence_matches(changed, ordinary + injury), "positive casualties still require actual one dead and two wounded")
	check(not casualty_consequence_matches(changed, ordinary + " 此趟死亡1人、受伤3人。"), "positive casualties reject wrong real number")
	check(not casualty_consequence_matches(changed, ordinary), "positive casualties cannot use zero/omitted casualty branch")

func _saved_ownership_tests() -> void:
	# Compare-only fixtures: no Campaign object, import, state repair or save.
	var before := {"id": "qa-enemy", "ownerId": "enemy", "representation": "near", "damage": {"hull": 0}, "cargo": {}}
	var after: Dictionary = before.duplicate(true); after.representation = "route"
	var context := {"kind": "normal-ui-save-checkpoint", "safe": true, "portId": "kinmen", "nativeIds": ["qa-flag"], "capturedShipIds": []}
	check(allows_saved_ownership(before, after, context), "normal save allows only absent uncaptured sunk enemy near-to-route ownership")
	check(not allows_saved_ownership(before, after, {}), "restore and generic material checks stay strict by default")
	var changed: Dictionary = before.duplicate(true); changed.damage.hull = 1
	check(not allows_saved_ownership(changed, after, context), "live enemy cannot use saved ownership exception")
	changed = context.duplicate(true); changed.nativeIds.append("qa-enemy")
	check(not allows_saved_ownership(before, after, changed), "present native enemy cannot use saved ownership exception")
	changed = context.duplicate(true); changed.capturedShipIds.append("qa-enemy")
	check(not allows_saved_ownership(before, after, changed), "captured enemy cannot use saved ownership exception")
	changed = after.duplicate(true); changed.cargo.grain = 1
	check(not allows_saved_ownership(before, changed, context), "ownership exception cannot hide any other material field change")
	check(not allows_saved_ownership(after, before, context), "reverse route-to-near change stays forbidden")
	changed = context.duplicate(true); changed.safe = false
	check(not allows_saved_ownership(before, after, changed), "unsafe export cannot use saved ownership exception")
