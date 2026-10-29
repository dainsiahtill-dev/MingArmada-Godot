extends "res://tools/capture-painted-ui.gd"
## Supplemental ship-book windows receipt. Existing four capture groups stay frozen.

func sources() -> Dictionary:
	var result: Dictionary=super.sources()
	var path:="res://tools/capture-shipbook-windows.gd"
	result[path]=FileAccess.get_sha256(path)
	return result

func catalog_group() -> void:
	var book: Node=await enter("ships")
	if not book: return
	for dimensions: Vector2i in DIMENSIONS:
		await resize_view(dimensions)
		await capture("shipbook-normal-"+str(dimensions.x))
		for id: String in ["ShipKind","CameraAngle"]:
			var choice:=book.find_child(id,true,false) as OptionButton
			if not check(choice!=null,"ship-book native selector exists: "+id): continue
			if not await click(choice): continue
			var popup:=choice.get_popup()
			check(popup.visible,"actual ship-book click opens popup: "+id)
			var style:=popup.get_theme_stylebox("panel")
			check(style!=null and style.has_method("get_edge_style"),"ship-book popup resolves the generated layered frame: "+id)
			await capture("shipbook-"+id.to_snake_case().replace("_","-")+"-popup-"+str(dimensions.x),{"popup":"actual OptionButton PopupMenu","selector":id})
			await key(KEY_ESCAPE)
			check(not popup.visible,"native Escape closes the ship-book popup: "+id)
			check(main.current_scene==book,"closing popup retains the ship-book scene: "+id)
	await leave()
