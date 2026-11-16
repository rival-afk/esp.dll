extends Control
## Лист деталей: поиск сверху слева, сетка 4 колонки, скролл вниз.
## Открывается в игре по TAB / P (переключение из interact.gd).
## Headless-верификация: GODOT_VERIFY=parts (запуск сцены напрямую).

const PartsDB = preload("res://Scripts/data/parts_db.gd")

signal part_selected(part_id: String)
signal clear_desk_pressed

@onready var search_edit: LineEdit = %SearchEdit
@onready var parts_grid: GridContainer = %PartsGrid
@onready var count_label: Label = %CountLabel
@onready var clear_button: Button = %ClearButton

var _cards := []  # [[Button, Dictionary entry], ...]
var _count_labels := {}  # part_id -> Label (сколько на столе)
var _card_style := StyleBoxFlat.new()
var _card_hover := StyleBoxFlat.new()
var _card_pressed := StyleBoxFlat.new()

func _ready() -> void:
	_card_style.bg_color = Color(0.13, 0.11, 0.09, 1)
	_card_style.set_border_width_all(1)
	_card_style.border_color = Color(1, 0.82, 0.58, 0.12)
	_card_style.set_corner_radius_all(3)
	_card_style.set_content_margin_all(12)
	_card_hover.bg_color = Color(0.2, 0.17, 0.13, 1)
	_card_hover.set_border_width_all(1)
	_card_hover.border_color = Color(1, 0.82, 0.58, 0.3)
	_card_hover.set_corner_radius_all(3)
	_card_hover.set_content_margin_all(12)
	_card_pressed.bg_color = Color(0.26, 0.21, 0.15, 1)
	_card_pressed.set_border_width_all(1)
	_card_pressed.border_color = Color(1, 0.82, 0.58, 0.5)
	_card_pressed.set_corner_radius_all(3)
	_card_pressed.set_content_margin_all(12)

	parts_grid.columns = 4
	search_edit.text_changed.connect(_filter)
	clear_button.pressed.connect(_on_clear_desk)
	_build()
	_filter("")
	var v := OS.get_environment("GODOT_VERIFY")
	if v == "parts":
		call_deferred("_verify")

func _build() -> void:
	for entry in PartsDB.PARTS:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(210, 96)
		btn.add_theme_stylebox_override("normal", _card_style)
		btn.add_theme_stylebox_override("hover", _card_hover)
		btn.add_theme_stylebox_override("pressed", _card_pressed)
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var vb := VBoxContainer.new()
		vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
		vb.add_theme_constant_override("separation", 4)
		var name_l := Label.new()
		name_l.text = entry["name"]
		name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_l.add_theme_font_size_override("font_size", 16)
		# две строки максимум: высота фиксирована, лишнее не вылезает за карточку
		name_l.custom_minimum_size = Vector2(0, 44)
		name_l.clip_contents = true
		name_l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		var cat_l := Label.new()
		cat_l.text = entry["category"]
		cat_l.add_theme_font_size_override("font_size", 12)
		cat_l.modulate = Color(0.78, 0.7, 0.56)
		vb.add_child(name_l)
		vb.add_child(cat_l)
		var cnt_l := Label.new()
		cnt_l.add_theme_font_size_override("font_size", 13)
		cnt_l.add_theme_color_override("font_color", Color(0.72, 0.66, 0.55, 1))
		cnt_l.visible = false
		vb.add_child(cnt_l)
		_count_labels[entry["id"]] = cnt_l
		btn.add_child(vb)
		btn.pressed.connect(_on_card.bind(entry["id"]))
		parts_grid.add_child(btn)
		_cards.append([btn, entry])

# counts: catalog_id -> количество на столе (показываем только > 0)
func update_counts(counts: Dictionary) -> void:
	for entry in PartsDB.PARTS:
		var pid: String = entry["id"]
		if not _count_labels.has(pid):
			continue
		var n: int = counts.get(pid, 0)
		var lbl: Label = _count_labels[pid]
		lbl.text = "на столе: %d" % n
		lbl.visible = n > 0

func _on_card(part_id: String) -> void:
	part_selected.emit(part_id)

func _on_clear_desk() -> void:
	clear_desk_pressed.emit()

func _filter(q: String) -> void:
	var query := q.strip_edges().to_lower()
	var shown := 0
	for card in _cards:
		var entry: Dictionary = card[1]
		var hay := String(entry["name"]).to_lower() + " " + String(entry["category"]).to_lower()
		var vis := query == "" or hay.contains(query)
		card[0].visible = vis
		if vis:
			shown += 1
	count_label.text = "%d / %d" % [shown, PartsDB.PARTS.size()]

func _verify() -> void:
	var all_shown := _shown_count()
	_filter("резистор")
	print("VERIFY-OK parts total=%d all_shown=%d by_query=%d" % [
		PartsDB.PARTS.size(), all_shown, _shown_count()])
	get_tree().quit()

func _shown_count() -> int:
	var n := 0
	for card in _cards:
		if card[0].visible:
			n += 1
	return n
