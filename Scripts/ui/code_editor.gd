extends Control
## Редактор кода Arduino: открывается при зуме на ПК.
## Код исполняет arduino_vm.gd; pin_changed -> bench.set_arduino_pin.
## Headless-верификация: GODOT_VERIFY=code (запуск сцены напрямую).

const ArduinoVM = preload("res://Scripts/sim/arduino_vm.gd")

signal closed

@onready var code_edit: TextEdit = %CodeEdit
@onready var out_label: Label = %OutLabel
@onready var upload_btn: Button = %UploadButton
@onready var close_btn: Button = %CloseButton

var _vm: Node = null
# проверка «есть ли плата на столе» (подписывается извне, из interact.gd)
var board_check: Callable = Callable()

const DEFAULT_CODE := """void setup() {
  pinMode(13, OUTPUT);
}

void loop() {
  digitalWrite(13, HIGH);
  delay(500);
  digitalWrite(13, LOW);
  delay(500);
}
"""

func _ready() -> void:
	_vm = ArduinoVM.new()
	add_child(_vm)
	_vm.pin_changed.connect(_on_pin_changed)
	visible = false
	_upload_style(upload_btn, true)
	_upload_style(close_btn, false)
	upload_btn.pressed.connect(_on_upload)
	close_btn.pressed.connect(_on_close)
	code_edit.text = DEFAULT_CODE
	out_label.text = ""
	var v := OS.get_environment("GODOT_VERIFY")
	if v == "code":
		call_deferred("_verify")

func set_vm_active(on: bool) -> void:
	if on:
		return   # VM живёт, пока редактор открыт; закрытие останавливает
	_vm.stop()

func _on_upload() -> void:
	if board_check.is_valid() and not board_check.call():
		out_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.25, 1))
		out_label.text = "На столе нет платы — возьми ATmega328P из каталога (TAB / зум на шкаф)"
		return
	out_label.add_theme_color_override("font_color", Color(0.72, 0.66, 0.55, 1))
	var err: String = _vm.load_and_run(code_edit.text)
	if err == "":
		out_label.text = "Скомпилировано, загрузка на плату выполнена"
	else:
		out_label.add_theme_color_override("font_color", Color(0.85, 0.45, 0.3, 1))
		out_label.text = "Ошибка: " + err

func _on_close() -> void:
	# закрытие окна редактора не останавливает скетч: прошивка продолжает
	# исполняться на плате, иначе после закрытия редактора LED гаснет
	# и результат загрузки невозможно увидеть. Остановка — при новой
	# загрузке (load_and_run) или смене сцены.
	out_label.text = ""
	visible = false
	closed.emit()

# state: high -> true; вызывается из VM
func _on_pin_changed(pin: int, high: bool) -> void:
	out_label.add_theme_color_override("font_color", Color(0.72, 0.66, 0.55, 1))
	out_label.text = "pin %d: %s" % [pin, "HIGH" if high else "LOW"]

# внешний обработчик: подписывается interact.gd
func connect_pin_handler(cb: Callable) -> void:
	_vm.pin_changed.connect(cb)

func _verify() -> void:
	await get_tree().process_frame
	print("VERIFY-OK code editor=%s code_len=%d" % [visible, code_edit.text.length()])
	get_tree().quit()

func _upload_style(btn: Button, primary: bool) -> void:
	for state in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.13, 0.11, 0.09, 1) if state == "normal" \
			else (Color(0.2, 0.17, 0.13, 1) if state == "hover" else Color(0.26, 0.21, 0.15, 1))
		sb.set_border_width_all(1)
		sb.border_color = Color(1, 0.82, 0.58, 0.5 if primary and state == "normal" \
			else (0.35 if state == "hover" else (0.7 if state == "pressed" else 0.14)))
		sb.set_corner_radius_all(3)
		sb.set_content_margin_all(8)
		btn.add_theme_stylebox_override(state, sb)
	btn.add_theme_color_override("font_color", Color(1, 0.92, 0.55, 1) if primary \
		else Color(0.75, 0.7, 0.62, 1))
	btn.add_theme_color_override("font_hover_color", Color(1, 0.92, 0.55, 1))
	btn.add_theme_font_size_override("font_size", 16)
	btn.custom_minimum_size = Vector2(130, 36)
