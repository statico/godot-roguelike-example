extends Control

# Uncomment this to test the game immediately after running
# func _ready() -> void:
# 	call_deferred("_on_play_button_pressed")


func _on_play_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/game/game.tscn")


func _on_quit_button_pressed() -> void:
	get_tree().quit()
