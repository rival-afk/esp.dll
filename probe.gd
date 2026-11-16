extends SceneTree

func _init() -> void:
	var scene: Node = load("res://game.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var ws := scene.find_child("Workstation", true)
	for want in ["PC_HP", "PC_HP_001"]:
		var mi := _find_mesh(ws, want)
		if mi == null:
			print("missing ", want)
			continue
		var aabb: AABB = mi.global_transform * mi.get_aabb()
		print("%s center=%s size=%s" % [want, aabb.get_center(), aabb.size])
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1, 0, 0) if want == "PC_HP" else Color(0, 1, 0)
		mi.set_surface_override_material(0, mat)
	quit()

func _find_mesh(n: Node, want: String) -> MeshInstance3D:
	if n is MeshInstance3D and String(n.name) == want:
		return n
	for c in n.get_children():
		var r = _find_mesh(c, want)
		if r != null:
			return r
	return null
