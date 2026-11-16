extends SceneTree
# Headless probe: prints world-space AABBs of key nodes inside the fixed scene.
# Run: godot --headless --path . --script res://probe_nodes.gd

const SCENE := "res://Models/workstation.tscn"

const WANT := [
	"HP_PC", "PC_HP", "PC_HP_001",
	"KeyBoard_002_001", "Black Lamp_002", "Mug 4_001", "Pen Holder_001",
	"Top_Drawer_003", "Bottom_Drawer_003",
	"Desk_004", "Chair 1_001", "Filing Cainet Base_015",
	"File Box 1_001", "File Box 1_005", "File Box 2 Lid_001", "File Box 2 Lid_004",
	"Pot_002", "Binder_001", "Binder 2_004", "Binder 3_001",
]

func _init() -> void:
	var scene: Node = load(SCENE).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	for want in WANT:
		var mi := _find_mesh(scene, want)
		if mi == null:
			print("missing ", want)
			continue
		var aabb: AABB = mi.global_transform * mi.get_aabb()
		print("%s|%s|%s|%s" % [want, aabb.position, aabb.size, aabb.get_center()])
	# aggregate papers AABB
	var papers_aabb := AABB()
	var found := 0
	for c in _all_children(scene):
		if c is MeshInstance3D and String(c.name).begins_with("paper_"):
			papers_aabb = papers_aabb.merge(c.global_transform * c.get_aabb())
			found += 1
	print("papers[%d]|%s|%s|%s" % [found, papers_aabb.position, papers_aabb.size, papers_aabb.get_center()])
	quit()

func _find_mesh(n: Node, want: String) -> MeshInstance3D:
	if n is MeshInstance3D and String(n.name) == want:
		return n
	for c in n.get_children():
		var r = _find_mesh(c, want)
		if r != null:
			return r
	return null

func _all_children(n: Node) -> Array:
	var out := []
	for c in n.get_children():
		out.append(c)
		out.append_array(_all_children(c))
	return out
