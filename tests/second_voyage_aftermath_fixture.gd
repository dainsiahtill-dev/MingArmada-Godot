extends RefCounted
## Constructed automation fixtures through real Campaign boundaries, never player journey proof.
const Campaign=preload("res://game/domain/mingqi/campaign.gd")
const Runtime=preload("res://game/runtime/mingqi_runtime.gd")

static func envelope(s: Dictionary) -> String:
	return JSON.stringify({"version":2,"campaignId":s.campaignId,"mode":"mingqi-1650","savedAtUtc":"2026-10-12T00:00:00.000Z","simulationSeconds":s.simulationSeconds,"state":s},"",false,true)

static func make_claim(kind: String="full") -> Dictionary:
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/mingqi-reference.json"))
	var c:=Campaign.new()
	if not c.restore(envelope(fixture.convoySteps[6].state)):return {}
	if kind=="late" and not c.advance(1300,c.snapshot().vessels.keys()).ok:return {}
	var observation: Dictionary=fixture.convoySteps[7].native.duplicate(true)
	var events=[]
	if kind=="partial":events.append({"id":"constructed-cargo-loss","type":"hit","time":observation.time,"shipId":"convoy-enemy","targetId":"convoy-grain-a","ammo":"solid","damage":{"hull":0,"sail":0,"crew":0}})
	if kind=="zero":
		for ship in observation.ships:
			if ship.id in ["convoy-grain-a","convoy-grain-b"]:ship.hull=0;ship.crew=0
	if not c.sync_near(observation,events).ok:return {}
	var result: Dictionary=c.command({"type":"claim-convoy","contractId":"convoy-002","commandId":"constructed-second-claim-"+kind,"expectedRevision":c.snapshot().revision})
	return c.snapshot() if result.ok else {}

static func safe_witness(s: Dictionary,port_id: String="forward-supply") -> Dictionary:
	return {"flagshipId":s.flagshipId,"position":s.ports[port_id].position.duplicate(true),"speed":0,"hull":100,"anchored":true,"pendingAttacks":false,"activeBoardings":0,"hostileWithin600":false}

static func record_choice(s: Dictionary,result: Dictionary,command_id: String="constructed-aftermath") -> Dictionary:
	var id: String=s.campaignId+":story:second-return"
	var receipt={"id":id,"commandId":command_id,"revision":s.revision+1,"kind":"story-choice","message":result.message,"details":result.details.duplicate(true)}
	s.revision+=1;s.settlements[id]=receipt
	s.chronicle.append({"id":id,"kind":"story-choice","causeIds":[command_id,id],"simTime":s.simulationSeconds,"date":s.calendar.duplicate(true),"message":receipt.message})
	return receipt

static func casualty(s: Dictionary,ship_id: String,able: int,hull: int=100) -> bool:
	var c:=Campaign.new();c._state=s.duplicate(true)
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/mingqi-reference.json"))
	var observation: Dictionary=fixture.convoySteps[7].native.duplicate(true)
	observation.tick=100+s.revision;observation.time+=1
	for ship in observation.ships:
		ship.controlsSequence=100+s.revision
		ship.crew=s.vessels[ship.id].crew.able;ship.hull=s.vessels[ship.id].damage.hull
		if ship.id==ship_id:ship.crew=able;ship.hull=hull
	var ok: bool=c.sync_near(observation,[]).ok
	if ok:s.merge(c.snapshot(),true)
	return ok
