extends RefCounted
## Bundled subject registry; reports are data, demo code is explicitly allowlisted.
const CATALOG_PATH := "res://assets/research/catalog.json"
const PAPER_ROOT := "res://assets/research/papers/"
const PAPER_SECTIONS := ["问题与假设","方案比较","算法与实现","实验设计","结果与证据","局限与失败","集成与复现"]
const DEMO_PATHS := {"hull-contact":"res://game/research/demos/hull_contact_experiment.gd","ocean-surface":"res://game/research/demos/ocean_surface_experiment.gd","shore-surf":"res://game/research/demos/shore_surf_experiment.gd","weather-shadow":"res://game/research/demos/weather_shadow_experiment.gd","shadow-edges":"res://game/research/demos/shadow_edges_experiment.gd","wake-flow":"res://game/research/demos/wake_flow_experiment.gd"}
const STATUSES := {"proposed":"提议","researching":"研究中","validated":"独立验证","integration-ready":"待集成","integrated":"已集成","integrated-retrospective":"已集成 · 事后整理","parked":"搁置"}
var _topics: Array = []
var _by_id: Dictionary = {}

func load_catalog() -> Dictionary:
	var file := FileAccess.open(CATALOG_PATH,FileAccess.READ)
	if file == null: return {"ok":false,"reason":"课题目录无法读取"}
	var data: Variant = JSON.parse_string(file.get_as_text()); file.close()
	var checked := validate_catalog(data)
	if not checked.ok: return checked
	_topics = data.topics.duplicate(true); _by_id.clear()
	for item: Dictionary in _topics: _by_id[item.id] = item
	return {"ok":true,"count":_topics.size()}

func validate_catalog(data: Variant) -> Dictionary:
	if not data is Dictionary or data.get("schemaVersion") != 1 or not data.get("topics") is Array:
		return {"ok":false,"reason":"课题目录格式无效"}
	var ids: Dictionary = {}
	for item: Variant in data.topics:
		if not item is Dictionary: return {"ok":false,"reason":"课题条目无效"}
		for key: String in ["id","title","abstract","category","status","paper","demo"]:
			if not item.get(key) is String: return {"ok":false,"reason":"课题字段无效："+key}
		if item.id.is_empty() or item.title.is_empty() or ids.has(item.id): return {"ok":false,"reason":"课题标识重复或为空"}
		ids[item.id] = true
		if not item.status in STATUSES or not item.get("retrospective") is bool: return {"ok":false,"reason":"研究状态无效"}
		if not _safe_resource(item.paper) or not item.paper.begins_with(PAPER_ROOT) or item.paper.get_extension() != "md": return {"ok":false,"reason":"论文资源路径无效"}
		if not item.demo.is_empty() and not DEMO_PATHS.has(item.demo): return {"ok":false,"reason":"Demo 未注册"}
		for key: String in ["sources","evidence"]:
			if not item.get(key) is Array: return {"ok":false,"reason":"研究来源字段无效"}
			for path: Variant in item[key]:
				if not path is String or not _safe_resource(path): return {"ok":false,"reason":"研究引用路径无效"}
	return {"ok":true}

static func _safe_resource(path: String) -> bool:
	return path.begins_with("res://") and not path.contains("..") and not path.contains("\\") and not path.contains("\n")

func topics() -> Array: return _topics.duplicate(true)
func topic(id: String) -> Dictionary: return _by_id.get(id,{}).duplicate(true)
func status_label(id: String) -> String: return STATUSES.get(_by_id.get(id,{}).get("status",""),"未知")
func demo_path(id: String) -> String: return DEMO_PATHS.get(_by_id.get(id,{}).get("demo",""),"")

func read_paper(id: String) -> Dictionary:
	if not _by_id.has(id): return {"ok":false,"reason":"课题不存在"}
	return _read_text(_by_id[id].paper)

func read_reference(path: String) -> Dictionary:
	if not _safe_resource(path): return {"ok":false,"reason":"仅阅读课题登记的仓库资源"}
	var registered := false
	for item: Dictionary in _topics:
		if path in item.sources or path in item.evidence: registered = true; break
	if not registered: return {"ok":false,"reason":"来源未登记"}
	return _read_text(path)

func _read_text(path: String) -> Dictionary:
	if path.get_extension() not in ["md","gd","gdshader","gdshaderinc","json","txt"]: return {"ok":false,"reason":"此引用不是文本资源"}
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null: return {"ok":false,"reason":"当前安装不包含此仓库证据；论文内已保留来源与结果。","path":path}
	if file.get_length() > 2*1024*1024: file.close(); return {"ok":false,"reason":"引用超过阅读上限，请在仓库查看。","path":path}
	var content := file.get_as_text(); file.close()
	return {"ok":true,"text":content,"path":path}
