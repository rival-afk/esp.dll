extends Control
## Чертёж задания: открывается при зуме на бумаги (papers).
## Рисует кодом замкнутый контур «Arduino Uno (пин 13) → резистор 220 Ом → LED → GND».
## Статус сборки через provider (Callable, возвращает bool — собрал ли цепь).

signal closed

@onready var status_label: Label = %StatusLabel
@onready var schem: Control = %Schematic

var provider: Callable = Callable()

func _ready() -> void:
	visible = false
	%CloseButton.pressed.connect(_on_close)
	schem.draw.connect(_draw_schematic)

func _on_close() -> void:
	visible = false
	closed.emit()

func _process(_delta: float) -> void:
	if not visible:
		return
	var done: bool = provider.is_valid() and provider.call()
	if done:
		status_label.text = "Статус: задание выполнено"
		status_label.add_theme_color_override("font_color", Color(0.55, 0.85, 0.5, 1))
	else:
		status_label.text = "Статус: цепь не собрана"
		status_label.add_theme_color_override("font_color", Color(0.78, 0.7, 0.56, 1))
	schem.queue_redraw()

func _draw_schematic() -> void:
	var amber := Color(1, 0.82, 0.58, 1)
	var wire := 2.5
	var f := ThemeDB.fallback_font
	var dim := Color(0.75, 0.68, 0.56, 1)
	var board_col := Color(0.13, 0.55, 0.6, 1)

	# --- корпус Arduino Uno ---
	var box := Rect2(12.0, 30.0, 88.0, 130.0)
	schem.draw_rect(box, board_col)
	schem.draw_rect(box, amber, false, wire)
	# «USB»-разъём слева
	schem.draw_rect(Rect2(2.0, 52.0, 10.0, 24.0), dim, true)
	schem.draw_string(f, Vector2(20.0, 56.0), "Arduino", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.98, 0.93, 0.78, 1))
	schem.draw_string(f, Vector2(20.0, 74.0), "Uno", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, dim)
	schem.draw_string(f, Vector2(20.0, 90.0), "13", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 1.0, 1.0, 1))
	schem.draw_string(f, Vector2(20.0, 150.0), "GND", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 1.0, 1.0, 1))

	# --- замкнутый контур: 13 -> резистор -> LED -> GND ---
	var y_top := 84.0
	var y_bot := 142.0
	var x_out := 100.0   # правая грань платы (пины 13/GND)
	var x_led := 380.0
	schem.draw_line(Vector2(x_out, y_top), Vector2(160.0, y_top), amber, wire)
	# резистор — зигзаг 220 Ом
	var zig := PackedVector2Array([
		Vector2(160.0, y_top), Vector2(170.0, y_top - 11.0), Vector2(183.0, y_top + 11.0),
		Vector2(196.0, y_top - 11.0), Vector2(209.0, y_top + 11.0), Vector2(222.0, y_top - 11.0),
		Vector2(234.0, y_top),
	])
	for i in zig.size() - 1:
		schem.draw_line(zig[i], zig[i + 1], amber, wire)
	schem.draw_line(Vector2(234.0, y_top), Vector2(x_led, y_top), amber, wire)
	# LED вертикально: треугольник + катод-черта, ток сверху вниз
	schem.draw_line(Vector2(x_led, y_top), Vector2(x_led, y_top + 12.0), amber, wire)
	var tri_top := y_top + 12.0
	var tri_apex := y_top + 38.0
	schem.draw_polyline(PackedVector2Array([
		Vector2(x_led - 13.0, tri_top), Vector2(x_led + 13.0, tri_top), Vector2(x_led, tri_apex),
	]), amber, wire)
	schem.draw_line(Vector2(x_led - 14.0, tri_apex + 2.0), Vector2(x_led + 14.0, tri_apex + 2.0), amber, wire)
	schem.draw_line(Vector2(x_led, tri_apex + 2.0), Vector2(x_led, y_bot), amber, wire)
	# нижний провод обратно на GND платы
	schem.draw_line(Vector2(x_led, y_bot), Vector2(x_out, y_bot), amber, wire)
	schem.draw_circle(Vector2(x_out, y_top), 3.0, amber)
	schem.draw_circle(Vector2(x_out, y_bot), 3.0, amber)

	# --- подписи ---
	schem.draw_string(f, Vector2(197.0, y_top - 20.0), "Резистор 220 Ом", HORIZONTAL_ALIGNMENT_CENTER, -1, 13, dim)
	schem.draw_string(f, Vector2(300.0, tri_top + 20.0), "LED", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, dim)
	schem.draw_string(f, Vector2(16.0, 178.0), "пин 13 (D13) ── GND", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, dim)
