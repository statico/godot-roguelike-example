class_name HitEffect
extends ActionEffect

var direction: Vector2
var source: Monster
var took_damage: bool = false


func _init(
	p_target: Monster,
	p_direction: Vector2,
	p_location: Vector2i,
	p_source: Monster,
	p_took_damage: bool = false
) -> void:
	super(p_target, p_location)
	direction = p_direction
	source = p_source
	took_damage = p_took_damage


func _to_string() -> String:
	return (
		"HitEffect(target: %s, direction: %s, source: %s, took_damage: %s)"
		% [target, direction, source, took_damage]
	)


func involves_player() -> bool:
	return source == World.player or target == World.player
