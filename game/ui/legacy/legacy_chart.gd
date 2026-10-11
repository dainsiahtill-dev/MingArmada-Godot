extends Control
signal waypoint_requested(point:Dictionary)
const Catalog=preload("res://game/domain/legacy/catalog.gd")
const Text=preload("res://game/domain/legacy/utf16_text.gd")
var snapshot:Dictionary={}
func _ready():custom_minimum_size=Vector2(0,230);mouse_filter=Control.MOUSE_FILTER_STOP
func apply_snapshot(value:Dictionary):snapshot=value.duplicate(true);queue_redraw()
func projected(point):return Vector2((point.get("x",0)+1000)/2400.0*size.x,(point.get("z",0)+800)/1750.0*size.y)
func _draw():
	draw_rect(Rect2(Vector2.ZERO,size),Color("123f41"))
	var font=get_theme_default_font()
	for port in Catalog.DATA.PORTS:
		var island=projected({"x":port.islandX,"z":port.islandZ});draw_circle(island,port.radius/2400.0*size.x,Color("527e68"));var p=projected(port);draw_circle(p,4,Color("e4c781"));draw_string(font,p+Vector2(7,-5),Text.display_text(port.name),HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("fff2d5"))
	for site in Catalog.DATA.LAND_SITES:draw_rect(Rect2(projected(site)-Vector2(2,2),Vector2(4,4)),Color("f4dec3"))
	for objective in snapshot.get("activeObjectives",[]):
		var p=projected(objective.get("position",{}));draw_arc(p,7,0,TAU,24,Color("ed9871"),2);draw_string(font,p+Vector2(8,14),Text.display_text(str(objective.get("label",""))),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("ffd0ad"))
	for ship in snapshot.get("fleet",[]):
		var p=projected(ship.get("position",snapshot.get("position",{})));draw_circle(p,5,Color("fff5cc") if ship.id==snapshot.get("flagshipId") else Color("84ded0"))
	draw_string(font,Vector2(10,20),"北 ↑ · 金色锚地 / 朱色目标",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("fff2d5"))
func _gui_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT and size.x>0 and size.y>0:
		waypoint_requested.emit({"x":event.position.x/size.x*2400-1000,"z":event.position.y/size.y*1750-800});accept_event()
