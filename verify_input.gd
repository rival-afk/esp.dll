extends SceneTree
## Е2Е по событиям мыши: клик пина → тяга → отпускание, перетаскивание детали
##   godot --headless --path . --script res://verify_input.gd

func _init() -> void:
	var game: Node = load("res://game.tscn").instantiate()
	root.add_child(game)
	for i in 5:
		await process_frame
	game._zoom("bench")
	var frames := 0
	while game.busy and frames < 400:
		await process_frame
		frames += 1
	print("bench active=", game.bench._active, " frames=", frames)
	# слоты заполняются слева направо — берём средние три (крайние могут быть
	# за пределами видимости в квадратном headless-вьюпорте)
	var ph: String = game.bench.place_part("r1k")   # прокладка на слот 0
	var board: String = game.bench.place_part("ic_atmega")
	var res: String = game.bench.place_part("r220")
	var led: String = game.bench.place_part("led_red")
	var cam: Camera3D = game.cam
	print("board=", board, " res=", res, " led=", led)

	# --- 1) пин -> пин через события мыши ---
	var posA: Vector2 = cam.unproject_position(game.bench._pin_world(board + ":L"))
	var posB: Vector2 = cam.unproject_position(game.bench._pin_world(res + ":L"))
	_inject_button(game, posA, true)
	print("wire_from after pin click: '", game.bench._wire_from, "'")
	var mv := InputEventMouseMotion.new()
	mv.position = posB
	game._unhandled_input(mv)
	var mvA := InputEventMouseMotion.new()
	mvA.position = (posA + posB) * 0.5
	game._unhandled_input(mvA)
	print("temp_wire visible: ", game.bench._temp_wire.visible)
	_inject_button(game, posB, false)
	print("wires=", game.bench.wires.size(), " wire_from='", game.bench._wire_from, "'")

	# --- 2) перетаскивание детали за корпус ---
	var center: Vector3 = game.bench.get_part(res)["root"].global_position \
		+ Vector3(0, 0.008, 0)
	var posC: Vector2 = cam.unproject_position(center)
	_inject_button(game, posC, true)
	print("_drag after press='", game.bench._drag, "'")
	var mv2 := InputEventMouseMotion.new()
	mv2.position = posC + Vector2(120, 60)
	game._unhandled_input(mv2)
	mv2.position = cam.unproject_position(Vector3(cam.global_position.x, cam.global_position.y, cam.global_position.z)) \
		+ Vector2(0, 0)  # noop, keep simple
	var mv3 := InputEventMouseMotion.new()
	mv3.position = posC + Vector2(120, 60)
	game._unhandled_input(mv3)
	_inject_button(game, posC + Vector2(120, 60), false)
	var moved: Vector3 = game.bench.get_part(res)["root"].global_position
	var orig := Vector3(-0.30, 0.733, 0.565)
	print("_drag after release='", game.bench._drag, "' pos=", moved)

	# --- 3) R — поворот перетаскиваемой детали ---
	_inject_button(game, cam.unproject_position(moved + Vector3(0, 0.008, 0)), true)
	var rkey := InputEventKey.new()
	rkey.keycode = KEY_R
	rkey.pressed = true
	game._unhandled_input(rkey)
	print("yaw deg=", rad_to_deg(game.bench.get_part(res)["yaw"]))
	_inject_button(game, cam.unproject_position(moved + Vector3(0, 0.008, 0)), false)
	quit()

func _inject_button(game: Node, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	game._unhandled_input(ev)
