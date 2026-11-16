extends Node3D
## Зона сборки на столе (bench): размещение деталей из каталога, пины,
## соединение проводами, синхронизация с CircuitSim.
## Редактор: ортографический вид сверху, сетка 2 см; детали перемещаются
## зажатием ЛКМ (строго по сетке), поворот на 90° по R; провод тянется
## зажатием от пина к пину (отпустил над пином — соединено).
## Модели: процедурные в реальном масштабе (резистор 7 мм, LED 5 мм,
## DIP-корпуса по ГОСТ); .glb из Models/parts/<catalog_id>.glb подхватывается
## автоматически и масштабируется до реальных габаритов.
## Headless-тест: verify_bench.gd (добавляет /root/CircuitSim вручную).

const PartsDB = preload("res://Scripts/data/parts_db.gd")

signal parts_changed

# сетка сборки
const GRID_ORIGIN := Vector3(-0.36, 0.7345, 0.545)
const GRID_SIZE := Vector2(0.64, 0.14)
const GRID_STEP := 0.02
const GRID_Y := 0.7355
const MAT_Y := 0.734   # тонкий тёмный коврик под зоной сборки
# стартовые слоты (выровнены по сетке)
const SLOT_ORIGIN := Vector3(-0.30, 0.733, 0.565)
const SLOT_DX := 0.12
const SLOT_DZ := 0.06
const SLOTS_PER_ROW := 5
const ROWS := 2
const MAX_PARTS := SLOTS_PER_ROW * ROWS
const LEAD_Y := 0.004        # высота выводов и пинов (4 мм над столом)
const PICK_R := 0.013        # радиус попадания луча в пин
const WIRE_T := 0.0015       # толщина провода (1.5 мм)
const PARTS_GLB_DIR := "res://Models/parts/"

# реальные габариты для скачанных моделей (м)
const TARGET_SIZE := {
	"psu5v": Vector3(0.10, 0.07, 0.07), "lcd1602": Vector3(0.08, 0.016, 0.036),
	"bread830": Vector3(0.165, 0.02, 0.055), "ic_atmega": Vector3(0.09, 0.016, 0.02),
	"ic_esp32": Vector3(0.055, 0.012, 0.028), "s_hcsr04": Vector3(0.045, 0.016, 0.025),
}

var parts := []   # {pid, catalog_id, name, root, glow_mat, sim, comp_id, pins, aabb, yaw}
var wires := []   # {wid, a, b, comp_id, node}
var _next_pid := 1
var _next_wid := 1
var _hover := ""
var _wire_from := ""  # пин, из которого тянем провод
var _drag := ""       # pid перетаскиваемой детали
var _active := false
var _ui_block := false
var _panel: PanelContainer
var _title_label: Label
var _list_box: VBoxContainer
var _grid_mi: MeshInstance3D
var _mat_mi: MeshInstance3D
var _light: OmniLight3D
var _temp_wire: MeshInstance3D

func _ready() -> void:
	_build_grid()
	_build_panel()
	_light = OmniLight3D.new()
	_light.position = Vector3(-0.04, 1.0, 0.605)
	_light.light_color = Color(1, 0.95, 0.85, 1)
	_light.light_energy = 0.35
	_light.omni_range = 1.6
	_light.omni_attenuation = 1.0
	_light.visible = false
	add_child(_light)
	_temp_wire = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(WIRE_T, WIRE_T, 0.01)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.9, 0.65, 0.25, 1)
	box.material = m
	_temp_wire.mesh = box
	_temp_wire.visible = false
	add_child(_temp_wire)

func _sim() -> Node:
	return get_node_or_null("/root/CircuitSim")

# ---------------------------------------------------------------- сетка

func _build_grid() -> void:
	# коврик: чистая тёмная поверхность вместо шумной текстуры стола
	var mat := MeshInstance3D.new()
	var mbox := BoxMesh.new()
	mbox.size = Vector3(GRID_SIZE.x + 0.04, 0.002, GRID_SIZE.y + 0.03)
	var mmat := StandardMaterial3D.new()
	mmat.albedo_color = Color(0.14, 0.13, 0.12, 1)
	mmat.roughness = 0.95
	mbox.material = mmat
	mat.mesh = mbox
	mat.position = Vector3(GRID_ORIGIN.x + GRID_SIZE.x * 0.5, MAT_Y, GRID_ORIGIN.z + GRID_SIZE.y * 0.5)
	add_child(mat)
	_mat_mi = mat
	_grid_mi = MeshInstance3D.new()
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var x0 := GRID_ORIGIN.x
	var x1 := GRID_ORIGIN.x + GRID_SIZE.x
	var z0 := GRID_ORIGIN.z
	var z1 := GRID_ORIGIN.z + GRID_SIZE.y
	var steps_x := int(GRID_SIZE.x / GRID_STEP)
	var steps_z := int(GRID_SIZE.y / GRID_STEP)
	for i in steps_x + 1:
		var x := x0 + i * GRID_STEP
		im.surface_add_vertex(Vector3(x, GRID_Y, z0))
		im.surface_add_vertex(Vector3(x, GRID_Y, z1))
	for j in steps_z + 1:
		var z := z0 + j * GRID_STEP
		im.surface_add_vertex(Vector3(x0, GRID_Y, z))
		im.surface_add_vertex(Vector3(x1, GRID_Y, z))
	im.surface_end()
	_grid_mi.mesh = im
	var gmat := StandardMaterial3D.new()
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.albedo_color = Color(0.85, 0.72, 0.5, 0.45)
	_grid_mi.material_override = gmat
	_grid_mi.visible = false
	add_child(_grid_mi)

func _snap_to_grid(p: Vector3) -> Vector3:
	var gx := snappedf((p.x - GRID_ORIGIN.x) / GRID_STEP, 1.0) * GRID_STEP + GRID_ORIGIN.x
	var gz := snappedf((p.z - GRID_ORIGIN.z) / GRID_STEP, 1.0) * GRID_STEP + GRID_ORIGIN.z
	return Vector3(gx, 0.733, gz)

# ---------------------------------------------------------------- панель «На столе»

func _build_panel() -> void:
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.06, 0.05, 0.92)
	sb.set_border_width_all(1)
	sb.border_color = Color(1, 0.82, 0.58, 0.14)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 14)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.visible = false
	add_child(_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	_panel.add_child(vb)
	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 16)
	_title_label.add_theme_color_override("font_color", Color(1, 0.82, 0.58, 1))
	vb.add_child(_title_label)
	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 4)
	vb.add_child(_list_box)

func _rebuild_panel() -> void:
	if _title_label == null:
		return
	_title_label.text = "На столе: %d / %d" % [parts.size(), MAX_PARTS]
	for c in _list_box.get_children():
		c.queue_free()
	for p in parts:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lbl := Label.new()
		lbl.text = p["name"]
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var btn := Button.new()
		btn.text = "×"
		btn.custom_minimum_size = Vector2(28, 28)
		btn.add_theme_font_size_override("font_size", 16)
		btn.add_theme_color_override("font_color", Color(0.75, 0.7, 0.62, 1))
		btn.add_theme_color_override("font_hover_color", Color(1, 0.92, 0.55, 1))
		for state in ["normal", "hover", "pressed"]:
			var bs := StyleBoxFlat.new()
			bs.bg_color = Color(0.2, 0.17, 0.13, 1) if state != "normal" else Color(0.13, 0.11, 0.09, 1)
			bs.set_border_width_all(1)
			bs.border_color = Color(1, 0.82, 0.58, 0.3 if state != "normal" else 0.14)
			bs.set_corner_radius_all(3)
			btn.add_theme_stylebox_override(state, bs)
		btn.tooltip_text = "Убрать деталь со стола"
		btn.pressed.connect(remove_part.bind(p["pid"]))
		row.add_child(btn)
		_list_box.add_child(row)
	_apply_ui_visibility()

# ---------------------------------------------------------------- активность

func set_active(on: bool) -> void:
	_active = on
	if not on:
		_drag = ""
		_wire_from = ""
		_temp_wire.visible = false
		_refresh_pin_styles()
	_apply_ui_visibility()

func set_blocking_ui(on: bool) -> void:
	_ui_block = on
	_apply_ui_visibility()

func _apply_ui_visibility() -> void:
	if _panel != null:
		_panel.visible = _active and parts.size() > 0 and not _ui_block
	if _grid_mi != null:
		_grid_mi.visible = _active and not _ui_block
	if _mat_mi != null:
		_mat_mi.visible = _active and not _ui_block
	if _light != null:
		_light.visible = _active

# ---------------------------------------------------------------- размещение

func place_part(catalog_id: String) -> String:
	if parts.size() >= MAX_PARTS:
		return ""
	var entry: Dictionary = PartsDB.get_part(catalog_id)
	if entry.is_empty():
		return ""
	var sim_def: Dictionary = PartsDB.sim_of(catalog_id)
	var pid := "p%d" % _next_pid
	_next_pid += 1
	var slot := _free_slot()
	if slot == Vector3.INF:
		return ""
	var root := Node3D.new()
	root.name = "Part_" + pid
	root.position = slot
	add_child(root)

	var vis := _build_visual(catalog_id)
	root.add_child(vis["node"])
	var glow_mat: StandardMaterial3D = vis["glow_mat"]
	var span: float = vis["pin_span"]
	var aabb: AABB = AABB(Vector3(-vis["size"].x * 0.5, 0, -vis["size"].z * 0.5), vis["size"])

	var pins := {}
	for side in ["L", "R"]:
		var pin := MeshInstance3D.new()
		pin.name = "Pin_" + side
		var s := SphereMesh.new()
		s.radius = 0.0035
		s.height = 0.007
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(1.0, 0.82, 0.58, 1)
		pm.emission_enabled = true
		pm.emission = Color(1.0, 0.82, 0.58, 1)
		pm.emission_energy_multiplier = 0.25
		s.material = pm
		pin.mesh = s
		pin.position = Vector3(-span if side == "L" else span, LEAD_Y, 0)
		root.add_child(pin)
		pins[side] = {"mi": pin, "mat": pm}

	var rec := {
		"pid": pid, "catalog_id": catalog_id, "name": entry["name"], "sim": sim_def,
		"root": root, "glow_mat": glow_mat, "pins": pins, "comp_id": "",
		"aabb": aabb, "yaw": 0.0,
	}
	parts.append(rec)
	if not sim_def.is_empty() and _sim() != null:
		rec["comp_id"] = _sim().add_comp(sim_def["type"],
			_sim_node(pid, "L"), _sim_node(pid, "R"), sim_def.get("value", 0.0))
		_sim().solve()
	_update_leds()
	_rebuild_panel()
	parts_changed.emit()
	return pid

func get_part(pid: String) -> Dictionary:
	return _part_by_pid(pid)

func _free_slot() -> Vector3:
	for row in ROWS:
		for col in SLOTS_PER_ROW:
			var cand := SLOT_ORIGIN + Vector3(SLOT_DX * col, 0, SLOT_DZ * row)
			var busy := false
			for p in parts:
				var d: Vector3 = p["root"].position - cand
				if absf(d.x) < 0.05 and absf(d.z) < 0.04:
					busy = true
					break
			if not busy:
				return cand
	return Vector3.INF

# ---------------------------------------------------------------- модели деталей

func _build_visual(catalog_id: String) -> Dictionary:
	var target: Vector3 = TARGET_SIZE.get(catalog_id, Vector3(0.08, 0.04, 0.05))
	var glb := _load_glb(catalog_id, target)
	if glb != null:
		var wrap := Node3D.new()
		wrap.add_child(glb)
		var sz := target
		var a := _scene_aabb(glb)
		if a.size.x > 0:
			sz = a.size
		return {"node": wrap, "glow_mat": null, "size": sz,
			"pin_span": sz.x * 0.5 + 0.004}
	return _procedural_visual(catalog_id)

func _load_glb(catalog_id: String, target: Vector3) -> Node3D:
	var path := PARTS_GLB_DIR + catalog_id + ".glb"
	if not ResourceLoader.exists(path):
		return null
	var ps: PackedScene = load(path)
	if ps == null:
		return null
	var inst: Node3D = ps.instantiate()
	var a := _scene_aabb(inst)
	if a.size.x <= 0.0:
		return null
	var s: float = minf(target.x / a.size.x, minf(target.y / a.size.y, target.z / a.size.z))
	inst.scale = Vector3.ONE * s
	inst.position = Vector3(
		-(a.position.x + a.size.x * 0.5) * s,
		-a.position.y * s,
		-(a.position.z + a.size.z * 0.5) * s)
	return inst

func _scene_aabb(n: Node3D) -> AABB:
	var out := AABB()
	var found := false
	for c in n.get_children():
		if c is MeshInstance3D:
			var ab: AABB = c.transform * c.get_aabb()
			out = ab if not found else out.merge(ab)
			found = true
		else:
			var sub := _scene_aabb(c)
			if sub.size.x > 0:
				out = sub if not found else out.merge(sub)
				found = true
	return out

# --- примитивы-хелперы ---

func _mk_box(parent: Node3D, size: Vector3, pos: Vector3, col: Color, rough := 0.5) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	b.material = m
	mi.mesh = b
	mi.position = pos
	parent.add_child(mi)
	return mi

func _mk_cyl(parent: Node3D, r: float, h: float, pos: Vector3, col: Color, axis := "y", rough := 0.5, metal := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	c.material = m
	mi.mesh = c
	mi.position = pos
	if axis == "x":
		mi.rotation.z = PI / 2.0
	elif axis == "z":
		mi.rotation.x = PI / 2.0
	parent.add_child(mi)
	return mi

func _mk_sph(parent: Node3D, r: float, pos: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	s.material = m
	mi.mesh = s
	mi.position = pos
	parent.add_child(mi)
	return mi

func _mk_lead(parent: Node3D, from: Vector3, to: Vector3) -> MeshInstance3D:
	var dir := to - from
	var len := dir.length()
	if len < 0.0005:
		len = 0.0005
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.0007
	c.bottom_radius = 0.0007
	c.height = len
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.72, 0.72, 0.75, 1)
	m.metallic = 0.7
	m.roughness = 0.35
	c.material = m
	mi.mesh = c
	mi.position = (from + to) * 0.5
	var dn := dir / len
	var x_ax := Vector3.UP.cross(dn)
	if x_ax.length() < 1e-4:
		x_ax = Vector3(1, 0, 0)
	x_ax = x_ax.normalized()
	var z_ax := x_ax.cross(dn).normalized()
	mi.transform = Transform3D(Basis(x_ax, dn, z_ax), mi.position)
	parent.add_child(mi)
	return mi

func _mk_legs(parent: Node3D, n: int, pitch: float, y_top: float) -> void:
	for i in n:
		var x := -pitch * (n - 1) * 0.5 + pitch * i
		_mk_box(parent, Vector3(0.0015, 0.006, 0.002),
			Vector3(x, y_top - 0.003, -0.005), Color(0.72, 0.72, 0.75, 1), 0.35)
		_mk_box(parent, Vector3(0.0015, 0.006, 0.002),
			Vector3(x, y_top - 0.003, 0.005), Color(0.72, 0.72, 0.75, 1), 0.35)

const BAND_COLS := {
	"black": Color(0.1, 0.1, 0.1), "brown": Color(0.45, 0.3, 0.2),
	"red": Color(0.8, 0.15, 0.1), "orange": Color(0.9, 0.45, 0.1),
	"yellow": Color(0.9, 0.8, 0.2), "green": Color(0.2, 0.6, 0.2),
}

func _mk_resistor(parent: Node3D, bands: Array) -> void:
	# резистор 0.25 Вт: тело ~7 мм, выводы к пинам на ±13 мм
	_mk_cyl(parent, 0.0013, 0.007, Vector3(0, LEAD_Y, 0), Color(0.82, 0.71, 0.56, 1), "x", 0.65)
	var offs := [-0.0025, -0.0008, 0.0008, 0.0022]
	for i in bands.size():
		var col: Color = BAND_COLS.get(bands[i], Color(0.1, 0.1, 0.1))
		_mk_cyl(parent, 0.0015, 0.0012, Vector3(offs[i], LEAD_Y, 0), col, "x")
	for sx in [-1.0, 1.0]:
		_mk_lead(parent, Vector3(sx * 0.0035, LEAD_Y, 0), Vector3(sx * 0.013, LEAD_Y, 0))

func _mk_led(parent: Node3D, col: Color, glow: Dictionary) -> void:
	# LED 5 мм: корпус 5 мм, ножки к пинам на ±8 мм
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(col.r, col.g, col.b, 0.85)
	lm.roughness = 0.3
	lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow["glow_mat"] = lm
	var body := _mk_cyl(parent, 0.0025, 0.007, Vector3(0, 0.0065, 0), col, "y", 0.3)
	body.mesh.material = lm
	var dome := _mk_sph(parent, 0.0025, Vector3(0, 0.0115, 0), col)
	dome.mesh.material = lm
	for sx in [-1.0, 1.0]:
		_mk_lead(parent, Vector3(sx * 0.008, LEAD_Y, 0), Vector3(sx * 0.0025, LEAD_Y, 0))
		_mk_lead(parent, Vector3(sx * 0.0025, LEAD_Y, 0), Vector3(sx * 0.0025, 0.004, 0))

func _mk_dip(parent: Node3D, w: float, legs: int) -> void:
	_mk_box(parent, Vector3(w, 0.006, 0.009), Vector3(0, 0.006, 0), Color(0.2, 0.2, 0.22, 1), 0.45)
	_mk_legs(parent, legs, w / (legs - 1) * 0.82, 0.006)

func _mk_to220(parent: Node3D, tab: float) -> void:
	_mk_box(parent, Vector3(0.010, 0.014, 0.005), Vector3(0, 0.009, 0), Color(0.14, 0.14, 0.15, 1), 0.5)
	_mk_box(parent, Vector3(0.010, tab, 0.0018), Vector3(0, 0.020 + tab * 0.5, -0.002), Color(0.7, 0.71, 0.74, 1), 0.35)
	for sx in [-1.0, 0.0, 1.0]:
		_mk_lead(parent, Vector3(sx * 0.0035, 0.007, 0), Vector3(sx * 0.0035, LEAD_Y, 0))
		_mk_lead(parent, Vector3(sx * 0.0035, LEAD_Y, 0), Vector3(sx * 0.007, LEAD_Y, 0))

func _procedural_visual(catalog_id: String) -> Dictionary:
	var node := Node3D.new()
	var out := {"node": node, "glow_mat": null, "size": Vector3(0.02, 0.012, 0.012),
		"pin_span": 0.014}
	match catalog_id:
		"psu5v":
			out["size"] = Vector3(0.10, 0.07, 0.07)
			out["pin_span"] = 0.055
			_mk_box(node, Vector3(0.09, 0.07, 0.07), Vector3(0, 0.035, 0), Color(0.2, 0.21, 0.23, 1), 0.5)
			_mk_cyl(node, 0.006, 0.012, Vector3(-0.025, 0.076, 0), Color(0.85, 0.2, 0.18, 1))
			_mk_cyl(node, 0.006, 0.012, Vector3(0.025, 0.076, 0), Color(0.12, 0.12, 0.14, 1))
			for sx in [-1.0, 1.0]:
				_mk_lead(node, Vector3(sx * 0.05, LEAD_Y, 0), Vector3(sx * 0.055, LEAD_Y, 0))
		"r220", "r1k", "r10k", "r100k", "r1m":
			out["size"] = Vector3(0.026, 0.008, 0.008)
			out["pin_span"] = 0.013
			var bands := []
			match catalog_id:
				"r220": bands = ["red", "red", "brown", "yellow"]
				"r1k": bands = ["brown", "black", "red", "yellow"]
				"r10k": bands = ["brown", "black", "orange", "yellow"]
				"r100k": bands = ["brown", "black", "yellow", "yellow"]
				"r1m": bands = ["brown", "black", "green", "yellow"]
			_mk_resistor(node, bands)
		"c100n":
			out["size"] = Vector3(0.020, 0.012, 0.008)
			out["pin_span"] = 0.012
			_mk_box(node, Vector3(0.008, 0.007, 0.004), Vector3(0, 0.006, 0), Color(0.85, 0.6, 0.25, 1), 0.6)
			for sx in [-1.0, 1.0]:
				_mk_lead(node, Vector3(sx * 0.005, 0.004, 0), Vector3(sx * 0.012, LEAD_Y, 0))
		"c10u", "c470u":
			var big := catalog_id == "c470u"
			var r := 0.0055 if big else 0.004
			var h := 0.016 if big else 0.011
			out["size"] = Vector3(r * 2.0 + 0.002, h, 0.01)
			out["pin_span"] = 0.011 if big else 0.009
			_mk_cyl(node, r, h, Vector3(0, h * 0.5, 0), Color(0.18, 0.18, 0.20, 1), "y", 0.45)
			_mk_cyl(node, r * 0.9, 0.0015, Vector3(0, h + 0.0008, 0), Color(0.7, 0.71, 0.74, 1), "y", 0.3)
			_mk_box(node, Vector3(0.002, h, 0.0006), Vector3(0, h * 0.5, r), Color(0.75, 0.75, 0.78, 1))
			for sx in [-1.0, 1.0]:
				_mk_lead(node, Vector3(sx * 0.004, 0.003, 0), Vector3(sx * (0.011 if big else 0.009), LEAD_Y, 0))
		"led_red", "led_green", "led_ir":
			out["size"] = Vector3(0.016, 0.014, 0.01)
			out["pin_span"] = 0.008
			var col := Color(0.9, 0.15, 0.12, 1)
			if catalog_id == "led_green":
				col = Color(0.25, 0.9, 0.3, 1)
			elif catalog_id == "led_ir":
				col = Color(0.45, 0.12, 0.1, 1)
			_mk_led(node, col, out)
		"q_bc547":
			out["size"] = Vector3(0.020, 0.010, 0.010)
			out["pin_span"] = 0.009
			_mk_cyl(node, 0.0027, 0.006, Vector3(0, 0.006, 0), Color(0.14, 0.14, 0.15, 1), "y", 0.5)
			for sx in [-1.0, 0.0, 1.0]:
				_mk_lead(node, Vector3(sx * 0.0025, 0.004, 0), Vector3(sx * 0.006, LEAD_Y, 0))
				_mk_lead(node, Vector3(sx * 0.006, LEAD_Y, 0), Vector3(sx * 0.009, LEAD_Y, 0))
		"q_2n2222":
			out["size"] = Vector3(0.020, 0.009, 0.010)
			out["pin_span"] = 0.009
			_mk_cyl(node, 0.003, 0.005, Vector3(0, 0.0055, 0), Color(0.65, 0.66, 0.7, 1), "y", 0.3, 0.8)
			for sx in [-1.0, 0.0, 1.0]:
				_mk_lead(node, Vector3(sx * 0.0025, 0.004, 0), Vector3(sx * 0.006, LEAD_Y, 0))
				_mk_lead(node, Vector3(sx * 0.006, LEAD_Y, 0), Vector3(sx * 0.009, LEAD_Y, 0))
		"q_irf540", "ic_7805":
			out["size"] = Vector3(0.020, 0.030, 0.012)
			out["pin_span"] = 0.008
			_mk_to220(node, 0.008 if catalog_id == "ic_7805" else 0.005)
		"ic_ne555":
			out["size"] = Vector3(0.016, 0.010, 0.014)
			out["pin_span"] = 0.010
			_mk_dip(node, 0.010, 4)
		"ic_l293d":
			out["size"] = Vector3(0.026, 0.010, 0.014)
			out["pin_span"] = 0.015
			_mk_dip(node, 0.019, 7)
		"ic_atmega":
			out["size"] = Vector3(0.040, 0.010, 0.018)
			out["pin_span"] = 0.020
			_mk_dip(node, 0.035, 14)
		"ic_esp32":
			out["size"] = Vector3(0.055, 0.015, 0.030)
			out["pin_span"] = 0.030
			_mk_box(node, Vector3(0.055, 0.008, 0.028), Vector3(0, 0.006, 0), Color(0.1, 0.35, 0.2, 1), 0.6)
			_mk_box(node, Vector3(0.032, 0.010, 0.024), Vector3(-0.006, 0.013, 0), Color(0.75, 0.76, 0.79, 1), 0.3)
			_mk_box(node, Vector3(0.012, 0.008, 0.026), Vector3(0.020, 0.011, 0), Color(0.08, 0.1, 0.09, 1), 0.5)
		"s_dht11":
			out["size"] = Vector3(0.024, 0.026, 0.018)
			out["pin_span"] = 0.010
			_mk_box(node, Vector3(0.012, 0.024, 0.009), Vector3(0, 0.013, 0), Color(0.25, 0.45, 0.75, 1), 0.6)
			for i in 3:
				_mk_lead(node, Vector3(-0.002 + i * 0.002, 0.004, 0), Vector3(-0.004 + i * 0.004, LEAD_Y, 0))
				_mk_lead(node, Vector3(-0.004 + i * 0.004, LEAD_Y, 0), Vector3(-0.008 + i * 0.008, LEAD_Y, 0))
		"s_ds18b20":
			out["size"] = Vector3(0.040, 0.014, 0.012)
			out["pin_span"] = 0.014
			_mk_box(node, Vector3(0.008, 0.008, 0.006), Vector3(0.014, 0.006, 0), Color(0.14, 0.14, 0.15, 1), 0.5)
			_mk_cyl(node, 0.0025, 0.014, Vector3(0.002, 0.004, 0), Color(0.65, 0.66, 0.7, 1), "x", 0.3, 0.8)
			_mk_lead(node, Vector3(-0.006, 0.004, 0), Vector3(-0.010, LEAD_Y, 0))
			_mk_lead(node, Vector3(-0.010, LEAD_Y, 0), Vector3(-0.014, LEAD_Y, 0))
		"s_ldr":
			out["size"] = Vector3(0.020, 0.010, 0.012)
			out["pin_span"] = 0.008
			_mk_cyl(node, 0.004, 0.003, Vector3(0.004, 0.006, 0), Color(0.45, 0.2, 0.15, 1), "y", 0.4)
			_mk_cyl(node, 0.003, 0.004, Vector3(0.004, 0.003, 0), Color(0.8, 0.75, 0.65, 1), "y", 0.5)
			for sx in [-1.0, 1.0]:
				_mk_lead(node, Vector3(sx * 0.006, 0.004, 0), Vector3(sx * 0.006, LEAD_Y, 0))
				_mk_lead(node, Vector3(sx * 0.006, LEAD_Y, 0), Vector3(sx * 0.008, LEAD_Y, 0))
		"s_hcsr04":
			out["size"] = Vector3(0.045, 0.030, 0.030)
			out["pin_span"] = 0.025
			_mk_box(node, Vector3(0.045, 0.012, 0.025), Vector3(0, 0.010, 0), Color(0.15, 0.3, 0.55, 1), 0.6)
			_mk_cyl(node, 0.008, 0.012, Vector3(-0.012, 0.018, 0), Color(0.7, 0.71, 0.74, 1), "y", 0.35)
			_mk_cyl(node, 0.008, 0.012, Vector3(0.012, 0.018, 0), Color(0.7, 0.71, 0.74, 1), "y", 0.35)
		"bread830":
			out["size"] = Vector3(0.165, 0.02, 0.055)
			out["pin_span"] = 0.085
			_mk_box(node, Vector3(0.165, 0.018, 0.055), Vector3(0, 0.009, 0), Color(0.88, 0.87, 0.84, 1), 0.55)
			_mk_box(node, Vector3(0.16, 0.001, 0.008), Vector3(0, 0.019, 0), Color(0.15, 0.15, 0.15, 1))
			_mk_box(node, Vector3(0.16, 0.001, 0.006), Vector3(0, 0.019, -0.022), Color(0.75, 0.2, 0.18, 1))
			_mk_box(node, Vector3(0.16, 0.001, 0.006), Vector3(0, 0.019, 0.022), Color(0.2, 0.3, 0.7, 1))
		"w_mm":
			out["size"] = Vector3(0.03, 0.010, 0.010)
			out["pin_span"] = 0.017
			_mk_box(node, Vector3(0.012, 0.006, 0.008), Vector3(0, 0.005, 0), Color(0.15, 0.15, 0.16, 1), 0.5)
			var wcols := [Color(0.85, 0.2, 0.18, 1), Color(0.2, 0.3, 0.75, 1), Color(0.85, 0.75, 0.2, 1)]
			for i in 3:
				_mk_cyl(node, 0.0008, 0.020, Vector3(0.010, 0.005, -0.002 + i * 0.002), wcols[i], "x", 0.5)
		"lcd1602":
			out["size"] = Vector3(0.08, 0.016, 0.036)
			out["pin_span"] = 0.043
			_mk_box(node, Vector3(0.080, 0.008, 0.036), Vector3(0, 0.006, 0), Color(0.1, 0.35, 0.2, 1), 0.6)
			_mk_box(node, Vector3(0.062, 0.006, 0.022), Vector3(0, 0.013, 0), Color(0.08, 0.12, 0.1, 1), 0.3)
			_mk_legs(node, 8, 0.008, 0.006)
		"pot10k":
			out["size"] = Vector3(0.030, 0.018, 0.016)
			out["pin_span"] = 0.012
			_mk_cyl(node, 0.005, 0.008, Vector3(0, 0.005, 0), Color(0.2, 0.3, 0.55, 1), "y", 0.5)
			_mk_cyl(node, 0.002, 0.008, Vector3(0, 0.012, 0), Color(0.15, 0.15, 0.17, 1), "y", 0.4)
			_mk_sph(node, 0.002, Vector3(0.001, 0.016, 0), Color(0.9, 0.9, 0.92, 1))
			for sx in [-1.0, 0.0, 1.0]:
				_mk_lead(node, Vector3(sx * 0.004, 0.003, 0.006), Vector3(sx * 0.007, LEAD_Y, 0))
				_mk_lead(node, Vector3(sx * 0.007, LEAD_Y, 0), Vector3(sx * 0.012, LEAD_Y, 0))
		"btn":
			out["size"] = Vector3(0.018, 0.012, 0.014)
			out["pin_span"] = 0.009
			_mk_box(node, Vector3(0.006, 0.004, 0.006), Vector3(0, 0.004, 0), Color(0.12, 0.12, 0.13, 1), 0.5)
			_mk_cyl(node, 0.002, 0.005, Vector3(0, 0.007, 0), Color(0.8, 0.2, 0.18, 1), "y", 0.4)
			for sx in [-1.0, 1.0]:
				_mk_lead(node, Vector3(sx * 0.004, 0.004, 0), Vector3(sx * 0.007, LEAD_Y, 0))
				_mk_lead(node, Vector3(sx * 0.007, LEAD_Y, 0), Vector3(sx * 0.009, LEAD_Y, 0))
		"buzzer":
			out["size"] = Vector3(0.016, 0.016, 0.014)
			out["pin_span"] = 0.009
			_mk_cyl(node, 0.006, 0.009, Vector3(0, 0.0055, 0), Color(0.1, 0.1, 0.11, 1), "y", 0.5)
			_mk_cyl(node, 0.001, 0.0015, Vector3(0, 0.0108, 0), Color(0.05, 0.05, 0.05, 1), "y")
			for sx in [-1.0, 1.0]:
				_mk_lead(node, Vector3(sx * 0.003, 0.003, 0), Vector3(sx * 0.007, LEAD_Y, 0))
				_mk_lead(node, Vector3(sx * 0.007, LEAD_Y, 0), Vector3(sx * 0.009, LEAD_Y, 0))
		"servo":
			out["size"] = Vector3(0.032, 0.030, 0.024)
			out["pin_span"] = 0.014
			_mk_box(node, Vector3(0.023, 0.024, 0.012), Vector3(0, 0.014, 0), Color(0.2, 0.35, 0.6, 1), 0.5)
			_mk_box(node, Vector3(0.017, 0.005, 0.010), Vector3(0, 0.028, 0), Color(0.15, 0.25, 0.45, 1), 0.5)
			_mk_box(node, Vector3(0.014, 0.003, 0.004), Vector3(0, 0.032, 0), Color(0.9, 0.9, 0.92, 1), 0.4)
		_:
			out["size"] = Vector3(0.03, 0.012, 0.02)
			out["pin_span"] = 0.018
			_mk_box(node, Vector3(0.03, 0.012, 0.02), Vector3(0, 0.007, 0), Color(0.45, 0.5, 0.55, 1), 0.6)
			for sx in [-1.0, 1.0]:
				_mk_lead(node, Vector3(sx * 0.014, LEAD_Y, 0), Vector3(sx * 0.018, LEAD_Y, 0))
	return out

# ---------------------------------------------------------------- соединение

func connect_pins(a: String, b: String) -> bool:
	if a == b or _find_wire(a, b) != null:
		return false
	var pa := _pin_world(a)
	var pb := _pin_world(b)
	if pa == Vector3.INF or pb == Vector3.INF:
		return false
	var sim := _sim()
	var wcomp := ""
	if sim != null:
		wcomp = sim.add_comp("wire", _sim_node_of(a), _sim_node_of(b))
		sim.solve()
	_update_leds()
	var wid := "w%d" % _next_wid
	_next_wid += 1
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(WIRE_T, WIRE_T, maxf(pa.distance_to(pb), 0.005))
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.75, 0.2, 0.18, 1)
	box.material = m
	mi.mesh = box
	add_child(mi)
	wires.append({"wid": wid, "a": a, "b": b, "comp_id": wcomp, "node": mi})
	_refresh_wire(wires[wires.size() - 1])
	return true

func _wire_basis(dir: Vector3) -> Basis:
	var d := dir
	if d.length() < 1e-6:
		return Basis()
	var dn := d / d.length()
	var x_ax := Vector3.UP.cross(dn)
	if x_ax.length() < 1e-4:
		x_ax = Vector3(1, 0, 0)
	x_ax = x_ax.normalized()
	var z_ax := x_ax.cross(dn).normalized()
	return Basis(x_ax, dn, z_ax)

func _refresh_wire(w: Dictionary) -> void:
	var pa := _pin_world(w["a"])
	var pb := _pin_world(w["b"])
	var mi: MeshInstance3D = w["node"]
	var box: BoxMesh = mi.mesh
	box.size = Vector3(WIRE_T, WIRE_T, maxf(pa.distance_to(pb), 0.005))
	mi.transform = Transform3D(_wire_basis(pb - pa), (pa + pb) * 0.5)

func _refresh_wires() -> void:
	for w in wires:
		_refresh_wire(w)

func _find_wire(a: String, b: String):
	for w in wires:
		if (w["a"] == a and w["b"] == b) or (w["a"] == b and w["b"] == a):
			return w
	return null

# ---------------------------------------------------------------- удаление

func remove_part(pid: String) -> void:
	var rec := _part_by_pid(pid)
	if rec.is_empty():
		return
	var dead := []
	for w in wires:
		if w["a"].split(":")[0] == pid or w["b"].split(":")[0] == pid:
			dead.append(w)
	for w in dead:
		w["node"].queue_free()
		wires.erase(w)
		if _sim() != null and w["comp_id"] != "":
			_sim().remove_comp(w["comp_id"])
	if _sim() != null and rec["comp_id"] != "":
		_sim().remove_comp(rec["comp_id"])
	rec["root"].queue_free()
	parts.erase(rec)
	if _drag == pid:
		_drag = ""
	if _wire_from != "" and _wire_from.split(":")[0] == pid:
		_cancel_wire_drag()
	if _sim() != null:
		_sim().solve()
	_update_leds()
	_rebuild_panel()
	parts_changed.emit()

func clear_all_parts() -> void:
	for p in parts.duplicate():
		remove_part(p["pid"])

func counts_by_catalog() -> Dictionary:
	var out := {}
	for p in parts:
		var cid: String = p["catalog_id"]
		out[cid] = out.get(cid, 0) + 1
	return out

# первая плата ATmega328P (Arduino) на столе — её пин программирует код
func get_arduino() -> Dictionary:
	for p in parts:
		if p["catalog_id"] == "ic_atmega" and p["comp_id"] != "":
			return p
	return {}

func circuit_task_done() -> bool:
	# задание чертежа: любой светодиод на столе горит
	var sim := _sim()
	if sim == null:
		return false
	for p in parts:
		if p["sim"].get("type", "") == "led" and p["comp_id"] != "":
			if sim.is_led_on(p["comp_id"]):
				return true
	return false

# сигнал из редактора кода: цифровой пин платы HIGH/LOW -> напряжение источника
func set_arduino_pin(_pin: int, high: bool) -> void:
	var a := get_arduino()
	if a.is_empty() or _sim() == null:
		return
	_sim().set_source_voltage(a["comp_id"], 5.0 if high else 0.0)
	_update_leds()

# ---------------------------------------------------------------- ввод

func on_click(o: Vector3, d: Vector3) -> void:
	if not _active:
		return
	var pin := _pick_pin(o, d)
	if pin != "":
		_wire_from = pin
		_refresh_pin_styles()
		return
	var pid := _pick_part(o, d)
	if pid != "":
		_drag = pid
		return
	_wire_from = ""
	_temp_wire.visible = false
	_refresh_pin_styles()

func on_motion(o: Vector3, d: Vector3) -> void:
	if not _active:
		return
	if _wire_from != "":
		var from := _pin_world(_wire_from)
		var t := (0.733 - o.y) / d.y if absf(d.y) > 1e-6 else 0.0
		var to := o + d * maxf(t, 0.0)
		_update_temp_wire(from, to)
		return
	if _drag != "":
		_move_dragged(o, d)
		return
	_hover = _pick_pin(o, d)
	_refresh_pin_styles()

# отпускание ЛКМ: если тянули провод и попали в другой пин — соединяем
func end_drag(o: Vector3, d: Vector3) -> void:
	if _wire_from != "":
		var target := _pick_pin(o, d)
		if target != "" and target != _wire_from:
			connect_pins(_wire_from, target)
		_wire_from = ""
		_temp_wire.visible = false
		_refresh_pin_styles()
		return
	_drag = ""
	_refresh_wires()

func rotate_dragged() -> void:
	if _drag == "":
		return
	var rec := _part_by_pid(_drag)
	if rec.is_empty():
		return
	rec["yaw"] = fmod(rec["yaw"] + 90.0, 360.0)
	rec["root"].rotation.y = deg_to_rad(rec["yaw"])
	_refresh_wires()

func _update_temp_wire(from: Vector3, to: Vector3) -> void:
	var box: BoxMesh = _temp_wire.mesh
	box.size = Vector3(WIRE_T, WIRE_T, maxf(from.distance_to(to), 0.005))
	_temp_wire.visible = true
	_temp_wire.transform = Transform3D(_wire_basis(to - from), (from + to) * 0.5)

func _cancel_wire_drag() -> void:
	_wire_from = ""
	_temp_wire.visible = false

func _move_dragged(o: Vector3, d: Vector3) -> void:
	if absf(d.y) < 1e-6:
		return
	var rec := _part_by_pid(_drag)
	if rec.is_empty():
		return
	var t := (0.733 - o.y) / d.y
	if t < 0.0:
		return
	var p := o + d * t
	var sn := _snap_to_grid(p)
	var hw: float = rec["aabb"].size.x * 0.5
	var hd: float = rec["aabb"].size.z * 0.5
	sn.x = clampf(sn.x, GRID_ORIGIN.x + hw, GRID_ORIGIN.x + GRID_SIZE.x - hw)
	sn.z = clampf(sn.z, GRID_ORIGIN.z + hd, GRID_ORIGIN.z + GRID_SIZE.y - hd)
	rec["root"].position = sn
	_refresh_wires()

func _pick_part(o: Vector3, d: Vector3) -> String:
	var best := ""
	var best_d := INF
	for p in parts:
		var ab: AABB = p["root"].global_transform * p["aabb"]
		var hit = ab.intersects_ray(o, d)
		if hit != null:
			var dist: float = o.distance_to(hit)
			if dist < best_d:
				best_d = dist
				best = p["pid"]
	return best

# ---------------------------------------------------------------- пины

func _part_by_pid(pid: String) -> Dictionary:
	for p in parts:
		if p["pid"] == pid:
			return p
	return {}

func _sim_node(pid: String, side: String) -> String:
	return "pin:%s:%s" % [pid, side]

func _sim_node_of(pin_id: String) -> String:
	var pp := pin_id.split(":")
	return _sim_node(pp[0], pp[1])

func _pin_local(rec: Dictionary, side: String) -> Vector3:
	var mi: MeshInstance3D = rec["pins"][side]["mi"]
	return mi.position

func _pin_world(pin_id: String) -> Vector3:
	var pp := pin_id.split(":")
	var rec := _part_by_pid(pp[0])
	if rec.is_empty():
		return Vector3.INF
	return rec["root"].to_global(_pin_local(rec, pp[1]))

func _pick_pin(o: Vector3, d: Vector3) -> String:
	var best := ""
	var best_t := INF
	for p in parts:
		for side in ["L", "R"]:
			var c: Vector3 = p["root"].to_global(_pin_local(p, side))
			var t := _ray_sphere_t(o, d, c, PICK_R)
			if t >= 0.0 and t < best_t:
				best_t = t
				best = "%s:%s" % [p["pid"], side]
	return best

func _ray_sphere_t(o: Vector3, d: Vector3, c: Vector3, r: float) -> float:
	var oc := o - c
	var b := oc.dot(d)
	var cc := oc.dot(oc) - r * r
	var disc := b * b - cc
	if disc < 0.0:
		return -1.0
	var t := -b - sqrt(disc)
	return t

func _refresh_pin_styles() -> void:
	for p in parts:
		for side in ["L", "R"]:
			var id := "%s:%s" % [p["pid"], side]
			var pm: StandardMaterial3D = p["pins"][side]["mat"]
			if id == _wire_from:
				pm.emission_energy_multiplier = 1.6
			elif id == _hover:
				pm.emission_energy_multiplier = 0.8
			else:
				pm.emission_energy_multiplier = 0.25

# ---------------------------------------------------------------- состояние

func _update_leds() -> void:
	var sim := _sim()
	if sim == null:
		return
	for p in parts:
		if p["sim"].get("type", "") != "led" or p["comp_id"] == "":
			continue
		var mat: StandardMaterial3D = p["glow_mat"]
		if mat == null:
			continue
		var on: bool = sim.is_led_on(p["comp_id"])
		mat.emission_enabled = true
		mat.emission = p["sim"].get("color", Color(1, 0.1, 0.1))
		mat.emission_energy_multiplier = 1.6 if on else 0.0
