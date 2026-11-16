extends Control
## Главное меню: Играть -> сцена стола, Выход.
## Headless-верификация: GODOT_VERIFY=menu | menu_play

const GAME_SCENE := "res://game.tscn"

@onready var play_button: Button = %PlayButton
@onready var quit_button: Button = %QuitButton

func _ready() -> void:
	play_button.pressed.connect(_on_play)
	quit_button.pressed.connect(_on_quit)
	play_button.grab_focus()
	var v := OS.get_environment("GODOT_VERIFY")
	if v != "":
		call_deferred("_verify", v)
	if OS.get_environment("GODOT_SHOT") != "":
		call_deferred("_shot")

func _on_play() -> void:
	var tree := get_tree()
	var err := tree.change_scene_to_file(GAME_SCENE)
	if OS.get_environment("GODOT_VERIFY") == "menu_play":
		print("VERIFY-OK menu_play err=", err)
		tree.quit()

func _on_quit() -> void:
	get_tree().quit()

func _verify(v: String) -> void:
	await get_tree().process_frame
	if v == "menu":
		var ok := play_button.text == "Играть" and quit_button.text == "Выход" \
			and play_button.has_focus()
		print("VERIFY-OK menu buttons=%s focused=%s" % [ok, play_button.has_focus()])
		get_tree().quit()
	elif v == "menu_play":
		play_button.pressed.emit()

func _shot() -> void:
	for i in 30:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://Screenshots/auto_menu.png"))
	print("SHOTS-DONE")
	get_tree().quit()
