extends SceneTree
## Execute the production scalar shader functions as GDScript, with independently
## hand-derived cases. This is CPU logic coverage, never a GPU/pixel claim.
const SOURCE := "res://modules/scene_engine/ocean/reference_shore_foam.gdshaderinc"
var assertions := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,detail: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ",detail)

func scalar_function(source: String,name: String) -> RefCounted:
	var expression := RegEx.new()
	expression.compile("(?s)float\\s+"+name+"\\s*\\(([^)]*)\\)\\s*\\{([^}]+)\\}")
	var found := expression.search(source)
	check(found!=null,"production scalar formula exists: "+name)
	if found==null: return null
	var parameters: Array[String]=[]
	for parameter: String in found.get_string(1).split(","):
		parameters.append(parameter.strip_edges().trim_prefix("float ")+": float")
	var body := found.get_string(2).strip_edges().replace(";","").replace("max(","maxf(").replace("min(","minf(")
	# Scalar formulas use only native arithmetic and smoothstep/clamp; their
	# production source is executed, rather than a separately copied CPU formula.
	var program := GDScript.new()
	program.source_code="extends RefCounted\nfunc evaluate("+", ".join(parameters)+") -> float:\n\t"+body.replace("\n","\n\t")+"\n"
	check(program.reload()==OK,"production scalar formula is executable: "+name)
	return program.new() if program.can_instantiate() else null

func cases(model: RefCounted,fixtures: Array,detail: String) -> void:
	if model==null: return
	for fixture: Array in fixtures:
		var actual: float=model.evaluate(fixture[0],fixture[1])
		check(is_finite(actual) and absf(actual-float(fixture[2]))<1e-6,detail+": "+str(fixture))

func run() -> void:
	check(FileAccess.file_exists(SOURCE),"formal sea owns the smooth seabed/shore transition instead of a hard terrain edge")
	if failures: print("REFERENCE_SHORE_FEATHER_TESTS assertions=",assertions," failures=",failures); quit(1); return
	var source:=FileAccess.get_file_as_string(SOURCE)
	cases(scalar_function(source,"reference_bottom_visibility"),[[0.0,48.0,1.0],[8.0,48.0,1.0],[15.0,48.0,0.5],[22.0,48.0,0.0],[24.0,100.0,0.0],[0.0,0.0,0.0],[0.0,24.0,0.5],[15.0,24.0,0.25],[4.0,-2.0,0.0]],"true shallow bottom remains visible and coverage edges fade continuously")
	cases(scalar_function(source,"reference_bottom_gate"),[[0.0,24.0,1.0],[24.0,2.0,0.0],[0.0,-1.0,0.0],[0.0,0.25,0.0],[4.0,2.0,0.5],[4.0,1.125,0.25],[0.0,1.125,0.5]],"water floor classification does not fade ordinary above-water objects or deep-water hulls")
	cases(scalar_function(source,"reference_shore_transition"),[[0.0,0.0,1.0],[3.2,0.0,0.0],[0.0,14.0,0.0],[1.75,8.5,0.25],[0.2,1000.0,0.0],[8.0,0.0,0.0]],"pale shore transition follows actual coast and excludes isolated shallow banks")
	print("REFERENCE_SHORE_FEATHER_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
