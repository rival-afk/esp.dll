extends SceneTree
## Headless-тест ядра симуляции цепей:
##   godot --headless --path . --script res://verify_sim.gd

func _init() -> void:
	var sim: Node = load("res://Scripts/sim/circuit_sim.gd").new()
	root.add_child(sim)

	# --- тест 1: 5V -> R220 -> LED(Vf=2) -> gnd ---
	var src: String = sim.add_comp("vsource", "p5v", "gnd", 5.0)
	var r1: String = sim.add_comp("resistor", "p5v", "nled", 220.0)
	var led: String = sim.add_comp("led", "nled", "gnd", 2.0)
	var ok: bool = sim.solve()
	var v5: float = sim.get_voltage("p5v")
	var vl: float = sim.get_voltage("nled")
	var il: float = sim.get_current(led)
	# открытый LED: I = (5-2)/(220+50) = 11.1 мА, v(nled) = 2 + I*50 = 2.556
	var ok1: bool = ok and absf(v5 - 5.0) < 1e-6 and sim.is_led_on(led) \
		and absf(il - 0.0111) < 0.002 and vl > 2.0 and vl < 3.0
	print("T1 src_v=%.3f led_v=%.3f led_I=%.4f on=%s -> %s" % [v5, vl, il, sim.is_led_on(led), ok1])

	# --- тест 2: параллельные резисторы: 5V -> R220 -> [R220 || R220] -> gnd ---
	sim.clear_all()
	sim.add_comp("vsource", "a", "gnd", 5.0)
	sim.add_comp("resistor", "a", "mid", 220.0)
	var r2: String = sim.add_comp("resistor", "mid", "gnd", 220.0)
	var r3: String = sim.add_comp("resistor", "mid", "gnd", 220.0)
	ok = sim.solve()
	var vm: float = sim.get_voltage("mid")
	# эквивалент 110 Ом: v(mid) = 5*110/330 = 1.667, I каждый = 7.58 мА
	var i2: float = sim.get_current(r2)
	var ok2: bool = ok and absf(vm - 1.6667) < 0.02 and absf(i2 - 0.007576) < 0.001 \
		and absf(sim.get_current(r3) - i2) < 1e-6
	print("T2 mid_v=%.3f i2=%.4f i3=%.4f -> %s" % [vm, i2, sim.get_current(r3), ok2])

	# --- тест 3: разомкнутая цепь и провод-объединение ---
	sim.clear_all()
	sim.add_comp("vsource", "a", "gnd", 5.0)
	var rw: String = sim.add_comp("wire", "a", "b")
	var rl: String = sim.add_comp("resistor", "b", "c", 220.0)
	var led2: String = sim.add_comp("led", "c", "gnd", 2.0)
	ok = sim.solve()
	var vb: float = sim.get_voltage("b")
	var vc: float = sim.get_voltage("c")
	var ok3: bool = ok and sim.is_led_on(led2) and absf(vb - 5.0) < 1e-6 \
		and absf(vc - (2.0 + 3.0 / 270.0 * 50.0)) < 0.02
	print("T3 wire_v=%.3f led_v=%.3f on=%s -> %s" % [vb, vc, sim.is_led_on(led2), ok3])

	# --- тест 4: без источника всё погашено ---
	sim.clear_all()
	sim.add_comp("vsource", "a", "gnd", 0.0)
	var led3: String = sim.add_comp("led", "a", "gnd", 2.0)
	sim.solve()
	var ok4: bool = not sim.is_led_on(led3) and sim.get_voltage("a") < 1e-9
	print("T4 dead on=%s v=%.3f -> %s" % [sim.is_led_on(led3), sim.get_voltage("a"), ok4])

	if ok1 and ok2 and ok3 and ok4:
		print("VERIFY-OK sim")
	else:
		print("VERIFY-FAIL sim")
	quit()
