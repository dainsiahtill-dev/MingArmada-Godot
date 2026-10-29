extends SceneTree
## Isolated native StyleBox composition proof. --gpu-probe renders actual Panels;
## default mode checks public resource and native layout contracts headlessly.
const HELPER_PATH := "res://game/ui/shared/painted_window_style.gd"
const QUIET := "res://assets/ui/ming_maritime/painted/quiet/runtime/"
const FRAMED := "res://assets/ui/ming_maritime/painted/quiet/framed/runtime/"
const OUTPUT := "res://docs/design/2026-10-27-painted-ui/evidence/painted-window-probe-v3"
var assertions := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func check(value: bool,detail: String) -> bool:
	assertions+=1
	if not value: failures+=1;printerr("FAIL: ",detail)
	return value

func _plain(filename: String) -> StyleBoxTexture:
	var result := StyleBoxTexture.new()
	result.texture=load(QUIET+filename)
	result.region_rect=Rect2(Vector2.ZERO,result.texture.get_size())
	result.set_texture_margin_all(8)
	result.set_content_margin_all(24)
	return result

func _run() -> void:
	if not check(ResourceLoader.exists(HELPER_PATH),"compositor helper exists"):
		_finish();return
	var helper=load(HELPER_PATH)
	if not check(helper!=null and helper.can_instantiate(),"compositor helper parses"):
		_finish();return
	var body := _plain("command-panel.png")
	var edge: StyleBoxTexture=helper.framed_edge(load(FRAMED+"command-panel.png"))
	var layered: StyleBox=helper.compose(body,edge)
	check(layered!=null and layered.call("get_body_style").texture==body.texture,"compositor getter retains quiet body texture authority")
	check(layered.call("get_edge_style").texture==edge.texture,"compositor getter retains generated edge texture authority")
	var duplicate: StyleBox=layered.duplicate(true)
	check(duplicate.call("get_body_style")!=null and duplicate.call("get_edge_style")!=null,"native resource duplication preserves both drawing layers")
	check(layered.get_minimum_size()==body.get_minimum_size(),"frame caps do not enlarge native content minimum")
	check(layered.get_margin(SIDE_TOP)==body.get_margin(SIDE_TOP) and layered.get_margin(SIDE_LEFT)==body.get_margin(SIDE_LEFT),"native content margins retain the body contract")
	check(not edge.draw_center,"frame layer leaves reading center unpainted")
	# Independently measured frozen source bounds; geometry must keep the
	# complete top transparent band and bottom shadow outside the hit rectangle.
	check(edge.get_texture_margin(SIDE_TOP)>=48 and edge.get_texture_margin(SIDE_BOTTOM)>=46,"command edge protects its 40px transparent head and soft shadow caps")
	check(edge.get_texture_margin(SIDE_LEFT)>=18 and edge.get_texture_margin(SIDE_RIGHT)>=21,"command edge protects side line and shadow caps")
	var folio: StyleBoxTexture=helper.framed_edge(load(FRAMED+"folio-panel.png"))
	check(folio.get_texture_margin(SIDE_LEFT)>=29 and folio.get_texture_margin(SIDE_TOP)>=27,"folio edge protects measured 22px spine-side and 20px head")
	var draw: Rect2 = layered.call("_get_draw_rect",Rect2(0,0,200,100))
	check(draw.position.x<0 and draw.position.y<=-40 and draw.end.x>200 and draw.end.y>100,"compositor draw bounds include decorative line and shadow")
	layered.set_expand_margin(SIDE_TOP,32)
	var expanded: Rect2=layered.call("_get_draw_rect",Rect2(0,0,200,100))
	check(expanded.position.y<=draw.position.y-32,"outer Window title expansion extends both layers' drawing bounds")
	print("PAINTED_WINDOW_GEOMETRY command=",edge.get_texture_margin(SIDE_LEFT),",",edge.get_texture_margin(SIDE_TOP),",",edge.get_texture_margin(SIDE_RIGHT),",",edge.get_texture_margin(SIDE_BOTTOM)," expand=",edge.get_expand_margin(SIDE_LEFT),",",edge.get_expand_margin(SIDE_TOP),",",edge.get_expand_margin(SIDE_RIGHT),",",edge.get_expand_margin(SIDE_BOTTOM)," folio=",folio.get_texture_margin(SIDE_LEFT),",",folio.get_texture_margin(SIDE_TOP),",",folio.get_texture_margin(SIDE_RIGHT),",",folio.get_texture_margin(SIDE_BOTTOM))
	if "--gpu-probe" in OS.get_cmdline_user_args():
		await _gpu(helper)
	_finish()

func _panel(parent: Node,position: Vector2,extent: Vector2,style: StyleBox,caption: String) -> Panel:
	var panel := Panel.new();parent.add_child(panel)
	panel.position=position;panel.size=extent;panel.add_theme_stylebox_override("panel",style)
	var label := Label.new();panel.add_child(label);label.position=Vector2(24,24);label.text=caption
	label.add_theme_color_override("font_color",Color("eadfca"));label.add_theme_font_size_override("font_size",16)
	return panel

func _gpu(helper) -> void:
	if not check(DisplayServer.get_name()!="headless","GPU probe uses a native graphics display"): return
	root.size=Vector2i(640,420)
	var viewport := SubViewport.new();viewport.size=Vector2i(640,420)
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var backdrop := ColorRect.new();backdrop.color=Color("81948e");backdrop.size=Vector2(640,420);viewport.add_child(backdrop)
	var plain := _plain("command-panel.png")
	var composite: StyleBox=helper.compose(plain,helper.framed_edge(load(FRAMED+"command-panel.png")))
	_panel(viewport,Vector2(40,60),Vector2(230,120),composite,"旧账与工钱\n船要修，人也要吃饭。")
	_panel(viewport,Vector2(360,60),Vector2(230,120),plain,"旧账与工钱\n船要修，人也要吃饭。")
	var outer: StyleBox=helper.compose(plain,helper.framed_edge(load(FRAMED+"command-panel.png")))
	var outer_plain := plain.duplicate() as StyleBoxTexture
	for style: StyleBox in [outer,outer_plain]:
		style.set_expand_margin(SIDE_LEFT,8);style.set_expand_margin(SIDE_RIGHT,8);style.set_expand_margin(SIDE_TOP,32);style.set_expand_margin(SIDE_BOTTOM,6)
	var expanded_panel := _panel(viewport,Vector2(40,280),Vector2(230,100),outer,"外扩标题 · 正文")
	var expanded_baseline := _panel(viewport,Vector2(360,280),Vector2(230,100),outer_plain,"外扩标题 · 正文")
	for parent: Panel in [expanded_panel,expanded_baseline]:
		var title := Label.new();parent.add_child(title);title.text="窗口标题";title.position=Vector2(24,-24)
		title.add_theme_color_override("font_color",Color("eadfca"));title.add_theme_font_size_override("font_size",20)
	var display := TextureRect.new();display.texture=viewport.get_texture();display.size=Vector2(640,420);root.add_child(display)
	await process_frame;await RenderingServer.frame_post_draw
	await process_frame;await RenderingServer.frame_post_draw
	var pixels := viewport.get_texture().get_image()
	var maximum_body_difference := 0.0
	for y in range(20,100,4):
		for x in range(20,210,4):
			var a:=pixels.get_pixel(40+x,60+y);var b:=pixels.get_pixel(360+x,60+y)
			maximum_body_difference=maxf(maximum_body_difference,maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b))))
	check(maximum_body_difference<0.03,"actual GPU body pixels match an independently drawn quiet-only Panel")
	var rim_difference_pixels := 0
	for y in range(-39,145):
		for x in range(-12,248):
			if x>=0 and x<230 and y>=0 and y<120: continue
			var px:=40+x;var py:=60+y
			var qx:=360+x;var qy:=60+y
			if px<0 or py<0 or qx>=640 or qy>=420: continue
			var a:=pixels.get_pixel(px,py);var b:=pixels.get_pixel(qx,qy)
			if maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))>0.04:rim_difference_pixels+=1
	check(rim_difference_pixels>=100,"actual GPU invokes custom _draw: painted edge/shadow exists outside body unlike native base-only Panel")
	var outer_difference := 0.0
	# The prior v2 region began four pixels inside the outer edge, including
	# its deliberately visible seven-pixel frame cells. Measure actual title
	# and content space instead; retain the exact same 0.03 difference limit.
	for y in range(-20,77,4):
		for x in range(24,207,4):
			var a:=pixels.get_pixel(40+x,280+y);var b:=pixels.get_pixel(360+x,280+y)
			outer_difference=maxf(outer_difference,maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b))))
	check(outer_difference<0.03,"Window-style outer expansion paints the title band with quiet body, with edge still outside")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	pixels.save_png(OUTPUT+"/probe.png")
	var receipt={"assertions":assertions,"failures":failures,"display":DisplayServer.get_name(),"adapter":RenderingServer.get_video_adapter_name(),"bodyMaximumDifference":maximum_body_difference,"outsideRimDifferentPixels":rim_difference_pixels,"outerHeaderMaximumDifference":outer_difference,"helperSha256":FileAccess.get_sha256(HELPER_PATH),"scope":"Independent real GPU Panel comparison, including outer title expansion; not full game acceptance."}
	var file:=FileAccess.open(OUTPUT+"/result.json",FileAccess.WRITE);file.store_string(JSON.stringify(receipt,"\t"));file.close()
	print("PAINTED_WINDOW_GPU ",JSON.stringify(receipt))
	viewport.queue_free();display.queue_free()
	await process_frame

func _finish() -> void:
	print("PAINTED_WINDOW_STYLE_TEST assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
