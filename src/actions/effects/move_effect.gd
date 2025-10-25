class_name MoveEffect
extends ActionEffect

var to: Vector2i
var from: Vector2i


func _init(p_target: Monster, p_to: Vector2i, p_from: Vector2i) -> void:
	super(p_target, p_from)
	to = p_to
	from = p_from


func _to_string() -> String:
	return "MoveEffect(target: %s, to: %s, from: %s)" % [target, to, from]
