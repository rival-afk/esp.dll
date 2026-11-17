extends SceneTree
## Headless end-to-end тест MVP-цикла:
##   собрал цепь (плата + резистор + LED) -> прошил код мигания -> LED мигает
##   godot --headless --path . --script res://verify_mvp.gd

const CODE := """
void setup() {
  pinMode(13, OUTPUT);
}

void loop() {
  digitalWrite(13, HIGH);
  delay(150);
  digitalWrite(13, LOW);
  delay(150);
}
"""

func _init() -> void:
	var sim: Node = load("res://Scripts/sim/circuit_sim.gd").new()
	sim.name = "CircuitSim"
	root.add_child(sim)
	var bench: Node3D = load("res://Scripts/game/bench.gd").new()
	root.add_child(bench)
	for i in 3:
		await process_frame
	bench.set_active(true)

	# 1. сборка: плата ATmega (программируемый источник) + резистор + LED
	var board: String = bench.place_part("ic_atmega")
	var res: String = bench.place_part("r220")
	var led: String = bench.place_part("led_red")
	var ok_build: bool = board != "" and res != "" and led != "" \
		and bench.get_part(board)["comp_id"] != ""
	var w1: bool = bench.connect_pins(board + ":L", res + ":L")
	var w2: bool = bench.connect_pins(res + ":R", led + ":L")
	var w3: bool = bench.connect_pins(led + ":R", board + ":R")
	var ok_wires: bool = w1 and w2 and w3 and bench.wires.size() == 3
	# модель платы не должна сжиматься до пары сантиметров (фикс осей OBJ)
	var board_w: float = bench.get_part(board)["aabb"].size.x if board != "" else 0.0
	var ok_model: bool = board_w > 0.03
	print("build: board=%s wires=%d model_x=%.3f -> %s" % [
		ok_build, bench.wires.size(), board_w, ok_model])

	# 2. «прошивка»: тот же путь, что и редактор кода (vm.pin_changed -> bench)
	var vm: Node = load("res://Scripts/sim/arduino_vm.gd").new()
	root.add_child(vm)
	vm.pin_changed.connect(bench.set_arduino_pin)
	for i in 2:
		await process_frame
	var err: String = vm.load_and_run(CODE)
	var ok_upload: bool = err == "" and vm.running
	print("upload: err='%s' running=%s -> %s" % [err, vm.running, ok_upload])

	# 3. LED мигает: собираем состояния за ~50 кадров
	var led_comp: String = bench.get_part(led)["comp_id"]
	var flips: int = 0
	var prev: bool = sim.is_led_on(led_comp)
	for i in 90:
		await process_frame
		var on: bool = sim.is_led_on(led_comp)
		if on != prev:
			flips += 1
			prev = on
	var ok_blink: bool = flips >= 2
	print("blink: flips=%d last=%s -> %s" % [flips, sim.is_led_on(led_comp), ok_blink])

	# 4. стоп «платы» гасит LED (остановка прошивки)
	vm.stop()
	bench.set_arduino_pin(13, false)
	await process_frame
	await process_frame
	var ok_stop: bool = not sim.is_led_on(led_comp)
	print("stop: led_on=%s -> %s" % [sim.is_led_on(led_comp), ok_stop])

	# 5. задание чертежа засчитывается, пока плата гонит код
	vm.load_and_run(CODE)
	for i in 5:
		await process_frame
	var ok_task: bool = bench.circuit_task_done()
	print("task: circuit_task_done=%s -> %s" % [ok_task, ok_task])

	# 6. закрытие редактора не останавливает прошивку: LED продолжает мигать
	vm.stop()
	var ce: Control = load("res://Scenes/ui/code_editor.tscn").instantiate()
	root.add_child(ce)
	await process_frame
	ce.connect_pin_handler(bench.set_arduino_pin)
	ce.board_check = bench.has_arduino
	ce.visible = true
	ce._on_upload()
	var ok_upload2: bool = ce.out_label.text.begins_with("Скомпилировано") and ce._vm.running
	for i in 100:
		await process_frame
	ce._on_close()
	var flips_closed := 0
	prev = sim.is_led_on(led_comp)
	for i in 120:
		await process_frame
		var on: bool = sim.is_led_on(led_comp)
		if on != prev:
			flips_closed += 1
			prev = on
	var ok_after_close: bool = ok_upload2 and not ce.visible \
		and ce._vm.running and flips_closed >= 1
	print("close editor: running=%s hidden=%s flips_after=%d -> %s" % [
		ce._vm.running, not ce.visible, flips_closed, ok_after_close])

	if ok_build and ok_wires and ok_upload and ok_blink and ok_stop and ok_task \
			and ok_model and ok_after_close:
		print("VERIFY-OK mvp")
	else:
		print("VERIFY-FAIL mvp")
	quit()
