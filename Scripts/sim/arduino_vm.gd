extends Node
## Учебная виртуальная Arduino: парсер подмножества C и исполнитель loop().
## Поддерживаются команды: pinMode(A, OUTPUT/INPUT), digitalWrite(A, HIGH/LOW),
## delay(мс), а также пустые строки, комментарии // и /* */.
## signal pin_changed(pin, high) -> взаимодействие с CircuitSim через bench.
## Headless-тест: verify_code.gd

signal pin_changed(pin: int, high: bool)
signal upload_error(msg: String)

var running := false
var _setup := []   # выполняются мгновенно при загрузке
var _loop := []    # крутятся бесконечно
var _idx := 0
var _acc := 0.0
var _wait := 0.0
var _pin_states := {}   # pin -> bool

func stop() -> void:
	running = false
	_setup.clear()
	_loop.clear()
	_idx = 0
	_acc = 0.0
	_wait = 0.0

func _strip_comments(src: String) -> String:
	var out := ""
	var in_block := false
	for line in src.split("\n"):
		if in_block:
			var end_pos := line.find("*/")
			if end_pos == -1:
				continue
			in_block = false
			line = line.substr(end_pos + 2)
		var cpos := line.find("/*")
		if cpos != -1:
			var epos := line.find("*/", cpos + 2)
			if epos == -1:
				in_block = true
				line = line.substr(0, cpos)
			else:
				line = line.substr(0, cpos) + line.substr(epos + 2)
		var spos := line.find("//")
		if spos != -1:
			line = line.substr(0, spos)
		out += line + "\n"
	return out

# извлечь тело функции "void NAME()" -> массив строк или пустой массив
func _extract_body(src: String, name: String) -> Array:
	var marker := "void %s()" % name
	var f := src.find(marker)
	if f == -1:
		return []
	var brace := src.find("{", f)
	if brace == -1:
		return []
	var depth := 0
	var body := []
	var cur := ""
	for i in range(brace, src.length()):
		var ch := src[i]
		if ch == "{":
			depth += 1
			if depth == 1:
				continue
		elif ch == "}":
			depth -= 1
			if depth == 0:
				if cur.strip_edges() != "":
					body.append(cur.strip_edges())
				return body
		if depth >= 1:
			if ch == ";":
				if cur.strip_edges() != "":
					body.append(cur.strip_edges())
				cur = ""
			else:
				cur += ch
	return body

# разобрать строку-оператор; вернуть Dictionary или {err: "..."}
func _parse_stmt(line: String) -> Dictionary:
	var l := line.replace(" ", "").replace("\t", "")
	if l == "":
		return {"op": "nop"}
	if l.begins_with("digitalWrite(") and l.ends_with(")"):
		var args := l.substr(13, l.length() - 14).split(",")
		if args.size() != 2:
			return {"err": "digitalWrite ждёт 2 аргумента: %s" % line}
		var pin := args[0].to_int()
		if args[1] == "HIGH":
			return {"op": "write", "pin": pin, "high": true}
		if args[1] == "LOW":
			return {"op": "write", "pin": pin, "high": false}
		return {"err": "digitalWrite: только HIGH или LOW: %s" % line}
	if l.begins_with("pinMode(") and l.ends_with(")"):
		var args := l.substr(8, l.length() - 9).split(",")
		if args.size() != 2:
			return {"err": "pinMode ждёт 2 аргумента: %s" % line}
		return {"op": "mode", "pin": args[0].to_int(), "out": args[1] == "OUTPUT"}
	if l.begins_with("delay(") and l.ends_with(")"):
		var ms := l.substr(6, l.length() - 7).to_int()
		if ms < 0:
			return {"err": "delay: отрицательное время: %s" % line}
		return {"op": "delay", "ms": ms}
	return {"err": "Не знаю такую команду: %s" % line}

# вернуть "" при успехе, иначе текст ошибки
func load_and_run(code: String) -> String:
	stop()
	var src := _strip_comments(code)
	var setup_lines := _extract_body(src, "setup")
	var loop_lines := _extract_body(src, "loop")
	for l in setup_lines:
		var st := _parse_stmt(l)
		if st.has("err"):
			return st["err"]
		if st["op"] == "write":
			pin_changed.emit(st["pin"], st["high"])
	for l in loop_lines:
		var st := _parse_stmt(l)
		if st.has("err"):
			return st["err"]
		if st["op"] != "nop":
			_loop.append(st)
	if _loop.is_empty():
		return "В loop() нет команд — нечего выполнять"
	_idx = 0
	_acc = 0.0
	_wait = 0.0
	running = true
	return ""

func _process(delta: float) -> void:
	if not running or _loop.is_empty():
		return
	_acc += delta
	var guard := 0
	while _acc >= _wait and guard < 1000:
		guard += 1
		_acc -= _wait
		_wait = 0.0
		var st: Dictionary = _loop[_idx]
		_idx = (_idx + 1) % _loop.size()
		match st["op"]:
			"write":
				_pin_states[st["pin"]] = st["high"]
				pin_changed.emit(st["pin"], st["high"])
			"mode":
				pass
			"delay":
				_wait = st["ms"] / 1000.0
				return
	if guard >= 1000:
		_wait = 0.05   # защита от цикла без delay: не быстрее 20 Гц

func pin_state(pin: int) -> bool:
	return _pin_states.get(pin, false)
