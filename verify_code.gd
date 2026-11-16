extends SceneTree
## Headless-тест виртуальной Arduino и редактора кода:
##   godot --headless --path . --script res://verify_code.gd

func _init() -> void:
	var vm: Node = load("res://Scripts/sim/arduino_vm.gd").new()
	root.add_child(vm)
	for i in 2:
		await process_frame

	# --- тест 1: парсер — валидный код ---
	var code := """
void setup() {
  pinMode(13, OUTPUT);
}

void loop() {
  digitalWrite(13, HIGH);  // включить
  delay(120);
  digitalWrite(13, LOW);
  delay(120);
}
"""
	var err: String = vm.load_and_run(code)
	var ok1: bool = err == "" and vm.running
	print("T1 parse err='%s' running=%s -> %s" % [err, vm.running, ok1])

	# --- тест 2: исполнение — мигание за ~0.7 с ---
	var states: Array = []
	vm.pin_changed.connect(func(pin: int, high: bool):
		states.append([pin, high]))
	for i in 50:
		await process_frame
		await process_frame
	var ok2: bool = states.size() >= 3 \
		and states[0][0] == 13 and states[0][1] == true
	print("T2 events=%d first=%s -> %s" % [states.size(), states[0] if states.size() > 0 else "-", ok2])

	# --- тест 3: ошибки парсера ---
	var bad1: String = vm.load_and_run("void loop() { digitalWrite(13); }")
	var bad2: String = vm.load_and_run("void loop() { foo(1); }")
	var bad3: String = vm.load_and_run("void loop() { }")
	var ok3: bool = bad1 != "" and bad2 != "" and bad3 != ""
	print("T3 bad1='%s' bad2='%s' bad3='%s' -> %s" % [bad1, bad2, bad3, ok3])

	# --- тест 4: комментарии и регистр команд не ломают парсер ---
	var cmt := "// setup\nvoid loop() {\n  /* блок\n  комментарий */\n  digitalWrite(7, LOW);\n  delay(50);\n}\n"
	var err4: String = vm.load_and_run(cmt)
	var ok4: bool = err4 == ""
	print("T4 comments err='%s' -> %s" % [err4, ok4])

	vm.stop()
	if ok1 and ok2 and ok3 and ok4:
		print("VERIFY-OK code")
	else:
		print("VERIFY-FAIL code")
	quit()
