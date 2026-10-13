extends SceneTree
var assertions := 0
var failures := 0
func check(ok:bool,message:String)->void:
	assertions+=1
	if not ok: failures+=1; printerr("FAIL: ",message)
func _initialize()->void: _run.call_deferred()
func json(name:String)->Dictionary: return JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/source_wake/"+name))
func ints(value:Variant)->Variant:
	if value is Array:
		var out:Array=[]
		for child:Variant in value:out.append(ints(child))
		return out
	if value is Dictionary:
		var out:Dictionary={}
		for key:Variant in value:out[key]=ints(value[key])
		return out
	return int(value) if value is float else value
func _run()->void:
	var history_script=load("res://modules/scene_engine/water/source_wake_history.gd") if FileAccess.file_exists("res://modules/scene_engine/water/source_wake_history.gd") else null
	check(history_script!=null,"original 30 point history implementation exists")
	if history_script:
		var setups={"initial":[],"equal_distance":[[[100,100,0],0.0]],"just_over_distance":[[[100,100,0],0.0]],"stop_older_clock":[[[100,100,0],0.0],[[103,100,0],0.1]],"same_time_move":[[[100,100,0],0.0]],"rewind":[[[100,100,0],0.0],[[103,100,0],1.0]],"teleport_equal":[[[100,100,0],0.0]],"teleport_over":[[[100,100,0],0.0],[[104,100,0],0.1]],"marker_changed":[[[100,100,0],0.0],[[104,100,0],0.1]],"reverse":[[[100,100,0],0.0],[[104,100,0],0.1]],"three_dimensional":[[[100,100,0],0.0]],"wrap":[]}
		for i in 36: setups.wrap.append([[100+4*i,100,0],float(i)/10])
		for fixture:Dictionary in json("ORIGINAL_HISTORY_VERIFY.json").fixtures:
			var history=history_script.new()
			for step:Array in setups[fixture.name]: history.update(step[0],step[1])
			history.update(fixture.position,fixture.now,2 if fixture.name=="marker_changed" else 1)
			check(history.ring_bytes().hex_encode()==fixture.ring_hex,"original byte ring "+fixture.name)
			check(history.head==int(fixture.head) and history.updates==int(fixture.updates) and history.vertex_count==int(fixture.mesh_vertex_count),"original control fields "+fixture.name)
		var profile=json("ORIGINAL_PROFILE_VERIFY.json")
		for fixture:Dictionary in profile.curves:
			check(absf(history_script.curve(fixture.x,fixture.scale,fixture.offset)-float(fixture.native_result))<0.0000000001,"original bitmap interpolation binary32 stores")
		for fixture:Dictionary in profile.widths:
			check(absf(history_script.half_width(fixture.scale,fixture.distance_fraction,fixture.age_clamped,40.0)-float(fixture.native_half_width))<=0.0000153,"original two model scale width branches")
		for fixture:Dictionary in profile.alphas:
			check(history_script.row_alpha(int(fixture.update_count),int(fixture.row_vertex_index))==history_script.f32(fixture.native),"original update-count row alpha")
		for fixture:Dictionary in profile.profile_stores:
			var out:Dictionary=history_script.profile_ratios(fixture.input)
			check(out.age==history_script.f32(fixture.native_age_clamped) and out.fraction==history_script.f32(fixture.native_distance_fraction) and out.domain==history_script.f32(fixture.native_spread_domain),"original history-to-profile stored ratios "+fixture.trajectory)
		var zero=history_script.new(); zero.update([100,100,0],0.0)
		check(zero.profile()[0].diagnostic_adaptation.native_equivalent==false,"zero-length finite diagnostic marks original NaN path unexecuted")
	var battle_script=load("res://modules/scene_engine/water/source_battle_trail.gd") if FileAccess.file_exists("res://modules/scene_engine/water/source_battle_trail.gd") else null
	check(battle_script!=null,"original 90 history battle implementation exists")
	if battle_script:
		for fixture:Dictionary in json("BATTLE_ORIGINAL_FIXTURES.json").cases:
			var out:Dictionary=battle_script.draw(ints(fixture.input))
			check(out.history==ints(fixture.native_history),"original 90-word history "+fixture.name)
			check(out.draw_arguments==ints(fixture.native_draw_arguments),"original 7x3 draw arguments "+fixture.name)
			check(out.draw_arguments.size()==21,"21 original layer submits "+fixture.name)
	print("SOURCE_WAKE_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
