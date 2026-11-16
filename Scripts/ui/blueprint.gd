extends Control
## Чертёж задания: открывается при зуме на чертежи (papers).
## Монтажная схема — монтажка уровня 1 из Fritzing (Textures/blueprint_l1.png);
## статус сборки через provider (Callable, возвращает bool — собрал ли цепь).

signal closed

@onready var status_label: Label = %StatusLabel
@onready var schem: TextureRect = %Schematic

var provider: Callable = Callable()

func _ready() -> void:
	visible = false
	%CloseButton.pressed.connect(_on_close)
	schem.texture = load("res://Textures/blueprint_l1.png")

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
