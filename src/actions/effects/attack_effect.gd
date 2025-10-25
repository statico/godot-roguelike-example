class_name AttackEffect
extends ActionEffect

var direction: Vector2
var subject: Monster


func _init(
	p_target: Monster, p_direction: Vector2, p_subject: Monster, p_location: Vector2i
) -> void:
	super(p_target, p_location)
	direction = p_direction
	subject = p_subject


func involves_player() -> bool:
	return super() or subject == World.player


func _to_string() -> String:
	return "AttackEffect(target: %s, direction: %s, subject: %s)" % [target, direction, subject]
