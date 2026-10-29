extends RefCounted
## Isolated trial prices, not historical wages or a campaign economy.
## Only explicit voyage-day receipts settle wages; battle seconds never do.

const ROSTERS := ["ordinary", "mixed", "elite"]
const PRICE_VERSION := "crew-contract-r1"
const ORDINARY_RECRUITMENT := 8
const SPECIALIST_RECRUITMENT := 16
const ORDINARY_DAILY_WAGE := 1
const SPECIALIST_DAILY_WAGE := 2

var _state: Dictionary = {}
var _daily_wage := 0

func configure(options: Dictionary = {}) -> Dictionary:
	for key in options:
		if key not in ["roster", "budget", "days"]:
			return {"ok":false,"error":"unknown option"}
	var roster = options.get("roster", "ordinary")
	var budget = options.get("budget", 144)
	var days = options.get("days", 4)
	if not roster is String or roster not in ROSTERS:
		return {"ok":false,"error":"invalid roster"}
	if typeof(budget) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(budget)) or budget < 0:
		return {"ok":false,"error":"invalid budget"}
	if typeof(days) != TYPE_INT or days <= 0:
		return {"ok":false,"error":"invalid contract days"}
	var hired_count := 12 if roster == "ordinary" else (10 if roster == "mixed" else 6)
	var hired_ids: Array = []
	var qualified_ids: Array = []
	var recruitment_paid := 0
	var daily_wage := 0
	for index in range(hired_count):
		var id := "crew%02d" % (index + 1)
		var qualified: bool = roster == "elite" or (roster == "mixed" and id in ["crew03", "crew04"])
		hired_ids.append(id)
		if qualified: qualified_ids.append(id)
		recruitment_paid += SPECIALIST_RECRUITMENT if qualified else ORDINARY_RECRUITMENT
		daily_wage += SPECIALIST_DAILY_WAGE if qualified else ORDINARY_DAILY_WAGE
	var wage_reserved := float(days) * float(daily_wage)
	var total_committed := float(recruitment_paid) + wage_reserved
	if not is_finite(total_committed) or total_committed > float(budget):
		return {"ok":false,"error":"insufficient budget"}
	var next_state := {
		"price_version":PRICE_VERSION,
		"currency":"trial_coin",
		"roster":roster,
		"hired_ids":hired_ids,
		"qualified_ids":qualified_ids,
		"hired_count":hired_count,
		"budget":float(budget),
		"recruitment_paid":recruitment_paid,
		"wage_reserved":wage_reserved,
		"wages_paid":0.0,
		"free_cash":float(budget) - total_committed,
		"day":0,
		"days":days,
		"total_committed":total_committed,
		"phase_receipts":{},
	}
	_state = next_state
	_daily_wage = daily_wage
	return {"ok":true}

func settle(phase_id: Variant, day: Variant) -> Dictionary:
	if _state.is_empty():
		return {"ok":false,"error":"contract not configured"}
	if not phase_id is String or not day is int or phase_id.strip_edges().is_empty() or day < 0 or day > int(_state.days):
		return {"ok":false,"error":"invalid settlement phase or day"}
	# A previously accepted receipt remains replayable after later phases.
	if _state.phase_receipts.has(phase_id):
		if int(_state.phase_receipts[phase_id]) != day:
			return {"ok":false,"error":"settlement receipt conflict"}
		return {"ok":true}
	if day < int(_state.day):
		return {"ok":false,"error":"contract day cannot move backward"}
	_state.day = day
	_state.wages_paid = float(day) * float(_daily_wage)
	_state.wage_reserved = float(int(_state.days) - day) * float(_daily_wage)
	_state.phase_receipts[phase_id] = day
	return {"ok":true}

func snapshot() -> Dictionary:
	return _state.duplicate(true)
