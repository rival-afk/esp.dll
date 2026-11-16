extends Control
## Чертёж задания: открывается при зуме на чертежи (papers).
## Рисует схему кодом (battery, резистор, LED) и следит за статусом сборки
## через provider (Callable, возвращает bool — собрал ли игрок цепь).

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
	var w := 2.0
	# контур цепи: БП (слева) -> резистор (сверху) -> LED (справа) -> назад
	var pts := PackedVector2Array([
		Vector2(40, 120), Vector2(70, 120), Vector2(70, 50),
		Vector2(120, 50), Vector2(210, 50), Vector2(260, 50),
		Vector2(260, 70),
	])
	for i in pts.size() - 1:
		schem.draw_line(pts[i], pts[i + 1], amber, w)
	# батарейка: длинная и короткая пластины
	schem.draw_line(Vector2(30, 112), Vector2(30, 128), amber, w)
	schem.draw_line(Vector2(40, 117), Vector2(40, 123), amber, w)
	schem.draw_line(Vector2(260, 110), Vector2(260, 130), amber, w)
	# резистор — зигзаг
	var zig := PackedVector2Array([
		Vector2(120, 50), Vector2(130, 40), Vector2(145, 60),
		Vector2(160, 40), Vector2(175, 60), Vector2(190, 40),
		Vector2(200, 50), Vector2(210, 50),
	])
	for i in zig.size() - 1:
		schem.draw_line(zig[i], zig[i + 1], amber, w)
	# светодиод — треугольник и черта
	schem.draw_polyline(PackedVector2Array([
		Vector2(248, 78), Vector2(248, 102), Vector2(270, 90),
	]), amber, w)
	schem.draw_line(Vector2(270, 76), Vector2(270, 104), amber, w)
	# подписи
	var f := ThemeDB.fallback_font
	schem.draw_string(f, Vector2(12, 150), "5 В", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.72, 0.66, 0.55, 1))
	schem.draw_string(f, Vector2(140, 32), "220 Ом", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.72, 0.66, 0.55, 1))
	schem.draw_string(f, Vector2(246, 70), "LED", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.72, 0.66, 0.55, 1))
