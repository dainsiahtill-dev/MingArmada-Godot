extends SceneTree
## Independent quiet-art acceptance: real PNG bytes, native theme resolution,
## worst sampled body pixels, resolved fonts, button geometry and focus rim.
## No product resources are changed by this test.
const Art = preload("res://game/ui/shared/maritime_art_theme.gd")
const Core = preload("res://game/ui/shared/parchment_theme.gd")
const QUIET := "res://assets/ui/ming_maritime/painted/quiet/"
const RUNTIME := QUIET+"runtime/"
const FRAMED := QUIET+"framed/"
var assertions := 0
var failures := 0
var _images: Dictionary = {}

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, detail: String) -> void:
	assertions+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",detail)

func _image(path: String) -> Image:
	if not _images.has(path):
		var pixels := Image.new()
		var error := pixels.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
		check(error==OK and not pixels.is_empty(),path+" decodes from actual PNG bytes")
		_images[path]=pixels
	return _images[path]

func _pixels(texture: Texture2D) -> Image:
	if texture==null: return null
	var pixels := texture.get_image()
	if pixels!=null and pixels.is_compressed(): pixels.decompress()
	return pixels

func _region(skin: StyleBoxTexture,pixels: Image) -> Rect2:
	return skin.region_rect if skin.region_rect.has_area() else Rect2(Vector2.ZERO,Vector2(pixels.get_size()))

func _axis_source(destination: float,target: float,start: float,extent: float,first: float,last: float) -> float:
	if destination<first: return start+destination
	if destination>=target-last: return start+extent-(target-destination)
	var center := maxf(target-first-last,0.001)
	return start+first+(destination-first)*(extent-first-last)/center

func _at(skin: StyleBoxTexture,pixels: Image,target: Vector2,point: Vector2) -> Color:
	var rect := _region(skin,pixels)
	var offset := Vector2(skin.get_expand_margin(SIDE_LEFT),skin.get_expand_margin(SIDE_TOP))
	var draw_size := target+offset+Vector2(skin.get_expand_margin(SIDE_RIGHT),skin.get_expand_margin(SIDE_BOTTOM))
	var draw_point := point+offset
	var x := _axis_source(draw_point.x,draw_size.x,rect.position.x,rect.size.x,skin.get_texture_margin(SIDE_LEFT),skin.get_texture_margin(SIDE_RIGHT))
	var y := _axis_source(draw_point.y,draw_size.y,rect.position.y,rect.size.y,skin.get_texture_margin(SIDE_TOP),skin.get_texture_margin(SIDE_BOTTOM))
	return pixels.get_pixel(clampi(int(x),0,pixels.get_width()-1),clampi(int(y),0,pixels.get_height()-1))

func _tinted(pixel: Color,tint: Color) -> Color:
	return Color(clampf(pixel.r*tint.r,0,1),clampf(pixel.g*tint.g,0,1),clampf(pixel.b*tint.b,0,1),clampf(pixel.a*tint.a,0,1))

func _over(front: Color,back: Color) -> Color:
	return Color(front.r*front.a+back.r*(1-front.a),front.g*front.a+back.g*(1-front.a),front.b*front.a+back.b*(1-front.a),1)

func _contrast(text: Color,background: Color) -> float:
	var first := _over(text,background).srgb_to_linear().get_luminance()
	var second := background.srgb_to_linear().get_luminance()
	return (maxf(first,second)+0.05)/(minf(first,second)+0.05)

func _painted(style: StyleBox,filename: String,detail: String,prefix: String=RUNTIME,expect_edge: bool=false) -> StyleBoxTexture:
	var layered := style!=null and style.has_method("get_body_style") and style.has_method("get_edge_style")
	check(not expect_edge or layered,detail+" exposes native body and independent painted edge layers")
	var skin := style.call("get_body_style") as StyleBoxTexture if layered else style as StyleBoxTexture
	check(skin!=null,detail+" resolves generated body texture rather than Flat")
	if skin==null: return null
	if layered:
		var edge := style.call("get_edge_style") as StyleBoxTexture
		check(edge!=null and edge.texture!=null and edge.texture.resource_path==FRAMED+"runtime/"+filename,detail+" edge references the real framed PNG")
		if edge!=null:
			check(not edge.draw_center and edge.get_expand_margin(SIDE_TOP)>0 and edge.get_expand_margin(SIDE_LEFT)>0,detail+" decorative alpha band stays in a separate outward edge layer")
	var pixels := _pixels(skin.texture)
	check(pixels!=null and not pixels.is_empty(),detail+" native texture is nonempty")
	if pixels==null or pixels.is_empty(): return null
	check(skin.texture.resource_path==prefix+filename,detail+" native texture points to current generated runtime")
	var png := _image(prefix+filename)
	var actual := pixels.get_pixel(pixels.get_width()/2,pixels.get_height()/2)
	var original := png.get_pixel(png.get_width()/2,png.get_height()/2)
	check(pixels.get_size()==png.get_size() and actual.is_equal_approx(original),detail+" imported resource matches generated quiet PNG pixels")
	return skin

func _readable(skin: StyleBoxTexture,text: Color,detail: String,target: Vector2=Vector2(450,640),required: float=4.5) -> void:
	if skin==null: return
	var pixels := _pixels(skin.texture)
	var ratio := INF
	var worst := Vector2.ZERO
	var worst_pixel := Color.TRANSPARENT
	# Native content margins define where text may draw; map that rectangle
	# through this StyleBoxTexture's actual nine-patch caps and region.
	for gy in range(48):
		for gx in range(48):
			var point := Vector2(lerpf(skin.get_margin(SIDE_LEFT),target.x-skin.get_margin(SIDE_RIGHT)-1,float(gx)/47),lerpf(skin.get_margin(SIDE_TOP),target.y-skin.get_margin(SIDE_BOTTOM)-1,float(gy)/47))
			var pixel := _tinted(_at(skin,pixels,target,point),skin.modulate_color)
			# Preserved alpha includes 253/255, and disabled modulate has alpha.
			# Black and white underlays bound unknown scenery behind the skin.
			var observed := minf(_contrast(text,_over(pixel,Color.BLACK)),_contrast(text,_over(pixel,Color.WHITE)))
			if observed<ratio:
				ratio=observed;worst=point;worst_pixel=pixel
	print("QUIET_CONTRAST ",detail," samples=2304 minimum=",snappedf(ratio,0.001)," required=",required," destination=",worst," composed_source=",worst_pixel," font=",text)
	check(ratio>=required,detail+" worst sampled text contrast >= "+str(required)+" (observed "+str(ratio)+")")

func _png_alpha() -> void:
	for filename: String in ["command-panel.png","folio-panel.png","button-normal.png","button-selected.png"]:
		var locations: Array[String]=[QUIET,RUNTIME]
		if filename in ["command-panel.png","folio-panel.png"]: locations.append_array([FRAMED,FRAMED+"runtime/"])
		for prefix: String in locations:
			var pixels := _image(prefix+filename)
			if pixels.is_empty(): continue
			check(pixels.detect_alpha()==Image.ALPHA_BLEND,prefix+filename+" contains real fractional alpha")
			var exterior := false
			for p: Vector2i in [Vector2i.ZERO,Vector2i(pixels.get_width()-1,0),Vector2i(0,pixels.get_height()-1),pixels.get_size()-Vector2i.ONE]:
				if pixels.get_pixelv(p).a<0.01: exterior=true
			check(exterior and pixels.get_pixel(pixels.get_width()/2,pixels.get_height()/2).a>0.90,prefix+filename+" has transparent outside and near-opaque interior without assuming alpha255")
	# Witness locations were identified outside the gold rule by full-image view.
	# These real RGBA samples record soft alpha tails; alpha alone cannot prove
	# that an arbitrary edge is a shadow, so no synthetic shadow assertion here.
	for filename: String in ["command-panel.png","folio-panel.png"]:
		var pixels := _image(FRAMED+filename)
		var tail: Array=[]
		for x in range(pixels.get_width()-45,pixels.get_width(),3):
			tail.append([x,pixels.get_pixel(x,pixels.get_height()/2)])
		print("FRAMED_SHADOW_RGBA_WITNESS ",filename," y=",pixels.get_height()/2," points=",tail)

func _plain_text(control: Control,detail: String) -> void:
	check(control.get_theme_color("font_shadow_color").a<=0.001 and control.get_theme_color("font_outline_color").a<=0.001,detail+" resolved text has no visible shadow/outline glow")

func _fonts(host: Control,popup: PopupMenu) -> void:
	var body := Label.new();host.add_child(body)
	var heading := Label.new();heading.theme_type_variation="HeadingLabel";host.add_child(heading)
	var body_name := body.get_theme_font("font").get_font_name()
	var heading_name := heading.get_theme_font("font").get_font_name()
	var window_name := popup.get_theme_font("title_font","Window").get_font_name()
	print("QUIET_FONTS body=",body_name," heading=",heading_name," window=",window_name)
	check("yahei" in body_name.to_lower() or "微软雅黑" in body_name,"native body font resolves Microsoft YaHei family")
	for item in [[heading_name,"HeadingLabel"],[window_name,"Window title"]]:
		var name := str(item[0]).to_lower()
		check("kaiti" in name or "楷体" in name,str(item[1])+" resolves actual KaiTi family")
	_plain_text(body,"body Label")
	_plain_text(heading,"HeadingLabel")
	check(popup.get_theme_color("title_outline_modulate","Window").a<=0.001,"native window title outline is transparent")
	# Shared Core must not reintroduce glow through inherited colors.
	var shared := Label.new();shared.theme=Core.create();host.add_child(shared)
	_plain_text(shared,"shared Core Label")

func _focus_visible(button: Button,normal: StyleBoxTexture,detail: String) -> void:
	button.grab_focus()
	check(button.has_focus(),detail+" acquires native keyboard focus")
	var style := button.get_theme_stylebox("focus")
	check(style is StyleBoxTexture,detail+" focus resolves generated texture")
	if not style is StyleBoxTexture or normal==null: return
	var focus := style as StyleBoxTexture
	var pixels := _pixels(focus.texture)
	var base_pixels := _pixels(normal.texture)
	check(pixels!=null and not pixels.is_empty(),detail+" focus image is nonempty")
	if pixels==null or pixels.is_empty(): return
	var target := Vector2(100,38)
	var visible := 0
	var delta := 0.0
	for y in range(38):
		for x in range(100):
			var in_center := x>=focus.get_texture_margin(SIDE_LEFT) and x<100-focus.get_texture_margin(SIDE_RIGHT) and y>=focus.get_texture_margin(SIDE_TOP) and y<38-focus.get_texture_margin(SIDE_BOTTOM)
			if not focus.draw_center and in_center: continue
			var point := Vector2(x,y)
			var color := _tinted(_at(focus,pixels,target,point),focus.modulate_color)
			if color.a<0.15: continue
			var base := _over(_tinted(_at(normal,base_pixels,target,point),normal.modulate_color),Color("17353b"))
			var focused := _over(color,base)
			var change := maxf(absf(focused.r-base.r),maxf(absf(focused.g-base.g),absf(focused.b-base.b)))
			if change>=0.10: visible+=1
			delta=maxf(delta,change)
	print("QUIET_FOCUS ",detail," rim_pixels_delta_at_least_0.1=",visible," max_channel_delta=",snappedf(delta,0.001))
	check(visible>=16,detail+" native focus rim has a discernible change over its actual unfocused pixels")
	check(not focus.draw_center,detail+" focus does not paint over live center text")

func _run() -> void:
	_png_alpha()
	var theme: Theme=Art.create()
	var host := Control.new();host.theme=theme;root.add_child(host)
	var panel := Panel.new();host.add_child(panel)
	var panel_skin := _painted(panel.get_theme_stylebox("panel"),"command-panel.png","Panel",RUNTIME,true)
	var body := Label.new();panel.add_child(body)
	var rich := RichTextLabel.new();panel.add_child(rich)
	_readable(panel_skin,body.get_theme_color("font_color"),"body Label")
	_readable(panel_skin,rich.get_theme_color("default_color"),"body RichTextLabel")
	var muted := Label.new();muted.theme_type_variation="MutedLabel";panel.add_child(muted)
	_readable(panel_skin,muted.get_theme_color("font_color"),"body MutedLabel")
	var folio_skin := _painted(Art.panel(20,"folio"),"folio-panel.png","specialized folio",RUNTIME,true)
	_readable(folio_skin,body.get_theme_color("font_color"),"folio body Label")
	_readable(folio_skin,rich.get_theme_color("default_color"),"folio body RichTextLabel")
	_readable(folio_skin,muted.get_theme_color("font_color"),"folio body MutedLabel")
	var popup := PopupMenu.new();popup.theme=theme;host.add_child(popup)
	var popup_skin := _painted(popup.get_theme_stylebox("panel"),"command-panel.png","PopupMenu",RUNTIME,true)
	_readable(popup_skin,popup.get_theme_color("font_color"),"PopupMenu")
	_fonts(host,popup)
	for kind: String in ["LineEdit","TextEdit"]:
		var field: Control=LineEdit.new() if kind=="LineEdit" else TextEdit.new()
		host.add_child(field)
		var skin := _painted(field.get_theme_stylebox("normal"),"command-panel.png",kind)
		_readable(skin,field.get_theme_color("font_color"),kind+" body",Vector2(300,100))
		_readable(skin,field.get_theme_color("font_placeholder_color"),kind+" placeholder",Vector2(300,100))
		_plain_text(field,kind)
	for primary: bool in [false,true]:
		var button := Button.new();button.text="确定";button.custom_minimum_size=Vector2(100,36)
		if primary: button.theme_type_variation="PrimaryButton"
		host.add_child(button)
		var label := "PrimaryButton" if primary else "Button"
		var normal: StyleBoxTexture
		for state: String in ["normal","hover","pressed","disabled"]:
			var filename := "button-selected.png" if primary or state=="pressed" else "button-normal.png"
			var skin := _painted(button.get_theme_stylebox(state),filename,label+" "+state)
			if state=="normal": normal=skin
			var key := "font_color" if state=="normal" else "font_"+state+"_color"
			_readable(skin,button.get_theme_color(key),label+" "+state,Vector2(100,38),3.0 if state=="disabled" else 4.5)
		await process_frame
		var written := button.get_combined_minimum_size()
		print("QUIET_BUTTON_MINIMUM ",label," text=",written)
		check(written.x<=100 and written.y<=38,label+" default16px text action fits native 100x38")
		button.text=""
		await process_frame
		var empty := button.get_combined_minimum_size()
		print("QUIET_BUTTON_MINIMUM ",label," empty=",empty)
		check(empty.x<=100 and empty.y<=36,label+" empty100x36 action is not enlarged by texture caps")
		button.text="确定"
		_plain_text(button,label)
		_focus_visible(button,normal,label)
	popup.free();host.free()
	print("MARITIME_ART_THEME_TEST assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
