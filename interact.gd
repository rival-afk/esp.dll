extends Node3D
# Interactivity for the desk scene:
#   hover PC (whole monitor) -> screen lights up (OFF/ON texture swap)
#   hover papers             -> yellow overlay on the sheet meshes themselves
#   hover cabinet            -> translucent highlight plane
#   click zone               -> camera tweens to a close-up; right click / ESC -> back
#   ESC on overview          -> back to main menu (task 1.2)
#   TAB / P                  -> parts list overlay
# Zones are picked by camera ray vs world AABB of their meshes, so the whole
# PC / cabinet / paper stack is clickable.
# Verification (headless): GODOT_VERIFY = hover_pc | hover_papers | hover_parts |
#   zoom_pc | zoom_papers | zoom_parts | back_to_menu (run game.tscn explicitly)

const TEX_ON := "res://Textures/screen_on.png"
const ZONE_ORDER := ["pc", "papers", "bench", "parts"]
const SKIP_PAPERS := ["paper_025", "paper_032", "paper_033"]  # мятые листы — без подсветки

var cam: Camera3D
var screen_glow: OmniLight3D
var parts_glow: MeshInstance3D
var bench_glow: MeshInstance3D
var parts_list: Control
var bench: Node3D
var code_editor: Control
var blueprint: Control
var paper_hl_mat: StandardMaterial3D
var papers_meshes: Array = []
# zone -> world AABB used for ray picking
var zone_boxes := {}

var cam_target := Vector3(0.1495, 0.733, 0.012)
var overview_pos := Vector3(0.15567365, 1.4, 1.1491948)
var overview_trg := Vector3(0.1495, 0.733, 0.012)
# zone -> [camera pos, look-at target]  (calibrated for Models/workstation.tscn)
var poses := {
	# ПК: экран во весь кадр (дистанция 0.115 от плоскости экрана)
	"pc":     [Vector3(0.00, 1.0553, 0.366), Vector3(0.00, 1.0553, 0.2509)],
	"papers": [Vector3(-0.52, 1.15, 0.70), Vector3(-0.60, 0.74, 0.42)],
	# сборка: ортографический вид сверху (проекция включается в _zoom)
	"bench":  [Vector3(-0.04, 1.65, 0.605), Vector3(-0.04, -0.35, 0.605)],
	"parts":  [Vector3(0.80, 0.95, 1.30), Vector3(0.80, 0.55, 0.50)],
}

var mode := ""   # "" overview, else zoomed-in zone
var hover := ""
var busy := false
# HUD задания (6.1 mini): цель уровня + подсказки клавиш
var hud_task: Label
var hud_hint: Label
var hud_panel: PanelContainer
# fly state
var fly_p0 := Vector3.ZERO
var fly_t0 := Vector3.ZERO
var fly_p1 := Vector3.ZERO
var fly_t1 := Vector3.ZERO
var fly_up := Vector3.UP
# cursor follow: small smoothed yaw/pitch on top of the base camera pose
@export var follow_strength := Vector2(4.0, 2.5)  # degrees: yaw, pitch
@export var fly_duration := 1.1
var mouse_pos := Vector2(-1, -1)
var _follow := Vector2.ZERO  # radians (x=yaw, y=pitch)
var _base_tr := Transform3D.IDENTITY
# проекцию камеры меняем в конце пролёта (0 — не менять, 1 — ortho, 2 — persp)
var _pending_proj := 0

func _ready() -> void:
	cam = find_child("Camera3D", true) as Camera3D
	if cam:
		cam_target = overview_trg
	screen_glow = find_child("ScreenGlow", true) as OmniLight3D
	parts_glow = find_child("PartsGlow", true) as MeshInstance3D
	bench_glow = find_child("BenchGlow", true) as MeshInstance3D
	parts_list = find_child("PartsList", true)
	bench = find_child("Bench", true)
	code_editor = find_child("CodeEditor", true)
	blueprint = find_child("Blueprint", true)
	if bench != null:
		bench.set_active(false)
	if parts_list != null:
		parts_list.part_selected.connect(_on_part_selected)
	if bench != null and parts_list != null:
		bench.parts_changed.connect(_refresh_catalog_counts)
		parts_list.clear_desk_pressed.connect(_on_clear_desk)
		parts_list.visibility_changed.connect(_on_catalog_visibility)
	if code_editor != null and bench != null:
		code_editor.connect_pin_handler(bench.set_arduino_pin)
		code_editor.board_check = bench.has_arduino
	if blueprint != null:
		blueprint.provider = circuit_task_done
	paper_hl_mat = StandardMaterial3D.new()
	paper_hl_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paper_hl_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	paper_hl_mat.albedo_color = Color(1.0, 0.92, 0.55, 0.40)
	paper_hl_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_collect_zones()
	if screen_glow != null: screen_glow.visible = false
	if parts_glow != null: parts_glow.visible = false
	if bench_glow != null: bench_glow.visible = false
	if parts_list != null: parts_list.visible = false
	if code_editor != null: code_editor.visible = false
	if blueprint != null: blueprint.visible = false
	_set_screen(false)
	if cam != null:
		mouse_pos = cam.get_viewport().get_visible_rect().size * 0.5
		_base_tr = cam.global_transform
	var v := OS.get_environment("GODOT_VERIFY")
	if v != "":
		call_deferred("_verify", v)
	_build_hud()
	if OS.get_environment("GODOT_SHOT") != "":
		call_deferred("_shot")

func _process(delta: float) -> void:
	_update_hud()
	if cam == null or busy:
		return
	# в зуме на экран ПК слежение отключено — экран должен занимать весь кадр
	if mode == "pc":
		return
	if parts_list != null and parts_list.visible:
		return
	# в режиме сборки ортокамера панорамируется за курсором по зоне сборки
	if mode == "bench":
		if mouse_pos.x < 0.0:
			return
		var vp := cam.get_viewport().get_visible_rect().size
		if vp.x <= 0.0:
			return
		var m: float = clampf(mouse_pos.x / vp.x * 2.0 - 1.0, -1.0, 1.0)
		var target_x: float = clampf(-0.04 + m * 0.13, -0.19, 0.11)
		var p := cam.global_position
		p.x = lerpf(p.x, target_x, minf(1.0, delta * 6.0))
		cam.global_position = p
		return
	if mouse_pos.x < 0.0:
		return
	if mouse_pos.x < 0.0:
		return
	var vp := cam.get_viewport().get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	var m: Vector2 = ((mouse_pos / vp) * 2.0 - Vector2.ONE).clamp(
		Vector2(-1.0, -1.0), Vector2(1.0, 1.0))
	var target := Vector2(-m.x * deg_to_rad(follow_strength.x),
		-m.y * deg_to_rad(follow_strength.y))
	_follow = _follow.lerp(target, minf(1.0, delta * 5.0))
	var rot := Transform3D(Basis.from_euler(Vector3(_follow.y, _follow.x, 0.0)), Vector3.ZERO)
	cam.global_transform = _base_tr * rot

# ---------------------------------------------------------------- helpers

func _mesh_by_name(n: Node, want: String) -> MeshInstance3D:
	if n is MeshInstance3D and String(n.name) == want:
		return n
	for c in n.get_children():
		var r = _mesh_by_name(c, want)
		if r != null:
			return r
	return null

func _all_meshes(n: Node) -> Array:
	var out := []
	for c in n.get_children():
		if c is MeshInstance3D:
			out.append(c)
		out.append_array(_all_meshes(c))
	return out

func _world_aabb(mi: MeshInstance3D) -> AABB:
	return mi.global_transform * mi.get_aabb()

const CABINET_MESHES := [
	"Filing Cainet Base_015", "File Box 1_001", "File Box 1_005",
	"File Box 2 Lid_001", "File Box 2 Lid_004",
]

func _collect_zones() -> void:
	var ws := find_child("Workstation", true)
	if ws == null:
		return
	var mon := _mesh_by_name(ws, "PC_HP")
	var scr := _mesh_by_name(ws, "PC_HP_001")
	if mon != null:
		zone_boxes["pc"] = _world_aabb(mon)
		if scr != null:
			zone_boxes["pc"] = zone_boxes["pc"].merge(_world_aabb(scr))
	var paper_box := AABB()
	var paper_found := false
	var cab_box := AABB()
	var cab_found := false
	for mi in _all_meshes(ws):
		var n := String(mi.name)
		if n.begins_with("paper_"):
			if n in SKIP_PAPERS:
				continue
			papers_meshes.append(mi)
			paper_box = _world_aabb(mi) if not paper_found else paper_box.merge(_world_aabb(mi))
			paper_found = true
		elif n in CABINET_MESHES:
			cab_box = _world_aabb(mi) if not cab_found else cab_box.merge(_world_aabb(mi))
			cab_found = true
	if paper_found:
		# rotated sheet AABBs inflate the merged box far below the desk top;
		# clamp it to the region where the sheets actually sit
		zone_boxes["papers"] = paper_box.intersection(
			AABB(Vector3(-0.75, 0.68, 0.15), Vector3(0.35, 0.18, 0.47)))
	if cab_found:
		zone_boxes["parts"] = cab_box
	# зона сборки схем: перед ПК, между бумагами и шкафом (столешница)
	zone_boxes["bench"] = AABB(Vector3(-0.40, 0.72, 0.48), Vector3(0.98, 0.10, 0.22))

func _set_screen(on: bool) -> void:
	var mi: MeshInstance3D = null
	var ws := find_child("Workstation", true)
	if ws != null:
		mi = _mesh_by_name(ws, "PC_HP_001")
	if mi == null:
		return
	var mat := StandardMaterial3D.new()
	mat.grow = true
	mat.grow_amount = 0.0008   # сдвиг к зрителю: убирает z-файтинг со стеклом корпуса
	if on:
		# textured glow independent of scene lighting
		mat.albedo_color = Color(0.04, 0.04, 0.04)
		mat.emission_enabled = true
		if OS.get_environment("GODOT_NOTEX") != "":
			mat.emission = Color(1.0, 0.65, 0.2)
		elif OS.get_environment("GODOT_ALBEDOTEX") != "":
			mat.albedo_texture = load("res://Textures/diag_uv.png")
			mat.albedo_color = Color(1, 1, 1)
			mat.emission_enabled = false
		else:
			mat.emission_texture = load(TEX_ON)
			mat.emission = Color(1.0, 1.0, 1.0)
		mat.roughness = 1.0
	else:
		mat.albedo_color = Color(0.03, 0.035, 0.03)
		mat.roughness = 0.9
	mi.set_surface_override_material(0, mat)
	if screen_glow != null:
		screen_glow.visible = on

func _set_papers_highlight(on: bool) -> void:
	for mi in papers_meshes:
		mi.set_surface_override_material(0, paper_hl_mat if on else null)

func _hover_hit(mouse: Vector2) -> String:
	if cam == null:
		return ""
	var o := cam.global_position
	var d := cam.project_ray_normal(mouse)
	for zone in ZONE_ORDER:
		if zone_boxes.has(zone) and zone_boxes[zone].intersects_ray(o, d) != null:
			return zone
	return ""

func _apply_hover(zone: String) -> void:
	hover = zone
	_set_screen(zone == "pc")
	_set_papers_highlight(zone == "papers")
	if parts_glow != null:
		parts_glow.visible = zone == "parts"
	if bench_glow != null:
		bench_glow.visible = zone == "bench"

# ---------------------------------------------------------------- camera fly

func _fly_step(k: float) -> void:
	var p := fly_p0.lerp(fly_p1, k)
	var t := cam_target.lerp(fly_t1, k)
	cam.global_transform = Transform3D(Basis.looking_at(t - p, fly_up), p)
	cam_target = t

func _fly_done() -> void:
	busy = false
	_base_tr = cam.global_transform
	_follow = Vector2.ZERO
	_apply_projection()
	# после зума на шкаф сразу открываем каталог деталей
	if mode == "parts" and parts_list != null and not parts_list.visible:
		parts_list.visible = true
	# зум на ПК открывает редактор кода Arduino
	if mode == "pc" and code_editor != null and not code_editor.visible:
		code_editor.visible = true
	# зум на чертежи открывает чертёж задания
	if mode == "papers" and blueprint != null and not blueprint.visible:
		blueprint.visible = true
	# в зуме сборки включаем пины и панель
	if mode == "bench" and bench != null:
		bench.set_active(true)

func _fly(pos: Vector3, trg: Vector3, dur: float = fly_duration, up_hint := Vector3.UP) -> void:
	busy = true
	fly_up = up_hint
	fly_p0 = cam.global_position
	fly_t0 = cam_target
	fly_p1 = pos
	fly_t1 = trg
	var tw := create_tween()
	tw.tween_method(_fly_step, 0.0, 1.0, dur) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.finished.connect(_fly_done)

# проекцию камеры меняем только после пролёта — иначе вид «дёргается» на стыке
func _apply_projection() -> void:
	if cam == null or _pending_proj == 0:
		return
	if _pending_proj == 1:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 0.22
	elif _pending_proj == 2:
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = 65.0
	_pending_proj = 0

func _on_part_selected(part_id: String) -> void:
	# клик по карточке каталога -> деталь автоматически появляется на столе
	if bench != null:
		bench.place_part(part_id)

func _refresh_catalog_counts() -> void:
	if bench != null and parts_list != null:
		parts_list.update_counts(bench.counts_by_catalog())

func _on_catalog_visibility() -> void:
	_refresh_catalog_counts()
	if bench != null and parts_list != null:
		bench.set_blocking_ui(parts_list.visible)

func _on_clear_desk() -> void:
	if bench != null:
		bench.clear_all_parts()

func circuit_task_done() -> bool:
	return bench != null and bench.circuit_task_done()

# закрыть открытый оверлей (каталог/редактор/чертёж); true — если был открыт
func _close_any_overlay() -> bool:
	if parts_list != null and parts_list.visible:
		_toggle_parts()
		return true
	if code_editor != null and code_editor.visible:
		code_editor._on_close()
		return true
	if blueprint != null and blueprint.visible:
		blueprint.visible = false
		return true
	return false

func _hide_overlays() -> void:
	if parts_list != null: parts_list.visible = false
	if code_editor != null: code_editor.visible = false
	if blueprint != null: blueprint.visible = false

func _zoom(zone: String) -> void:
	mode = zone
	var pose = poses[zone]
	_hide_overlays()
	if cam != null:
		# проекцию меняем только в конце пролёта — не «дёргает» камеру
		_pending_proj = 1 if zone == "bench" else 2
		_fly(pose[0], pose[1], fly_duration, Vector3(0, 0, -1) if zone == "bench" else Vector3.UP)
	if zone != "bench" and bench != null:
		bench.set_active(false)

func _back() -> void:
	mode = ""
	_hide_overlays()
	if cam != null:
		_pending_proj = 2
	_fly(overview_pos, overview_trg)
	if bench != null:
		bench.set_active(false)

# 1.2: ESC на общем плане — выход в главное меню (замыкает цикл меню ↔ игра)
func _return_to_menu() -> void:
	_hide_overlays()
	if bench != null:
		bench.set_active(false)
	var tree := get_tree()
	var err := tree.change_scene_to_file("res://Scenes/ui/main_menu.tscn")
	if OS.get_environment("GODOT_VERIFY") == "back_to_menu":
		print("VERIFY-OK back_to_menu err=", err)
		tree.quit()

# ---------------------------------------------------------------- input

func _toggle_parts() -> void:
	if parts_list == null:
		return
	parts_list.visible = not parts_list.visible
	_apply_hover("")
	if not parts_list.visible and mode == "parts":
		_back()

func _unhandled_input(e: InputEvent) -> void:
	if cam == null:
		return
	if e is InputEventKey and e.pressed and (e.keycode == KEY_TAB or e.keycode == KEY_P):
		_toggle_parts()
		return
	if e is InputEventKey and e.pressed and e.keycode == KEY_R and mode == "bench" and bench != null:
		bench.rotate_dragged()
		return
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE \
			and parts_list != null and parts_list.visible:
		_toggle_parts()   # сам вернёт камеру, если зумились на шкаф
		return
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE \
			and code_editor != null and code_editor.visible:
		code_editor._on_close()
		if mode == "pc":
			_back()   # один ESC закрывает редактор и отводит камеру
		return
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE \
			and blueprint != null and blueprint.visible:
		blueprint.visible = false
		if mode == "papers":
			_back()   # один ESC закрывает чертёж и отводит камеру
		return
	if busy:
		return
	if e is InputEventMouseMotion:
		mouse_pos = e.position
		if mode == "":
			_apply_hover(_hover_hit(e.position))
		elif mode == "bench" and bench != null:
			bench.on_motion(cam.global_position, cam.project_ray_normal(e.position))
	elif e is InputEventMouseButton:
		var press: bool = e.pressed
		if mode == "":
			if press and e.button_index == MOUSE_BUTTON_LEFT and hover != "":
				var z := hover
				_apply_hover("")
				_zoom(z)
		elif mode == "bench":
			if e.button_index == MOUSE_BUTTON_LEFT and bench != null:
				if press:
					bench.on_click(cam.global_position, cam.project_ray_normal(e.position))
				else:
					bench.end_drag(cam.global_position, cam.project_ray_normal(e.position))
			elif press and e.button_index == MOUSE_BUTTON_RIGHT:
				_back()
		else:
			if press and (e.button_index == MOUSE_BUTTON_RIGHT or e.button_index == MOUSE_BUTTON_LEFT):
				_back()
	elif e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE and mode != "":
		_back()
	elif e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		_return_to_menu()

# ---------------------------------------------------------------- hud / shots

# 6.1 (mini): HUD с целью уровня и подсказками; гаснет, когда задание выполнено
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "TaskHUD"
	add_child(layer)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.06, 0.045, 0.82)
	style.set_corner_radius_all(4)
	style.content_margin_left = 12.0
	style.content_margin_top = 8.0
	style.content_margin_right = 12.0
	style.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", style)
	var vb := VBoxContainer.new()
	hud_task = Label.new()
	hud_task.text = "Задание: соберите цепь 5 В → 220 Ом → LED\n(чертёж — на бумагах слева)"
	hud_task.add_theme_font_size_override("font_size", 15)
	hud_hint = Label.new()
	hud_hint.text = "ЛКМ по зоне — подойти · TAB/P — каталог · ЛКМ пин→пин — провод\nR — поворот детали · ПКМ/ESC — назад · ESC на общем плане — меню"
	hud_hint.add_theme_font_size_override("font_size", 12)
	hud_hint.modulate = Color(1, 0.9, 0.75, 0.85)
	vb.add_child(hud_task)
	vb.add_child(hud_hint)
	panel.add_child(vb)
	layer.add_child(panel)
	panel.position = Vector2(16, 16)
	hud_panel = panel
	# HUD не должен ловить мышь и мешать кликам по игре
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_task.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _update_hud() -> void:
	if hud_panel == null:
		return
	# HUD виден только на общем плане без открытых окон — не заслоняет UI
	hud_panel.visible = mode == "" \
		and not (parts_list != null and parts_list.visible) \
		and not (code_editor != null and code_editor.visible) \
		and not (blueprint != null and blueprint.visible)
	if hud_task == null:
		return
	if circuit_task_done():
		hud_task.text = "Задание выполнено ✓  LED горит"
		hud_task.add_theme_color_override("font_color", Color(0.55, 0.85, 0.5))
	else:
		hud_task.text = "Задание «Светофор»: зажги светодиод\n(пин платы → резистор 220 Ом → LED → GND; чертёж — на бумагах)"
		hud_task.remove_theme_color_override("font_color")

# автоскриншоты: GODOT_SHOT=1 godot --path . res://game.tscn
func _save_shot(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(path))
	print("SHOT saved ", path)

# ждём окончания полёта камеры и (опц.) открытия оверлея — максимум ~3 с
func _wait_ready(extra_visible: Node = null) -> void:
	var frames := 0
	while frames < 400:
		var ready := not busy
		if extra_visible != null:
			ready = ready and extra_visible.visible
		if ready:
			break
		await get_tree().process_frame
		frames += 1
	for i in 12:
		await get_tree().process_frame

func _shot() -> void:
	await _wait_ready()
	_save_shot("res://Screenshots/auto_overview.png")
	# экран ПК + редактор кода
	_zoom("pc")
	_set_screen(true)
	await _wait_ready(code_editor)
	_save_shot("res://Screenshots/auto_pc.png")
	# чертёж на бумагах (открывается сам в _fly_done)
	_zoom("papers")
	await _wait_ready(blueprint)
	_save_shot("res://Screenshots/auto_blueprint.png")
	# сборка: собранная цепь в редакторе (вид сверху)
	if bench != null:
		bench.set_active(true)
		var board: String = bench.place_part("ic_atmega")
		var res: String = bench.place_part("r220")
		var led: String = bench.place_part("led_red")
		bench.connect_pins(board + ":L", res + ":L")
		bench.connect_pins(res + ":R", led + ":L")
		bench.connect_pins(led + ":R", board + ":R")
	_zoom("bench")
	await _wait_ready()
	_save_shot("res://Screenshots/auto_bench.png")
	# каталог деталей (открывается сам после зума на шкаф)
	_zoom("parts")
	await _wait_ready(parts_list)
	_save_shot("res://Screenshots/auto_catalog.png")
	print("SHOTS-DONE")
	get_tree().quit()

# ---------------------------------------------------------------- verify

func _verify(v: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	print("ZONES ", zone_boxes)
	var task0 := "Задание «Светофор»: зажги светодиод\n(пин платы → резистор 220 Ом → LED → GND; чертёж — на бумагах)"
	if v == "hud":
		var ok_hud: bool = hud_task != null and hud_task.text == task0 \
			and hud_hint != null and hud_panel != null and hud_panel.visible
		print("VERIFY-OK hud task=%s" % ok_hud)
		get_tree().quit()
		return
	if v == "back_to_menu":
		_return_to_menu()
		return
	if not (v.begins_with("hover_") or v.begins_with("zoom_")):
		return
	var zone := v.substr(v.find("_") + 1)
	if v.begins_with("zoom_"):
		var pose = poses[zone]
		cam.global_transform = Transform3D(Basis.looking_at(pose[1] - pose[0], Vector3.UP), pose[0])
		cam_target = pose[1]
		mode = zone
	if zone == "pc":
		_set_screen(true)
	elif zone == "papers":
		_set_papers_highlight(true)
	elif zone == "parts":
		if parts_glow != null: parts_glow.visible = true
	elif zone == "bench":
		if bench_glow != null: bench_glow.visible = true
	print("VERIFY-OK ", v)
