@tool
extends SceneTree
# УСТАРЕЛ: game.tscn теперь поддерживается вручную (в редакторе Godot).
# Старый генератор сцены отключён, чтобы случайно не перезаписать текущую
# сцену (зоны, подсветки, PartsList). Калибровка — в interact.gd/game.tscn,
# пробник координат модели — probe_nodes.gd.

func _init() -> void:
	print("build_scene.gd устарел: game.tscn редактируется вручную. Сцена не изменена.")
	quit()
