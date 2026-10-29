extends SceneTree
## Native GPU proof for the existing command-panel alpha falloff. The test-only
## masked texture is an in-memory copy; product artwork is never modified.
const STYLE := preload("res://game/ui/shared/painted_window_style.gd")
const BODY := "res://assets/ui/ming_maritime/painted/quiet/runtime/command-panel.png"
const FRAME := "res://assets/ui/ming_maritime/painted/quiet/framed/runtime/command-panel.png"
const ROOT := "res://docs/design/2026-10-27-painted-ui/evidence/"
var output := ""
var failures := 0
var assertions := 0

func _initialize() -> void: _run.call_deferred()

func check(value: bool, what: String) -> bool:
	assertions += 1
	if not value:
		failures += 1
		printerr("SHADOW_PIXEL_FAIL ", what)
	return value

func panel(view: Node, at: Vector2, style: StyleBox, clipped: bool) -> void:
	var holder := Control.new()
	holder.position = at
	holder.size = Vector2(200,120)
	holder.clip_contents = clipped
	view.add_child(holder)
	var item := Panel.new()
	item.size = holder.size
	item.add_theme_stylebox_override("panel", style)
	holder.add_child(item)

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	if not check(output.begins_with(ROOT) and output.trim_prefix(ROOT).is_valid_filename(), "explicit fresh evidence directory required"):
		quit(1); return
	if not check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output)), "never overwrite evidence"):
		quit(1); return
	if not check(DisplayServer.get_name() != "headless", "GPU display required"):
		quit(1); return
	var tex := load(FRAME) as Texture2D
	var body := StyleBoxTexture.new()
	body.texture = load(BODY)
	body.region_rect = Rect2(Vector2.ZERO, body.texture.get_size())
	body.set_texture_margin_all(8)
	body.set_content_margin_all(24)
	var edge := STYLE.framed_edge(tex)
	var composite := STYLE.compose(body,edge)
	var source := tex.get_image()
	if source.is_compressed(): source.decompress()
	if not check(source.get_size() == Vector2i(768,384), "frozen frame dimensions"):
		quit(1); return
	# Source rows 348..353 are below the last high-opacity painted edge,
	# corresponding to output offsets y=3..8 given the measured nine-slice.
	# Retain just those source pixels. The interior probe samples y=4..7,
	# avoiding filtering at the mask's outer boundaries.
	var isolated := source.duplicate() as Image
	for y in range(source.get_height()):
		if y >= 348 and y <= 353: continue
		for x in range(source.get_width()): isolated.set_pixel(x,y,Color.TRANSPARENT)
	var maximum_value := 0.0
	var maximum_alpha := 0.0
	for y in range(348,354):
		for x in range(290,478):
			var p := source.get_pixel(x,y)
			maximum_value = maxf(maximum_value,maxf(p.r,maxf(p.g,p.b)))
			maximum_alpha = maxf(maximum_alpha,p.a)
	check(maximum_value < 0.25 and maximum_alpha < 0.41, "sampled original source band is low-opacity dark rather than gold")
	check(edge.get_texture_margin(SIDE_BOTTOM) == 46 and edge.get_expand_margin(SIDE_BOTTOM) == 39, "source-to-screen bottom stripe mapping preserved")
	var masked_edge := edge.duplicate() as StyleBoxTexture
	masked_edge.texture = ImageTexture.create_from_image(isolated)
	var masked := STYLE.compose(body,masked_edge)
	root.size = Vector2i(1280,720)
	var view := SubViewport.new()
	view.size = Vector2i(1280,720)
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	for row in range(2):
		var background := ColorRect.new()
		background.color = Color(0.78,0.75,0.65) if row == 0 else Color(0.10,0.13,0.14)
		background.position = Vector2(0,row*360)
		background.size = Vector2(1280,360)
		view.add_child(background)
		for col in range(4):
			panel(view,Vector2(30+col*300,70+row*360),[composite,body,masked,composite][col],col==3)
	var display := TextureRect.new()
	display.texture = view.get_texture()
	display.size = Vector2(1280,720)
	root.add_child(display)
	await process_frame; await RenderingServer.frame_post_draw
	await process_frame; await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image()
	var metrics := []
	for row in range(2):
		var change := 0.0
		var masked_error := 0.0
		var clipped_error := 0.0
		var darkened := 0
		var count := 0
		for y in range(4,8):
			for x in range(80,120):
				var base := image.get_pixel(330+x,70+row*360+120+y)
				var full := image.get_pixel(30+x,70+row*360+120+y)
				var only := image.get_pixel(630+x,70+row*360+120+y)
				var clipped := image.get_pixel(930+x,70+row*360+120+y)
				var delta := (base.r-full.r + base.g-full.g + base.b-full.b)/3.0
				change += delta
				if delta > 1.0/255.0: darkened += 1
				masked_error = maxf(masked_error,maxf(absf(full.r-only.r),maxf(absf(full.g-only.g),absf(full.b-only.b))))
				clipped_error = maxf(clipped_error,maxf(absf(base.r-clipped.r),maxf(absf(base.g-clipped.g),absf(base.b-clipped.b))))
				count += 1
		var mean := change / count
		metrics.append({"background":"light" if row==0 else "dark", "meanDarkening":mean,"darkenedPixels":darkened,"pixelCount":count,"shadowOnlyMaximumDifference":masked_error,"clippedMaximumDifference":clipped_error})
		check(mean > 1.0/255.0 and darkened > 20, "unclipped generated shadow visibly darkens " + str(row))
		check(masked_error <= 2.0/255.0, "gold-excluded masked source reproduces actual shadow " + str(row))
		check(clipped_error <= 1.0/255.0, "parent clip removes exterior shadow " + str(row))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var png := output.path_join("shadow-pixels.png")
	check(image.save_png(png)==OK,"GPU capture saved")
	var receipt := {"assertions": assertions,"failures":failures,"metrics":metrics,"sourceBandRGBMax":maximum_value,"sourceBandAlphaMax":maximum_alpha,"sourceFrameSha256":FileAccess.get_sha256(FRAME),"helperSha256":FileAccess.get_sha256("res://game/ui/shared/painted_window_style.gd"),"testSha256":FileAccess.get_sha256("res://tests/test_painted_shadow_pixels.gd"),"pngSha256":FileAccess.get_sha256(png),"adapter":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"display":DisplayServer.get_name(),"viewport":[1280,720],"panelSize":[200,120],"panelPositions":[[30,70],[330,70],[630,70],[930,70],[30,430],[330,430],[630,430],[930,430]],"panelColumns":["actual full frame","body only","test-only source shadow band","actual frame clipped by 200x120 parent"],"sourceFrameSize":[768,384],"sourceBandRowsInclusive":[348,353],"sourceBandSampleColumnsHalfOpen":[290,478],"measuredPanelRelativeRoiHalfOpen":[80,124,120,128],"meanDarkeningThreshold":1.0/255.0,"countThreshold":20,"description":"Thresholds are operational probes, not a validated human perception standard. Full original frame is compared with body-only; the source-band mask is a separate isolation check. The clipped parent bounds equal the body rectangle.","scope":"Command panel lower central shadow only; 200x120 isolated synthetic controls, bright/dark flat backgrounds, clipped/unclipped. Not individual game window verification or manual gameplay."}
	var file := FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(receipt,"\t")); file.close()
	else: failures += 1
	print("PAINTED_SHADOW_PIXELS ",JSON.stringify(receipt))
	quit(1 if failures else 0)
