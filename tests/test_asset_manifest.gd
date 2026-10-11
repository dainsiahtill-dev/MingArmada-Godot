extends SceneTree

var failures: Array[String] = []
var assertions := 0

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var path := "res://assets/migration-manifest.json"
	check(FileAccess.file_exists(path), "migration manifest must exist with all original assets")
	if FileAccess.file_exists(path):
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		check(manifest.sourceHead == "9ad6a44daecd4ec36a8172d83ff27493feffe5dd", "asset source must identify committed baseline")
		var glbs := 0
		var extensions: Dictionary = {}
		for entry: Dictionary in manifest.files:
			var target: String = "res://" + entry.to
			var source: String = manifest.sourceRoot + "/" + entry.from
			check(FileAccess.file_exists(target), "copied asset missing: " + target)
			check(FileAccess.get_sha256(target) == entry.sha256, "target bytes changed: " + target)
			check(FileAccess.get_sha256(source) == entry.sha256, "source bytes differ: " + source)
			if entry.category == "public":
				var extension := target.get_extension()
				extensions[extension] = extensions.get(extension, 0) + 1
				if extension == "glb":
					glbs += 1
		check(glbs == 21, "all eighteen ship and three sailor GLBs must be copied")
		check(extensions.get("png", 0) == 18, "all original PNG art/textures must be copied")
		check(extensions.get("mp3", 0) == 2, "both original music files must be copied")
		check(extensions.get("jpg", 0) == 1, "original normal texture must be copied")
		for group in ["ships", "sailors"]:
			var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/%s/%s-manifest.json" % [group, group]))
			for asset: Dictionary in original.assets:
				check(FileAccess.get_sha256("res://assets/models/%s/%s" % [group, asset.file]) == asset.sha256, "GLB bytes must also match original author manifest")
		var library_script = load("res://modules/scene_engine/assets/asset_library.gd")
		check(library_script != null, "native asset library must load")
		if library_script:
			var library = library_script.new()
			var first = library.instantiate_model("res://assets/models/sailors/sailor-lod0.glb")
			var second = library.instantiate_model("res://assets/models/sailors/sailor-lod0.glb")
			check(first != null and second != null, "original sailor GLB must instantiate")
			if first and second:
				var bones_a: Array = first.find_children("*", "Skeleton3D", true, false)
				var bones_b: Array = second.find_children("*", "Skeleton3D", true, false)
				check(bones_a.size() == 1 and bones_b.size() == 1, "each sailor owns one native skeleton")
				if bones_a.size() == 1 and bones_b.size() == 1:
					check(bones_a[0] != bones_b[0], "cached scenes must never share an active skeleton")
					check(bones_a[0].get_bone_count() == 18, "original sailor has eighteen bones")
				var animations: Array = first.find_children("*", "AnimationPlayer", true, false)
				check(animations.size() == 1, "original sailor animations must be retained")
				if animations.size() == 1:
					for clip in ["idle", "helm", "haul", "load-cannon", "walk", "lookout"]:
						check(animations[0].has_animation(clip), "original animation missing: " + clip)
				first.free()
				second.free()
			check(library.get_cached_count() == 1, "PackedScene must be cached once for repeated instantiation")
			for kind in ["fuchuan", "fisherman", "merchant", "voc", "patrol", "heavy"]:
				for lod in 3:
					var model = library.instantiate_model("res://assets/models/ships/%s-lod%d.glb" % [kind, lod])
					check(model != null, "original ship GLB must instantiate: %s-%d" % [kind, lod])
					if model:
						var sails := 0
						for mesh_node in model.find_children("*", "MeshInstance3D", true, false):
							if String(mesh_node.name).begins_with("sail_"):
								sails += 1
								check(mesh_node.mesh.get_blend_shape_count() == 2, "sail furl/inflate morphs retained")
							for surface in mesh_node.mesh.get_surface_count():
								var material = mesh_node.mesh.surface_get_material(surface)
								if material is StandardMaterial3D and mesh_node.mesh.surface_get_format(surface) & Mesh.ARRAY_FORMAT_COLOR:
									check(material.vertex_color_use_as_albedo, "baked COLOR_0 must drive material albedo")
						check(sails > 0, "ship keeps actual authored sails")
						model.free()
			library.dispose()
			check(library.get_cached_count() == 0, "dispose releases cached scenes")
			check(library.instantiate_model("res://assets/models/sailors/sailor-lod0.glb") == null, "disposed library rejects late model attachment")
	for message in failures:
		printerr("FAIL: ", message)
	print("ASSET_MANIFEST_TESTS assertions=", assertions, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
