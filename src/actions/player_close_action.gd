class_name PlayerCloseAction
extends CloseAction


func _init(dir: Vector2i) -> void:
	super(World.player, dir)


func _execute(map: Map, result: ActionResult) -> bool:
	var success := super(map, result)
	if success:
		# Override the message to be in second person for the player
		result.message = "You close the door."
	return success


func _to_string() -> String:
	return "PlayerCloseAction(direction: %s)" % direction
