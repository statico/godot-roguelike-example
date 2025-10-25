class_name Reticle
extends Node2D

var pulse := false
var _time := 0.0


func _ready() -> void:
	visible = false


func _process(delta: float) -> void:
	if pulse:
		_time += delta * 8.0  # Controls pulse speed
		scale = Vector2.ONE * (1.1 + 0.1 * sin(_time))  # Scales between 1.0 and 1.21
	else:
		scale = Vector2.ONE
