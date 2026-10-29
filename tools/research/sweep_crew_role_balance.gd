extends SceneTree
## Independent numerical audit. No tuning, UI, production state or weighted score.
const Rules = preload("res://game/research/demos/crew_role_rules.gd")
const SOURCE := "res://game/research/demos/crew_role_rules.gd"
const SELF_SOURCE := "res://tools/research/sweep_crew_role_balance.gd"
const STEP := 1.0 / 32.0
const EPSILON := 0.000001
const WINDOWS := [8,24,60]
const STRATEGIES := {
	"balanced":[],
	"one_gunner_to_repair":[["crew04","carpenter"]],
	"repair_detachment":[["crew04","carpenter"],["crew05","carpenter"]],
	"gun_priority":[["crew03","gunner"]],
	"rest_priority":[["crew04","rest"],["crew05","rest"]],
	"no_musician":[["crew02","gunner"]],
	"no_cook":[["crew01","gunner"]]
}
const MAXIMIZE := ["gun_efficiency_seconds","hull_gain","morale_gain","fatigue_reduction","cooked_rations_remaining"]
const MINIMIZE := ["grain_used","wood_used"]
var assertions := 0
var failures: Array = []
var cases: Array = []
var groups: Array = []
var fixtures: Dictionary = {}
var output := ""
var repair_model := "workstations"
var _repair_model_supplied := false

func _initialize() -> void: run.call_deferred()

func check(ok: bool, reason: String) -> bool:
	assertions += 1
	if not ok and not failures.has(reason):
		failures.append(reason)
		printerr("FAIL CREW BALANCE: ",reason)
	return ok

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output=") and output.is_empty(): output = arg.trim_prefix("--output=")
		elif arg.begins_with("--repair-model=") and not _repair_model_supplied:
			repair_model = arg.trim_prefix("--repair-model=")
			_repair_model_supplied = true
		else: check(false,"unknown or duplicate argument")
	check(repair_model in ["legacy_cap","workstations"],"repair model must be legacy_cap or workstations")
	check(output.begins_with("res://docs/research/evidence/crew-role-effects/") and output.ends_with(".json") and not output.contains("..") and not output.contains("\\") and not FileAccess.file_exists(output) and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output)),"fresh confined JSON output required")
	verify_comparison_contract()
	if not failures.is_empty(): finish(); return
	var source_before := {SOURCE:FileAccess.get_sha256(SOURCE),SELF_SOURCE:FileAccess.get_sha256(SELF_SOURCE)}
	var started := Time.get_ticks_usec()
	for environment: String in ["balanced","scarce"]:
		for specialists: bool in [false,true]:
			for seconds: int in WINDOWS:
				var members: Array = []
				for strategy: String in STRATEGIES:
					var row := run_case(environment,specialists,seconds,strategy)
					if row.is_empty(): finish(); return
					cases.append(row)
					members.append(row)
				groups.append(compare_group(environment,specialists,seconds,members))
	var duration_us := Time.get_ticks_usec()-started
	check(cases.size() == 84 and groups.size() == 12,"84 cases and 12 comparable scenario groups")
	var source_after := {SOURCE:FileAccess.get_sha256(SOURCE),SELF_SOURCE:FileAccess.get_sha256(SELF_SOURCE)}
	check(source_before == source_after,"source hashes stable throughout sweep")
	var pair_count := 0
	for group: Dictionary in groups: pair_count += group.dominance.size()
	var report := {
		"valid":failures.is_empty(),"failures":failures,"assertions":assertions,
		"scope":"CPU-only fixed-step numerical experiment through public crew rules API; no combat simulation, GPU, production campaign, player acceptance, weighted score or win rate.",
		"engine":Engine.get_version_info(),"displayServer":DisplayServer.get_name(),"fixedStep":STEP,"repairModel":repair_model,
		"caseCount":cases.size(),"comparisonGroupCount":groups.size(),"dominancePairCount":pair_count,
		"sourceBefore":source_before,"sourceAfter":source_after,
		"timing":{"microseconds":duration_us,"scope":"Entire CPU sweep including snapshots and invariant assertions; not isolated kernel time and not frame rate."},
		"comparisonContract":{
			"groupBy":["environment","specialists","seconds"],"maximize":MAXIMIZE,"minimize":MINIMIZE,"epsilon":EPSILON,
			"dominance":"A is no worse than B on every declared axis within absolute epsilon, and better by more than epsilon on at least one. Epsilon uses each axis's stated unit; no cross-axis normalization or scalar score.",
			"units":{"gun_efficiency_seconds":"integral of dimensionless gun service over seconds","hull_gain":"game hull points at endpoint","morale_gain":"game morale points at endpoint","fatigue_reduction":"sum of 12 workers' game fatigue reduction","cooked_rations_remaining":"actual uneaten cooked portions","grain_used":"raw portions consumed","wood_used":"game wood units consumed"},
			"meals":"Cooked/eaten meal counts are recorded; eaten meals are not an additional objective because their fatigue effect is already included. Remaining cooked food is an asset axis, not discarded as waste.",
			"specialists":"Compare only within the same specialists value. Specialist recruitment, wage, training and opportunity costs do not exist; true/false is an ability control, not a fair economic matchup.",
			"policy":"Each strategy assigns once at time zero and keeps jobs fixed. No optimized return to guns after reaching repair cap; no tactical reassignment search."
		},
		"limitations":[
			"Gun service is an abstract capped scalar. No ammunition, reload cycle, volley, firing arcs, hit probability, damage, casualties, redundancy value or enemy pressure is modelled.",
			"Endpoint hull and morale do not price earlier recovery or ship survival before the deadline. Faster repair may matter in combat even when equal at the endpoint.",
			"No wages, specialist acquisition cost, fatigue generation from active work, hunger penalty, injuries, role switching time or travel between stations.",
			"A dominated static policy here is a concrete diagnostic for this fixture and these objective axes, not proof it is always bad in the intended game. Non-dominated does not mean balanced or enjoyable.",
			"Finite supplies and repair/food capacity can eliminate future marginal work. This sweep reports when that happens; it never edits rates to hide the result."
		],
		"fixtures":fixtures,"cases":cases,"groups":groups
	}
	if not check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir())) == OK,"create evidence parent"): finish(); return
	if not check(not FileAccess.file_exists(output),"output still absent before write"): finish(); return
	var file := FileAccess.open(output,FileAccess.WRITE)
	if not check(file != null,"open fresh report"): finish(); return
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("CREW_BALANCE_RESULT cases=",cases.size()," groups=",groups.size()," repair_model=",repair_model," dominance_pairs=",pair_count," cpu_us=",duration_us," output=",output)
	finish()

func run_case(environment: String, specialists: bool, seconds: int, strategy: String) -> Dictionary:
	var rules := Rules.new()
	var id := "%s-%s-%ds-%s" % [environment,"specialist" if specialists else "ordinary",seconds,strategy]
	if not check(rules.configure({"preset":environment,"specialists":specialists,"repair_model":repair_model}).get("ok",false),id+": configure"): return {}
	var initial: Dictionary = rules.snapshot()
	var fixture_key := repair_model+":"+environment+":"+str(specialists)
	if not fixtures.has(fixture_key): fixtures[fixture_key] = initial.duplicate(true)
	if not check(initial == fixtures[fixture_key],id+": identical initial personnel, supplies and state"): return {}
	for assignment: Array in STRATEGIES[strategy]:
		if not check(rules.assign(assignment[0],assignment[1]).get("ok",false),id+": assignment accepted"): return {}
	var assigned: Dictionary = rules.snapshot()
	if not check(physical_state(assigned) == physical_state(initial),id+": assigning jobs does not grant resources or change people"): return {}
	var initial_fatigue := total_fatigue(initial)
	var gun_integral := 0.0
	var state: Dictionary = assigned
	var milestones := {"grain_exhausted_at":null,"wood_exhausted_at":null,"repair_cap_at":null,"ration_cap_at":null}
	for tick in range(seconds*32):
		gun_integral += float(state.gun_efficiency)*STEP
		rules.step()
		state = rules.snapshot()
		if not validate_state(state,initial,id,tick+1): return {}
		if milestones.grain_exhausted_at == null and state.grain <= EPSILON: milestones.grain_exhausted_at = state.time
		if milestones.wood_exhausted_at == null and state.wood <= EPSILON: milestones.wood_exhausted_at = state.time
		if milestones.repair_cap_at == null and state.hull >= float(state.sea_repair_cap)-EPSILON: milestones.repair_cap_at = state.time
		if milestones.ration_cap_at == null and state.cooked_rations >= Rules.RATION_CAP-EPSILON: milestones.ration_cap_at = state.time
	var ledger: Dictionary = state.ledger
	var metrics := {
		"gun_efficiency_seconds":gun_integral,"gun_efficiency_mean":gun_integral/seconds,
		"hull_gain":float(state.hull)-float(initial.hull),"morale_gain":float(state.morale)-float(initial.morale),
		"fatigue_reduction":initial_fatigue-total_fatigue(state),"cooked_rations_remaining":state.cooked_rations,
		"grain_used":ledger.grain_used,"wood_used":ledger.wood_used,"meals_cooked":ledger.meals_cooked,"meals_eaten":ledger.meals_eaten
	}
	if not check(all_finite(metrics),id+": finite metrics"): return {}
	return {"id":id,"environment":environment,"specialists":specialists,"seconds":seconds,"strategy":strategy,"assignments":STRATEGIES[strategy].duplicate(true),"initial":assigned,"final":state,"metrics":metrics,"milestones":milestones,"counts":state.counts.duplicate(true)}

func physical_state(state: Dictionary) -> Dictionary:
	var result: Dictionary = state.duplicate(true)
	for key: String in ["counts","rates","gun_efficiency","repair_staffing"]: result.erase(key)
	for worker: Dictionary in result.workers: worker.erase("role")
	return result

func total_fatigue(state: Dictionary) -> float:
	var total := 0.0
	for worker: Dictionary in state.workers: total += float(worker.fatigue)
	return total

func all_finite(value: Variant) -> bool:
	if value is float: return is_finite(value)
	if value is Dictionary:
		for child: Variant in value.values():
			if not all_finite(child): return false
	elif value is Array:
		for child: Variant in value:
			if not all_finite(child): return false
	return true

func validate_state(state: Dictionary, initial: Dictionary, id: String, tick: int) -> bool:
	if not check(all_finite(state),id+": finite state"): return false
	if not check(state.tick == tick and state.time == tick*STEP,id+": fixed clock"): return false
	var seen := {}
	var counts := {"cook":0,"musician":0,"carpenter":0,"gunner":0,"rest":0}
	for worker: Dictionary in state.workers:
		if not check(not seen.has(worker.id) and worker.role in Rules.ROLES,id+": no duplicate person or invalid role"): return false
		seen[worker.id] = true
		counts[worker.role] += 1
		if not check(worker.fatigue >= 0.0 and worker.fatigue <= 100.0,id+": fatigue bound"): return false
	if not check(seen.size() == 12 and counts == state.counts,id+": exactly twelve uniquely assigned workers"): return false
	var l: Dictionary = state.ledger
	var conserved := absf(initial.grain-state.grain-l.grain_used) <= EPSILON and absf(l.grain_used-l.meals_cooked) <= EPSILON and absf(l.meals_cooked-l.meals_eaten-state.cooked_rations) <= EPSILON and absf(initial.wood-state.wood-l.wood_used) <= EPSILON and absf(l.wood_used-l.hull_repaired*0.5) <= EPSILON and absf(state.hull-initial.hull-l.hull_repaired) <= EPSILON
	return check(conserved and state.grain >= 0.0 and state.wood >= 0.0 and state.cooked_rations >= 0.0 and state.cooked_rations <= Rules.RATION_CAP+EPSILON and state.hull <= state.sea_repair_cap+EPSILON and state.morale >= 0.0 and state.morale <= 100.0 and state.gun_efficiency >= 0.0 and state.gun_efficiency <= 1.0,id+": resource conservation and bounds")

func compare_group(environment: String, specialists: bool, seconds: int, members: Array) -> Dictionary:
	var dominance: Array = []
	var equivalent: Array = []
	var dominated_ids := {}
	for i in members.size():
		for j in members.size():
			if i == j: continue
			var a: Dictionary = members[i]
			var b: Dictionary = members[j]
			var relation := compare_metrics(a.metrics,b.metrics)
			if relation.dominates:
				dominated_ids[b.id] = true
				dominance.append({"dominant":a.strategy,"dominated":b.strategy,"betterAxes":relation.better_axes,"deltasDominantMinusDominated":relation.deltas,"interpretation":explain(a,b)})
			elif relation.equivalent and i < j:
				equivalent.append([a.strategy,b.strategy])
	var frontier: Array = []
	for row: Dictionary in members:
		if not dominated_ids.has(row.id): frontier.append(row.strategy)
	return {"environment":environment,"specialists":specialists,"seconds":seconds,"nonDominated":frontier,"dominance":dominance,"equivalentOnDeclaredAxes":equivalent}

func compare_metrics(a: Dictionary, b: Dictionary) -> Dictionary:
	var no_worse := true
	var better: Array = []
	var deltas := {}
	for axis: String in MAXIMIZE+MINIMIZE:
		var delta := float(a[axis])-float(b[axis])
		deltas[axis] = delta
		var benefit := delta if axis in MAXIMIZE else -delta
		if benefit < -EPSILON: no_worse = false
		if benefit > EPSILON: better.append(axis)
	return {"dominates":no_worse and not better.is_empty(),"equivalent":no_worse and better.is_empty(),"better_axes":better,"deltas":deltas}

func verify_comparison_contract() -> void:
	var base := {}
	for axis: String in MAXIMIZE+MINIMIZE: base[axis] = 0.0
	check(not compare_metrics(base,base).dominates and compare_metrics(base,base).equivalent,"Pareto equality is not strict dominance")
	var better: Dictionary = base.duplicate()
	better.hull_gain = 1.0
	check(compare_metrics(better,base).dominates and not compare_metrics(base,better).dominates,"Pareto strict benefit direction")
	better.grain_used = 1.0
	check(not compare_metrics(better,base).dominates and not compare_metrics(base,better).dominates,"Pareto resource tradeoff stays incomparable")
	var cheaper: Dictionary = better.duplicate()
	cheaper.grain_used = 0.0
	check(compare_metrics(cheaper,better).dominates,"Pareto cost direction is reversed")
	var noise: Dictionary = base.duplicate()
	noise.hull_gain = EPSILON*0.5
	check(compare_metrics(noise,base).equivalent and not compare_metrics(noise,base).dominates,"Pareto epsilon cannot manufacture strict dominance")

func explain(a: Dictionary, b: Dictionary) -> Array:
	var notes: Array = []
	if a.strategy == "one_gunner_to_repair" and b.strategy == "repair_detachment" and absf(a.initial.rates.repair-b.initial.rates.repair) <= EPSILON:
		if repair_model == "legacy_cap":
			notes.append("旧模型将全船维修工时封顶；初态抽调一人后已触顶，第二名炮手未增加修船速率，却降低炮位效率。该基线保留冗余调岗缺陷。")
		else:
			notes.append("工作位模型在本案测得一人与两人调修初始速率相同；应检查repair_staffing的active、waiting与worker_ids，不把这一状态推广到全部人员配置。")
	if repair_model == "workstations" and a.strategy == "one_gunner_to_repair" and b.strategy == "repair_detachment" and b.initial.rates.repair > a.initial.rates.repair+EPSILON:
		notes.append("三工作位模型中第二名调修炮手确实提高初始维修速率。本时窗期末被支配只说明这些终点目标已失去提前修好的价值，不能解释为第二人恒无收益。")
	if b.strategy == "no_musician" and absf(a.initial.gun_efficiency-b.initial.gun_efficiency) <= EPSILON:
		notes.append("原炮位效率已饱和；增派乐师去炮位未提高当前枪效率，却损失士气恢复。模型尚无齐射、伤亡替补、轮班和复杂装填来表达额外炮手价值。")
	if b.strategy in ["repair_detachment","one_gunner_to_repair"] and absf(a.metrics.hull_gain-b.metrics.hull_gain) <= EPSILON:
		notes.append("时窗结束修复量相同；请对照初始维修速率与耗尽/达顶时刻解释。这里没有途中受击、防沉压力与修复时序价值，长期末端相同不等于短窗维修速度相同。")
	if a.milestones.wood_exhausted_at != null or b.milestones.wood_exhausted_at != null:
		notes.append("有限木材已耗尽，之后修船岗位继续占人；本扫描故意不自动返岗，以暴露静态策略边际收益消失。")
	if a.milestones.repair_cap_at != null or b.milestones.repair_cap_at != null:
		notes.append("至少一方已达海修上限，额外维修工时不再增加船体。到顶返岗策略未列入本次七种固定配置。")
	if a.milestones.grain_exhausted_at != null or b.milestones.grain_exhausted_at != null:
		notes.append("至少一方食材已经耗尽；庖师后续生产停止，剩余熟食仍计入库存收益轴。")
	if notes.is_empty(): notes.append("仅按列出的同向收益与反向成本成立；检查betterAxes和差值，不等同总体战力或胜率。")
	return notes

func finish() -> void:
	print("CREW_BALANCE_TESTS assertions=",assertions," cases=",cases.size()," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
