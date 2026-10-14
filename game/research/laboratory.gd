extends Control
## Research host: reports are read-only; each experiment owns an isolated World3D.
signal main_menu_requested
const Catalog = preload("res://game/research/catalog.gd")
const Reader = preload("res://game/research/paper_reader.gd")
const ParameterPanel = preload("res://game/research/parameter_panel.gd")
const CASES := ["cruise","slow","turn","stop","reentry"]
const CASE_LABELS := ["匀速航行","低速航行","转向","减速至停止","重入水压力测试"]
const KINDS := ["fuchuan","fisherman","merchant","voc","patrol","heavy"]
const KIND_LABELS := ["福船","渔船","商船","VOC 商船","巡逻船","重型战船"]
const CAMERAS := ["side","front","high"]
const CAMERA_LABELS := ["船侧水线","船首","高处俯视"]
var startup_options: Dictionary = {}
var startup_receipt: Dictionary = {"ok":false}
var _catalog: RefCounted = Catalog.new()
var _selected := ""
var _disposed := false
var _demo: Node3D
var _demo_options := {"kind":"fuchuan","scenario":"cruise","camera_mode":"side","paused":false,"contact_enabled":true,"carrier_extent":1200.0}
var _topic_buttons: Dictionary = {}
var _paper: RichTextLabel
var _title: Label
var _summary: Label
var _status: Label
var _reader_body: VBoxContainer
var _reference_body: ScrollContainer
var _references: VBoxContainer
var _demo_body: VBoxContainer
var _viewport: SubViewport
var _run_button: Button
var _pause_button: Button
var _contact: CheckBox
var _stats: Label
var _telemetry_seconds := 0.0
var _dragging := false
var _topic_options: Dictionary = {}
var _parameter_panel: Control
var _hull_controls: HFlowContainer
var _step_button: Button
var _notice: Label
var _demo_revision := 0

func _ready() -> void:
	_build_ui()
	var receipt: Dictionary = _catalog.load_catalog()
	if not receipt.ok: _paper.text = Reader.escape(receipt.reason); startup_receipt = receipt; return
	for item: Dictionary in _catalog.topics():
		var button := Button.new(); button.name = "Topic_"+item.id
		button.text = item.title+"\n"+item.category; button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; button.custom_minimum_size.y = 78
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(select_topic.bind(item.id)); _topic_buttons[item.id] = button
		find_child("TopicList",true,false).add_child(button)
	startup_receipt = {"ok":true,"mode":"laboratory","subjects":_catalog.topics().size(),"source":"bundled papers and isolated production-component experiments"}
	select_topic(_catalog.topics()[0].id)
	if not startup_options.get("staged",false): activate_entry()

func activate_entry() -> void:
	if not _disposed and startup_receipt.ok: get_window().title = "海上明旗 · 实验室"

func select_topic(id: String) -> bool:
	if _disposed or _catalog.topic(id).is_empty(): return false
	_close_demo(); _selected = id
	var item: Dictionary = _catalog.topic(id)
	_title.text = item.title; _summary.text = item.abstract
	_status.text = _catalog.status_label(id)+"  |  "+("独立实验可运行 · 近拍效果待改进" if id == "hull-contact" else "独立实验 · 按论文判据观察" if not _catalog.demo_path(id).is_empty() else "文献整理 · 独立实验尚未迁入")
	_run_button.disabled = _catalog.demo_path(id).is_empty()
	_run_button.tooltip_text = "此课题尚未提供独立实验；登记不代表验证通过。" if _run_button.disabled else "固定初态，在独立场景复现当前方案。"
	for key: String in _topic_buttons:
		_topic_buttons[key].add_theme_color_override("font_color",Color("e2c48b") if key == id else Color("dce7e5"))
	_show_paper(); return true

func _show_paper() -> void:
	_close_demo(); _reference_body.hide(); _reader_body.show()
	var paper: Dictionary = _catalog.read_paper(_selected)
	_paper.text = Reader.to_bbcode(paper.text) if paper.ok else Reader.escape(paper.reason)
	_paper.scroll_to_line(0)

func _show_references() -> void:
	_close_demo(); _reader_body.hide(); _reference_body.show()
	for child: Node in _references.get_children(): child.free()
	var item: Dictionary = _catalog.topic(_selected)
	_label(_references,"SourceExplanation","论文随游戏发布；原始源码、历史日志和完整证据在仓库内查看。当前安装未包含的引用会明确提示。",16)
	for group: String in ["sources","evidence"]:
		_label(_references,"Group_"+group,"实现与研究来源" if group == "sources" else "历史证据",21)
		for path: String in item.get(group,[]):
			var button := _button(_references,"Reference",path.trim_prefix("res://"))
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT; button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.pressed.connect(_read_reference.bind(path))

func _read_reference(path: String) -> void:
	var read: Dictionary = _catalog.read_reference(path)
	_reference_body.hide(); _reader_body.show()
	_paper.text = Reader.to_bbcode("# 来源\n\n"+path+"\n\n"+("```\n"+read.text+"\n```" if read.ok else read.reason))
	_paper.scroll_to_line(0)

func start_demo(options: Dictionary = {}) -> Dictionary:
	if _disposed or _selected.is_empty(): return {"ok":false,"reason":"实验室已关闭"}
	var path: String = _catalog.demo_path(_selected)
	if path.is_empty(): return {"ok":false,"reason":"此课题尚未提供独立实验"}
	_close_demo()
	var script: Variant = load(path)
	if not script is GDScript or not script.can_instantiate(): return _demo_failure("实验资源不可用")
	var candidate: Node3D = script.new()
	if _topic_options.has(_selected): _demo_options = _topic_options[_selected].duplicate(true)
	elif candidate.has_method("get_default_options"): _demo_options = candidate.get_default_options()
	else: _demo_options = {"kind":"fuchuan","scenario":"cruise","camera_mode":"side","paused":false,"contact_enabled":true,"carrier_extent":1200.0}
	_demo_options.merge(options,true)
	var configured: Dictionary = candidate.configure(_demo_options)
	if not configured.ok: candidate.free(); return _demo_failure(configured.get("reason","实验初始化失败"))
	_viewport.add_child(candidate)
	var ready: Dictionary = candidate.inspection_snapshot()
	if not ready.get("ready",false): candidate.dispose(); candidate.free(); return _demo_failure("实验场景构建失败")
	_demo = candidate
	_demo_revision += 1
	_reader_body.hide(); _reference_body.hide(); _demo_body.show()
	_hull_controls.visible = _selected == "hull-contact"
	_parameter_panel.visible = _selected != "hull-contact"
	var bound: Dictionary = _parameter_panel.bind_specs(candidate.control_spec() if candidate.has_method("control_spec") else [])
	if not bound.ok: _close_demo(); return _demo_failure(bound.reason)
	_notice.text = ""
	_sync_controls()
	_refresh_viewport()
	_telemetry_seconds = 0.0; _update_telemetry()
	return {"ok":true}

func _sync_controls() -> void:
	_pause_button.text = "继续" if _demo_options.paused else "暂停"
	_step_button.disabled = not _demo_options.paused
	_step_button.text = "单步 1/%d 秒" % roundi(1.0/_experiment_step())
	if _selected != "hull-contact": _parameter_panel.sync_values(_demo_options); return
	_contact.set_pressed_no_signal(_demo_options.contact_enabled)
	find_child("ExperimentCase",true,false).select(CASES.find(_demo_options.scenario))
	find_child("ExperimentShip",true,false).select(KINDS.find(_demo_options.kind))
	find_child("ExperimentCamera",true,false).select(CAMERAS.find(_demo_options.camera_mode))
	find_child("ExperimentCarrier",true,false).select(0 if _demo_options.carrier_extent == 1200.0 else 1)

func _demo_failure(reason: String) -> Dictionary:
	_reader_body.show(); _paper.text = Reader.escape(reason)
	return {"ok":false,"reason":reason}

func _close_demo() -> void:
	_dragging = false
	_demo_revision += 1
	if is_instance_valid(_demo):
		_topic_options[_selected] = _demo_options.duplicate(true)
		_demo.dispose(); _demo.free()
	_demo = null
	if is_instance_valid(_demo_body): _demo_body.hide()

func _change_case(index: int) -> void:
	_reset_demo({"scenario":CASES[index]})
func _change_kind(index: int) -> void:
	_reset_demo({"kind":KINDS[index]})
func _change_camera(index: int) -> void:
	_demo_options.camera_mode = CAMERAS[index]
	if is_instance_valid(_demo): _demo_revision += 1; _demo.set_camera_mode(CAMERAS[index]); _update_telemetry()
func _change_carrier(index: int) -> void:
	_reset_demo({"carrier_extent":1200.0 if index == 0 else 384.0})
func _reset_demo(overrides: Dictionary = {}) -> void:
	if not is_instance_valid(_demo): return
	var receipt: Dictionary = _demo.reset_experiment(overrides)
	if not receipt.ok: _close_demo(); _demo_failure(receipt.get("reason","重置失败")); return
	_demo_options.merge(overrides,true)
	var state: Dictionary = _demo.inspection_snapshot()
	if state.has("parameters"): _demo_options = state.parameters.duplicate(true)
	_demo_revision += 1
	_sync_controls()
	_update_telemetry()
func _pause_demo() -> void:
	if not is_instance_valid(_demo): return
	_demo_options.paused = not _demo_options.paused
	_demo_revision += 1
	_demo.set_paused(_demo_options.paused); _sync_controls(); _update_telemetry()

func step_demo() -> Dictionary:
	if _disposed or not is_instance_valid(_demo) or not _demo_options.get("paused",false): return {"ok":false,"reason":"暂停后才能单步观察"}
	_demo_revision += 1
	var delta := _experiment_step()
	_demo.set_paused(false); _demo.advance(delta); _demo.set_paused(true)
	_update_telemetry(); return {"ok":true}

func _experiment_step() -> float:
	if not is_instance_valid(_demo): return 1.0/32.0
	var snapshot: Dictionary = _demo.inspection_snapshot()
	var step: Variant = snapshot.get("fixed_step",1.0/32.0)
	return float(step) if (step is float or step is int) and is_finite(float(step)) and float(step)>0.0 and float(step)<=1.0 else 1.0/32.0

func _change_parameter(id: String,value: Variant) -> void:
	if _disposed or not is_instance_valid(_demo) or not _demo.has_method("set_parameter"): return
	var changed: Dictionary = _demo.set_parameter(id,value)
	if not changed.get("ok",false):
		_notice.text = "参数未修改："+changed.get("reason","输入无效"); _sync_controls(); return
	_demo_options[id] = changed.get("value",value)
	_demo_revision += 1
	if changed.get("reset_required",false): _reset_demo({id:_demo_options[id]}); _notice.text = "此参数需重建实验，已按相同初态重置。"
	else: _sync_controls(); _update_telemetry()
func _toggle_contact(enabled: bool) -> void:
	_demo_options.contact_enabled = enabled
	if is_instance_valid(_demo): _demo_revision += 1; _demo.set_contact_enabled(enabled); _update_telemetry()

func _process(delta: float) -> void:
	if _disposed or not is_instance_valid(_demo) or not get_window().has_focus(): return
	_demo.advance(delta)
	_telemetry_seconds += delta
	if _telemetry_seconds >= 0.2: _telemetry_seconds = 0.0; _update_telemetry()

func _update_telemetry() -> void:
	if not is_instance_valid(_demo): return
	var receipt: Dictionary = _demo.inspection_snapshot()
	if _selected != "hull-contact":
		_stats.text = "实验时间 %.2f s · 步 %d · %s\n%s\n右键环绕 / 滚轮缩放；暂停后可单步观察。" % [float(receipt.get("time",0)),int(receipt.get("tick",0)),"已暂停" if receipt.get("paused",false) else "运行中",_telemetry_text(receipt)]
		return
	var contact: Dictionary = receipt.get("contact",{})
	_stats.text = "实验时间 %.2f s · 步 %d · 相对入水响应 %.3f · %s\n同一状态对照：只开关接触水沫，保留尾迹。右键环绕 / 滚轮缩放。载体对照重置初态；近场载体只覆盖 ±192 m。" % [float(receipt.get("time",0)),int(receipt.get("tick",0)),float(contact.get("impact_strength",0)),"已暂停" if receipt.get("paused",false) else "运行中"]

func _telemetry_text(receipt: Dictionary) -> String:
	var telemetry: Variant = receipt.get("telemetry",{})
	if not telemetry is Dictionary: return str(telemetry)
	match _selected:
		"ocean-surface":
			return "%d 组波浪 · %s · 平面镜像%s · 折射%s" % [int(telemetry.get("wave_count",5)),"柔化光学" if _demo_options.get("optics_mode","soft") == "soft" else "旧镜面响应","开启" if _demo_options.get("reflection_enabled",false) else "关闭","开启" if _demo_options.get("refraction_enabled",false) else "关闭"]
		"shore-surf":
			return "源短浪已更新 %d 次 · 残沫/花边倍率 %.2f · 控制器周期约 %.2f s" % [int(telemetry.get("source_updates",0)),float(_demo_options.get("residue_opacity",1.0)) if _demo_options.get("residue_enabled",true) else 0.0,float(telemetry.get("source_controller_period_seconds",29.97))]
		"weather-shadow":
			return "移动天气实例 %d · 天空云环 %d · 云影网格 %d" % [int(telemetry.get("world_weather_instances",0)),int(telemetry.get("sky_clones",0)),int(telemetry.get("shadow_meshes",0))]
		"wake-flow":
			if _demo_options.get("field_enabled",false):
				var field: Dictionary = receipt.get("field",{})
				var status: String = str(receipt.get("field_status","pending"))
				if status=="error": return "局部水流场不可用，保留原尾迹："+str(receipt.get("field_error","未知错误"))
				return "局部水流场 · %s · GPU 已发布 %.2f s · %d 探针\n双侧尾迹 / 水面起伏 / 持续泡沫；当前显示：%s。" % ["已绑定" if status=="ready" else "准备中，保留原尾迹",float(field.get("time",0)),int(field.get("emitter_count",0)),str(_demo_options.get("field_debug","none"))]
			var flow: Dictionary = receipt.get("flow",{})
			return "%s · 航迹 %.1f m · 历史 %d 点\n目标保留双侧尾浪；中线候选仅用于查看失败实验。" % ["历史中线候选 · 未采用" if _demo_options.get("flow_enabled",false) else "原尾迹对照",float(flow.get("length_m",0.0)),int(flow.get("samples",0))]
		"shadow-edges":
			return "同一阴影几何的原算法 / 预计算对照；帧内 CPU 耗时不等于整场 FPS。"
	return "当前参数、镜头和原始状态随截图保存。"

func _view_input(event: InputEvent) -> void:
	if not is_instance_valid(_demo): return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT: _dragging = event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			_demo_revision += 1
			_demo.zoom_camera(-0.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.12)
	elif event is InputEventMouseMotion and _dragging: _demo_revision += 1; _demo.orbit_camera(-event.relative.x*0.006,event.relative.y*0.004)
	var state: Dictionary = _demo.inspection_snapshot()
	if state.has("parameters"): _demo_options = state.parameters.duplicate(true)

func _refresh_viewport() -> void:
	if _disposed or not is_instance_valid(_demo): return
	_demo_revision += 1
	_demo.orbit_camera(0.0,0.0)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or event.keycode != KEY_ESCAPE: return
	if is_instance_valid(_demo) or _reference_body.visible: _show_paper()
	else: main_menu_requested.emit()
	get_viewport().set_input_as_handled()

func inspection_snapshot() -> Dictionary:
	return {"startup":startup_receipt.duplicate(true),"topic_count":_catalog.topics().size(),"selected_topic":_selected,"disposed":_disposed,"parameters":_demo_options.duplicate(true),"demo":_demo.inspection_snapshot() if is_instance_valid(_demo) else {},"scope":"Research papers and isolated demonstrations; no campaign save/settings writes."}

func _save_demo() -> void:
	var saved: Dictionary = await save_experiment_frame()
	if not _disposed: _notice.text = "截图与参数已保存："+saved.path if saved.ok else saved.get("reason","保存失败")

func save_experiment_frame(path: String = "") -> Dictionary:
	if _disposed or not is_instance_valid(_demo): return {"ok":false,"reason":"当前没有运行实验"}
	var token := _demo.get_instance_id()
	var revision := _demo_revision
	if path.is_empty(): path = "user://research-evidence/%s-%s-%d.png" % [_selected,_demo_options.get("scenario",_demo_options.get("preset","current")),Time.get_ticks_msec()]
	if path.get_extension().to_lower() != "png": return {"ok":false,"reason":"截图需要 PNG 路径"}
	await RenderingServer.frame_post_draw
	if _disposed or not is_instance_valid(_demo) or _demo.get_instance_id() != token or revision != _demo_revision: return {"ok":false,"reason":"实验或参数已切换，取消旧截图"}
	var image := _viewport.get_texture().get_image()
	if image == null or image.is_empty(): return {"ok":false,"reason":"渲染帧不可用"}
	var snapshot := inspection_snapshot()
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if error != OK: return {"ok":false,"reason":"无法创建截图目录"}
	error = image.save_png(path)
	if error != OK: return {"ok":false,"reason":"截图无法写入"}
	snapshot.engine = Engine.get_version_info(); snapshot.gpu = RenderingServer.get_video_adapter_name()
	snapshot.image_sha256 = FileAccess.get_sha256(path); snapshot.capture_note = "图像与参数在同一 frame_post_draw 回调读取；暂停实验可锁定时间进行对照。"
	var file := FileAccess.open(path+".json",FileAccess.WRITE)
	if file == null: return {"ok":false,"reason":"截图成功，但参数无法写入","path":path}
	file.store_string(JSON.stringify(snapshot,"\t")); file.close()
	return {"ok":true,"path":ProjectSettings.globalize_path(path)}

func dispose() -> void:
	if _disposed: return
	_disposed = true; set_process(false); _close_demo()
func _exit_tree() -> void: dispose()

func _label(parent: Node, node_name: String, text: String, size: int = 17) -> Label:
	var label := Label.new(); label.name = node_name; label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size",size); parent.add_child(label); return label
func _button(parent: Node, node_name: String, text: String) -> Button:
	var button := Button.new(); button.name = node_name; button.text = text
	button.custom_minimum_size.y = 38; parent.add_child(button); return button
func _option(parent: Node, node_name: String, labels: Array, callback: Callable) -> OptionButton:
	var option := OptionButton.new(); option.name = node_name
	for label: String in labels: option.add_item(label)
	option.item_selected.connect(callback); parent.add_child(option); return option
func _theme() -> Theme:
	var theme := Theme.new(); theme.default_font_size = 17
	var font := SystemFont.new(); font.font_names = PackedStringArray(["Microsoft YaHei","Noto Sans CJK SC","sans-serif"]); theme.default_font = font
	for type: String in ["Label","Button","OptionButton","CheckBox","RichTextLabel"]: theme.set_color("font_color",type,Color("dce7e5"))
	theme.set_color("font_hover_color","Button",Color("ffe2a4")); theme.set_color("font_disabled_color","Button",Color("7a9295"))
	for state: String in ["normal","hover","pressed","disabled","focus"]:
		var style := StyleBoxFlat.new(); style.bg_color = Color("20373e") if state in ["hover","pressed"] else Color("142930")
		style.border_color = Color("c4a76e") if state == "focus" else Color("38535a")
		style.set_border_width_all(2 if state == "focus" else 1); style.set_content_margin_all(10)
		theme.set_stylebox(state,"Button",style); theme.set_stylebox(state,"OptionButton",style)
	return theme

func _build_ui() -> void:
	name = "Laboratory"; set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); theme = _theme()
	var backdrop := ColorRect.new(); backdrop.color = Color("0c1c23"); backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(backdrop)
	var margin := MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left","top","right","bottom"]: margin.add_theme_constant_override("margin_"+side,24)
	add_child(margin)
	var page := VBoxContainer.new(); page.add_theme_constant_override("separation",16); margin.add_child(page)
	var header := HBoxContainer.new(); page.add_child(header)
	_label(header,"LaboratoryTitle","实验室",30)
	var back := _button(header,"ReturnToMenu","返回首页"); back.pressed.connect(func(): main_menu_requested.emit())
	_label(page,"ResearchPrinciple","提出问题 · 比较方案 · 独立实验 · 保留证据 · 接入游戏",16)
	var split := HSplitContainer.new(); split.size_flags_vertical = Control.SIZE_EXPAND_FILL; split.split_offset = 280; page.add_child(split)
	var topic_scroll := ScrollContainer.new(); topic_scroll.custom_minimum_size.x = 230; split.add_child(topic_scroll)
	var topic_list := VBoxContainer.new(); topic_list.name = "TopicList"; topic_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; topic_list.add_theme_constant_override("separation",10); topic_scroll.add_child(topic_list)
	_label(topic_list,"SubjectLabel","研究目录",21)
	var detail := VBoxContainer.new(); detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL; detail.custom_minimum_size.x = 300; detail.add_theme_constant_override("separation",12); split.add_child(detail)
	_title = _label(detail,"TopicTitle","",27); _summary = _label(detail,"TopicAbstract","",17); _status = _label(detail,"ResearchStatus","",15); _status.modulate = Color("c5b590")
	var tabs := HBoxContainer.new(); detail.add_child(tabs)
	_button(tabs,"ReadPaper","研究全文").pressed.connect(_show_paper)
	_run_button = _button(tabs,"RunExperiment","运行实验"); _run_button.pressed.connect(func(): start_demo())
	_button(tabs,"ReadSources","来源与证据").pressed.connect(_show_references)
	_reader_body = VBoxContainer.new(); _reader_body.size_flags_vertical = Control.SIZE_EXPAND_FILL; detail.add_child(_reader_body)
	_paper = RichTextLabel.new(); _paper.name = "ResearchPaper"; _paper.bbcode_enabled = true; _paper.selection_enabled = true
	_paper.size_flags_vertical = Control.SIZE_EXPAND_FILL; _paper.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _paper.add_theme_constant_override("normal_v_separation",8); _reader_body.add_child(_paper)
	_reference_body = ScrollContainer.new(); _reference_body.size_flags_vertical = Control.SIZE_EXPAND_FILL; detail.add_child(_reference_body); _reference_body.hide()
	_references = VBoxContainer.new(); _references.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _references.add_theme_constant_override("separation",14); _reference_body.add_child(_references)
	_demo_body = VBoxContainer.new(); _demo_body.size_flags_vertical = Control.SIZE_EXPAND_FILL; detail.add_child(_demo_body); _demo_body.hide()
	_hull_controls = HFlowContainer.new(); _hull_controls.add_theme_constant_override("h_separation",10); _demo_body.add_child(_hull_controls)
	_option(_hull_controls,"ExperimentCase",CASE_LABELS,_change_case); _option(_hull_controls,"ExperimentShip",KIND_LABELS,_change_kind); _option(_hull_controls,"ExperimentCamera",CAMERA_LABELS,_change_camera)
	_option(_hull_controls,"ExperimentCarrier",["海面载体：1200m 基准","海面载体：384m 近场"],_change_carrier)
	_contact = CheckBox.new(); _contact.name = "ContactEnabled"; _contact.text = "船体接触水沫"; _contact.button_pressed = true; _contact.toggled.connect(_toggle_contact); _hull_controls.add_child(_contact)
	_parameter_panel = ParameterPanel.new(); _parameter_panel.name = "TopicParameters"; _parameter_panel.add_theme_constant_override("h_separation",10); _demo_body.add_child(_parameter_panel)
	_parameter_panel.parameter_changed.connect(_change_parameter)
	var controls := HFlowContainer.new(); controls.add_theme_constant_override("h_separation",10); _demo_body.add_child(controls)
	_pause_button = _button(controls,"PauseExperiment","暂停"); _pause_button.pressed.connect(_pause_demo)
	_step_button = _button(controls,"StepExperiment","单步 1/32 秒"); _step_button.pressed.connect(func(): step_demo())
	_button(controls,"ResetExperiment","同条件重置").pressed.connect(_reset_demo)
	_button(controls,"SaveExperiment","保存截图与参数").pressed.connect(_save_demo)
	var container := SubViewportContainer.new(); container.name = "ExperimentView"; container.stretch = true
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL; container.size_flags_horizontal = Control.SIZE_EXPAND_FILL; _demo_body.add_child(container)
	_viewport = SubViewport.new(); _viewport.name = "ExperimentViewport"; _viewport.size = Vector2i(1000,600); _viewport.world_3d = World3D.new()
	_viewport.size_changed.connect(_refresh_viewport)
	_viewport.msaa_3d = Viewport.MSAA_4X; _viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; container.add_child(_viewport); container.gui_input.connect(_view_input)
	_stats = _label(_demo_body,"ExperimentTelemetry","",15)
	_notice = _label(_demo_body,"ExperimentNotice","",15)
