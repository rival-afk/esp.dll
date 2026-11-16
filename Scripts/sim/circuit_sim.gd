extends Node
## CircuitSim — ядро симуляции простых электронных цепей (autoload).
## Узлы — точки соединения; компоненты соединяют два узла:
##   wire     — провод (узлы считаются соединёнными напрямую)
##   resistor — резистор (value = сопротивление, Ом)
##   led      — светодиод (a = анод; value = Vf, падение в В)
##   vsource  — источник напряжения (a = «+», value = В)
## Решение: объединение узлов проводами (union-find) + MNA (узловой анализ
## с источниками напряжения). Светодиоды — итеративно: закрыт (разрыв) /
## открыт (LED_R_ON). После solve() доступны node_voltages / comp_results.

signal circuit_changed

const LED_R_ON := 50.0     # Ом, внутреннее сопротивление открытого LED
const LEAK_G := 1e-9       # «утечка» на землю от каждого узла (устраняет сингулярность)
const MAX_ITER := 8

var nodes: Array = []      # id узлов (String)
var comps := {}            # id -> {type, a, b, value, on}
var _next_id := 1

var node_voltages := {}    # node id -> V
var comp_results := {}     # comp id -> {on: bool, current: float, vdrop: float}
var _source_currents := {} # comp id -> A (через источник)

func _ready() -> void:
	if not nodes.has("gnd"):
		add_node("gnd")

# ---------------------------------------------------------------- построение

func add_node(id: String) -> void:
	if id != "" and not nodes.has(id):
		nodes.append(id)

func add_comp(type: String, a: String, b: String, value: float = 0.0) -> String:
	add_node(a)
	add_node(b)
	var id := "%s_%d" % [type, _next_id]
	_next_id += 1
	comps[id] = {"type": type, "a": a, "b": b, "value": value, "on": false}
	return id

func remove_comp(id: String) -> void:
	comps.erase(id)
	comp_results.erase(id)

# менять напряжение источника на лету (виртуальный Arduino: HIGH=5 В, LOW=0 В)
func set_source_voltage(comp_id: String, v: float) -> void:
	if comps.has(comp_id) and comps[comp_id]["type"] == "vsource":
		comps[comp_id]["value"] = v
		solve()

func clear_all() -> void:
	nodes.clear()
	comps.clear()
	node_voltages.clear()
	comp_results.clear()
	_source_currents.clear()
	add_node("gnd")

# ---------------------------------------------------------------- решение

func solve() -> bool:
	var parent := {}
	for n in nodes:
		parent[n] = n
	for c in comps.values():
		add_node(c.a)
		add_node(c.b)
		if c.type == "wire":
			_uf_union(parent, c.a, c.b)
	for c in comps.values():
		if c.type == "led":
			c.on = false
	var ok := true
	for i in MAX_ITER:
		ok = _solve_dc(parent)
		if not ok:
			break
		var changed := false
		for c in comps.values():
			if c.type != "led":
				continue
			var vd: float = node_voltages.get(c.a, 0.0) - node_voltages.get(c.b, 0.0)
			if not c.on and vd > c.value:
				c.on = true
				changed = true
			elif c.on and vd < c.value:
				c.on = false
				changed = true
		if not changed:
			break
	_solve_results()
	circuit_changed.emit()
	return ok

func _uf_find(p: Dictionary, x: String) -> String:
	while p[x] != x:
		p[x] = p[p[x]]
		x = p[x]
	return x

func _uf_union(p: Dictionary, a: String, b: String) -> void:
	var ra := _uf_find(p, a)
	var rb := _uf_find(p, b)
	if ra != rb:
		p[ra] = rb

func _solve_dc(parent: Dictionary) -> bool:
	# опорный узел: «минус» первого источника (если он есть), иначе gnd —
	# иначе замкнутая цепь без земли даёт вырожденную матрицу
	var ref_root := _uf_find(parent, "gnd")
	for cid in comps:
		if comps[cid].type == "vsource":
			ref_root = _uf_find(parent, comps[cid].b)
			break
	var idx := {}
	for n in nodes:
		var r := _uf_find(parent, n)
		if r != ref_root and not idx.has(r):
			idx[r] = idx.size()
	# источники: обычные vsource + открытые LED (Vf-источник + R_on через
	# внутренний узел); внутренние узлы получают индексы после idx.size()
	var sources := []  # {ia, ib, v, cid}
	var internal := 0
	for cid in comps:
		var c: Dictionary = comps[cid]
		var ia: int = idx.get(_uf_find(parent, c.a), -1)
		var ib: int = idx.get(_uf_find(parent, c.b), -1)
		if c.type == "vsource":
			sources.append({"ia": ia, "ib": ib, "v": c.value, "cid": cid})
		elif c.type == "led" and c.on:
			var iint: int = idx.size() + internal
			internal += 1
			sources.append({"ia": ia, "ib": iint, "v": c.value, "cid": cid})
	var n := idx.size() + internal
	var m := sources.size()
	var size := n + m
	node_voltages.clear()
	for nid in nodes:
		node_voltages[nid] = 0.0
	_source_currents.clear()
	if size == 0:
		return true
	var A := []
	var z := []
	for i in size:
		var row := []
		row.resize(size)
		row.fill(0.0)
		A.append(row)
		z.append(0.0)
	# KCL: утечка каждого реального узла на землю
	for r in idx:
		A[idx[r]][idx[r]] += LEAK_G
	# повторный проход: штампуем (нужны финальные индексы внутренних узлов)
	var int_i := 0
	for cid in comps:
		var c: Dictionary = comps[cid]
		var ia: int = idx.get(_uf_find(parent, c.a), -1)
		var ib: int = idx.get(_uf_find(parent, c.b), -1)
		match c.type:
			"resistor":
				_stamp_resistor(A, ia, ib, c.value)
			"led":
				if c.on:
					var iint: int = idx.size() + int_i
					int_i += 1
					_stamp_resistor(A, iint, ib, LED_R_ON)
			"wire":
				pass
	for s in sources:
		var k: int = n + sources.find(s)
		if s["ia"] >= 0:
			A[k][s["ia"]] += 1.0
		if s["ib"] >= 0:
			A[k][s["ib"]] -= 1.0
		z[k] = s["v"]
		if s["ia"] >= 0:
			A[s["ia"]][k] += 1.0
		if s["ib"] >= 0:
			A[s["ib"]][k] -= 1.0
	var x := _gauss(A, z, size)
	if x.is_empty():
		return false
	for nid in parent:
		var r := _uf_find(parent, nid)
		if r != ref_root:
			node_voltages[nid] = x[idx[r]]
	for i in m:
		_source_currents[sources[i]["cid"]] = x[n + i]
	return true

func _stamp_resistor(A: Array, ia: int, ib: int, ohms: float) -> void:
	if ia < 0 and ib < 0:
		return
	var g := 1.0 / maxf(ohms, 0.001)
	if ia >= 0:
		A[ia][ia] += g
	if ib >= 0:
		A[ib][ib] += g
	if ia >= 0 and ib >= 0:
		A[ia][ib] -= g
		A[ib][ia] -= g

func _gauss(A: Array, b: Array, n: int) -> Array:
	var M := []
	for i in n:
		var row: Array = A[i].duplicate()
		row.append(b[i])
		M.append(row)
	for col in n:
		var piv := col
		for r in range(col + 1, n):
			if absf(M[r][col]) > absf(M[piv][col]):
				piv = r
		if absf(M[piv][col]) < 1e-12:
			return []
		if piv != col:
			var t = M[piv]
			M[piv] = M[col]
			M[col] = t
		for r in range(col + 1, n):
			var f: float = M[r][col] / M[col][col]
			for cc in range(col, n + 1):
				M[r][cc] -= f * M[col][cc]
	var x := []
	x.resize(n)
	for i in range(n - 1, -1, -1):
		var s: float = M[i][n]
		for j in range(i + 1, n):
			s -= M[i][j] * x[j]
		x[i] = s / M[i][i]
	return x

func _solve_results() -> void:
	comp_results.clear()
	for cid in comps:
		var c: Dictionary = comps[cid]
		var va: float = node_voltages.get(c.a, 0.0)
		var vb: float = node_voltages.get(c.b, 0.0)
		var res := {"on": false, "current": 0.0, "vdrop": va - vb}
		match c.type:
			"resistor":
				res.current = (va - vb) / maxf(c.value, 0.001)
			"led":
				res.on = c.on
				if c.on:
					res.current = maxf((va - vb - c.value) / LED_R_ON, 0.0)
			"vsource":
				res.current = _source_currents.get(cid, 0.0)
		comp_results[cid] = res

# ---------------------------------------------------------------- запросы

func get_voltage(node_id: String) -> float:
	return node_voltages.get(node_id, 0.0)

func get_current(comp_id: String) -> float:
	if comp_results.has(comp_id):
		return comp_results[comp_id]["current"]
	return 0.0

func is_led_on(comp_id: String) -> bool:
	if comp_results.has(comp_id):
		return comp_results[comp_id]["on"]
	return false
