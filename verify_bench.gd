extends SceneTree
## Headless-тест зоны сборки: размещение деталей, провода, замкнутая цепь
##   godot --headless --path . --script res://verify_bench.gd

func _init() -> void:
	var sim: Node = load("res://Scripts/sim/circuit_sim.gd").new()
	sim.name = "CircuitSim"
	root.add_child(sim)
	var bench: Node3D = load("res://Scripts/game/bench.gd").new()
	root.add_child(bench)
	for i in 3:
		await process_frame
	bench.set_active(true)

	var psu: String = bench.place_part("psu5v")
	var res: String = bench.place_part("r220")
	var led: String = bench.place_part("led_red")
	var deco: String = bench.place_part("lcd1602")
	print("placed=%s,%s,%s,%s" % [psu, res, led, deco])
	var p_led: Dictionary = bench.get_part(led)
	var p_res: Dictionary = bench.get_part(res)
	var ok_place: bool = psu != "" and res != "" and led != "" and deco != "" \
		and not p_led.is_empty() and p_res["comp_id"] != "" and bench.get_part(deco)["comp_id"] == ""

	# замкнутая цепь: +БП -> R220 -> LED -> -БП (без земли)
	var w1: bool = bench.connect_pins(psu + ":L", res + ":L")
	var w2: bool = bench.connect_pins(res + ":R", led + ":L")
	var w3: bool = bench.connect_pins(led + ":R", psu + ":R")
	var n_wires: int = bench.wires.size()
	var wdup: bool = bench.connect_pins(psu + ":L", res + ":L")
	var led_on: bool = sim.is_led_on(p_led["comp_id"])
	var i_led: float = sim.get_current(p_led["comp_id"])
	var ok_circuit: bool = w1 and w2 and w3 and n_wires == 3 and not wdup \
		and led_on and i_led > 0.008 and i_led < 0.014
	print("wires=%d dup=%s led_on=%s I=%.4f -> %s" % [n_wires, wdup, led_on, i_led, ok_circuit])

	# провод зажатием: зажал пин — потянул — отпустил над другим пином
	var ra: String = bench.place_part("r1k")
	var rb: String = bench.place_part("r1k")
	var down := Vector3(0, -1, 0)
	var rA: Array = [bench._pin_world(ra + ":L") + Vector3(0, 1.0, 0), down]
	bench.on_click(rA[0], rA[1])
	var wstart_ok: bool = bench._wire_from == ra + ":L"
	bench.on_motion(rA[0], rA[1])
	var rB: Array = [bench._pin_world(rb + ":L") + Vector3(0, 1.0, 0), down]
	bench.end_drag(rB[0], rB[1])
	var ok_wire_drag: bool = wstart_ok and bench.wires.size() == 4 and bench._wire_from == ""
	print("wire_drag: start=%s wires=%d -> %s" % [wstart_ok, bench.wires.size(), ok_wire_drag])
	# клик мимо пинов/деталей не запускает тягу; отпускание мимо пина отменяет провод
	var rc: Array = [Vector3(0.02, 1.0, 0.61), down]
	bench.on_click(rc[0], rc[1])
	var ok_empty: bool = bench._wire_from == "" and bench.wires.size() == 4
	bench.on_click(bench._pin_world(ra + ":R") + Vector3(0, 1.0, 0), down)
	bench.end_drag(Vector3(0.02, 1.0, 0.61), down)
	var ok_cancel: bool = bench._wire_from == "" and bench.wires.size() == 4
	print("empty_click=%s cancel=%s" % [ok_empty, ok_cancel])

	# удаление детали, счётчики и очистка стола
	var cnt: Dictionary = bench.counts_by_catalog()
	bench.remove_part(res)
	var cnt2: Dictionary = bench.counts_by_catalog()
	var ok_remove: bool = bench.get_part(res).is_empty() and bench.wires.size() == 2 \
		and not sim.is_led_on(p_led["comp_id"]) and cnt.get("r220", 0) == 1 \
		and cnt2.get("r220", 0) == 0 and bench.place_part("r220") != "" \
		and bench.counts_by_catalog().get("r220", 0) == 1
	print("remove: wires=%d led_off=%s -> %s" % [bench.wires.size(), not sim.is_led_on(p_led["comp_id"]), ok_remove])
	bench.clear_all_parts()
	var ok_clear: bool = bench.parts.size() == 0 and bench.wires.size() == 0 \
		and bench.counts_by_catalog().is_empty()
	print("clear: parts=%d wires=%d -> %s" % [bench.parts.size(), bench.wires.size(), ok_clear])

	# сетка: перетаскивание со снапом и поворот на 90° по R
	var led2: String = bench.place_part("led_red")
	bench._drag = led2
	bench.rotate_dragged()
	var yaw: float = bench.get_part(led2)["root"].rotation.y
	bench.on_motion(Vector3(0.02, 1.5, 0.62), Vector3(0, -1, 0))
	var pos: Vector3 = bench.get_part(led2)["root"].position
	bench.end_drag(Vector3(0.02, 1.5, 0.62), Vector3(0, -1, 0))
	var gx: float = (pos.x - bench.GRID_ORIGIN.x) / bench.GRID_STEP
	var gz: float = (pos.z - bench.GRID_ORIGIN.z) / bench.GRID_STEP
	var ok_drag: bool = absf(yaw - PI / 2.0) < 1e-6 and bench._drag == "" \
		and absf(roundf(gx) - gx) < 1e-3 and absf(roundf(gz) - gz) < 1e-3
	print("drag: yaw=%.2f pos=%s grid_ok=%s -> %s" % [yaw, pos, ok_drag, ok_drag])

	if ok_place and ok_circuit and ok_wire_drag and ok_empty and ok_cancel \
			and ok_remove and ok_clear and ok_drag:
		print("VERIFY-OK bench")
	else:
		print("VERIFY-FAIL bench")
	quit()
