class_name PushActorEffect
extends ActionEffect

var direction: Vector2i


func _init(p_target: Monster, p_direction: Vector2i, p_location: Vector2i) -> void:
	super(p_target, p_location)
	direction = p_direction


func _to_string() -> String:
	return "PushActorEffect(target: %s, direction: %s)" % [target, direction]
