extends SceneTree
const Encounter=preload("res://modules/naval_simulation/encounter.gd")
const Fire=preload("res://modules/naval_simulation/combat/fire_control.gd")
const Launcher=preload("res://modules/naval_simulation/combat/fire_launcher.gd")
const Cannon=preload("res://modules/naval_simulation/combat/cannon_system.gd")
var assertions:=0
var failures:=0
func check(value:bool,detail:String)->void:
	assertions+=1
	if not value:failures+=1;printerr("FAIL: ",detail)
func setup(id:String,team:String,z:float)->Dictionary:
	return {"id":id,"kind":"fuchuan","team":team,"position":{"x":0.0,"z":z},"heading":0.0,"sailDeployment":0.0,"fireControl":Fire.initial(24),"fireLauncher":Launcher.initial(2,2)}
func ship(game:RefCounted,id:String)->Dictionary:
	return game.snapshot().ships.filter(func(s):return s.id==id)[0]
func _initialize()->void:
	var game:=Encounter.new({"ships":[setup("p","player",0.0),setup("e","hostile",60.0)],"playerId":"p","wind":{"direction":{"x":-1.0,"y":0.0},"speed":0.0}})
	check(game.last_error.is_empty(),"fire skirmish fixture valid")
	for tick in 61:game.step_fixed()
	check(ship(game,"e").fireLauncher.ammo["fire-ball"]==1,"equipped AI uses its real launcher")
	var events:Array=game.drain_events()
	check(events.any(func(e):return e.type=="fire-payload-launched" and e.shipId=="e"),"AI attack has original ballistic event")
	var hot:Dictionary=setup("p","player",0.0)
	hot.fireControl=Fire.ignite(Fire.initial(64),"fire-ball",0.0).state
	var fallen:Dictionary=setup("e","hostile",60.0);fallen.hull=0.0
	var aftermath:=Encounter.new({"ships":[hot,fallen],"playerId":"p","wind":{"direction":{"x":-1.0,"y":0.0},"speed":0.0}})
	aftermath.step_fixed()
	check(aftermath.snapshot().status=="active","last hostile gone does not freeze a burning flagship with a victory modal")
	check(aftermath.command({"type":"fire-control","shipId":"p","crew":4}).ok,"survivor can still order damage control after enemy sinks")
	for tick in 1800:
		if aftermath.snapshot().status=="victory":break
		aftermath.step_fixed()
	check(aftermath.snapshot().status=="victory" and ship(aftermath,"p").fireControl.heat==0.0,"victory follows actual quench and crew return")
	check(Fire.reserved_crew(ship(aftermath,"p").fireControl,int(ship(aftermath,"p").crew))==0,"result does not strand returning damage-control crew")
	var defended:Dictionary=setup("e","hostile",60.0)
	defended.fireControl=Fire.ignite(Fire.initial(24),"thorn-ball",0.0).state
	var defense:=Encounter.new({"ships":[setup("p","player",0.0),defended],"playerId":"p"})
	for tick in 61:defense.step_fixed()
	check(ship(defense,"e").fireControl.pendingFirefighters==4,"equipped AI commits four real people to a live fire")
	var native:Dictionary=game.snapshot();native.ships[0].availableCrew=0
	check(Cannon.broadside_status(native,"p","starboard").phase=="not-operational","cannon readout respects available workers")
	print("FIRE_SKIRMISH_NATIVE_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
