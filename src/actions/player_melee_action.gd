class_name PlayerMeleeAction
extends MeleeAction


func _init(dir: Vector2i) -> void:
	super(World.player, dir)


func _to_string() -> String:
	return "PlayerMeleeAction(direction: %s)" % direction
