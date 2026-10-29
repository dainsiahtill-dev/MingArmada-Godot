extends RefCounted
## Research-only event projection. Never writes campaign or gameplay authority.
const DISPLAY_SECONDS := 3.0
var _epoch := ""
var _flagship := ""
var _policy: Dictionary = {}
var _ships: Dictionary = {}
var _shots: Dictionary = {}
var _seen: Dictionary = {}
var _display: Dictionary = {}

func reset(epoch: String, flagship: String, policy: Dictionary, ships: Dictionary) -> void:
	_epoch = epoch; _flagship = flagship
	_policy = policy.duplicate(true); _ships = ships.duplicate(true)
	_shots.clear(); _seen.clear(); _display.clear()

func consume(event: Dictionary, now: float) -> void:
	if _epoch.is_empty() or _flagship.is_empty() or not is_finite(now) or now < 0.0: return
	var id := str(event.get("id",""))
	var kind := str(event.get("type",""))
	var shot := str(event.get("projectileId",""))
	if id.is_empty() or shot.is_empty() or _seen.has(id) or event.get("shipId") != _flagship: return
	if kind not in ["fire","hit","splash"]: return
	_seen[id] = true
	if kind == "fire":
		var side := str(event.get("side",""))
		if side in ["port","starboard"] and not _shots.has(shot): _shots[shot] = {"side":side,"resolved":false}
		return
	if not _shots.has(shot) or _shots[shot].resolved: return
	var side_text := "左舷" if _shots[shot].side == "port" else "右舷"
	var text := side_text + "炮弹未命中"
	var rank := 1
	if kind == "hit":
		var target := str(event.get("targetId",""))
		if target.is_empty(): return
		var ship: Dictionary = _ships.get(target,{})
		var name := str(ship.get("name",target))
		var label := "船只"
		var hostile: Dictionary = _policy.get("hostileTargets",{})
		if target not in _policy.get("capturedShipIds",[]) and hostile.has(_flagship) and target in hostile[_flagship]: label = "敌船"
		elif ship.get("team","") != "" and ship.get("team") != "neutral" and ship.get("team") == _ships.get(_flagship,{}).get("team"): label = "友船"
		text = side_text + "命中 · " + label + name
		rank = 2
	_shots[shot].resolved = true
	if _display.is_empty() or now >= float(_display.until) or rank >= int(_display.rank):
		_display = {"text":text,"rank":rank,"until":now + DISPLAY_SECONDS,"eventId":id,"projectileId":shot}

func snapshot(now: float) -> Dictionary:
	var current := _display.duplicate(true) if not _display.is_empty() and now < float(_display.until) else {}
	return {"epoch":_epoch,"text":current.get("text",""),"receipt":current,"shotCount":_shots.size(),"seenCount":_seen.size()}
