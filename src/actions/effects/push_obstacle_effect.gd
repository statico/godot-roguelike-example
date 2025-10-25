class_name PushObstacleEffect
extends ActionEffect

var from: Vector2i
var to: Vector2i


func _init(p_from: Vector2i, p_to: Vector2i, p_location: Vector2i) -> void:
	super(null, p_location)  # No target monster for obstacles
	from = p_from
	to = p_to


func involves_player() -> bool:
	return false  # Obstacles never directly involve the player


func _to_string() -> String:
	return "PushObstacleEffect(from: %s, to: %s)" % [from, to]
