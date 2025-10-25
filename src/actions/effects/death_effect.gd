class_name DeathEffect
extends ActionEffect

var caused_by_player: bool = false


func _init(p_target: Monster, p_location: Vector2i, p_caused_by_player: bool = false) -> void:
	super(p_target, p_location)
	caused_by_player = p_caused_by_player


func _to_string() -> String:
	return (
		"DeathEffect(target: %s, caused_by_player: %s, location: %s)"
		% [
			target,
			caused_by_player,
			location,
		]
	)


func involves_player() -> bool:
	return target == World.player or caused_by_player
