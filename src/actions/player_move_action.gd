class_name PlayerMoveAction
extends MoveAction


func _init(dir: Vector2i) -> void:
	super(World.player, dir)


func _to_string() -> String:
	return "PlayerMoveAction(direction: %s)" % direction
