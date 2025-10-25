class_name PlayerRestAction
extends RestAction


func _init() -> void:
	super(World.player)


func _execute(map: Map, result: ActionResult) -> bool:
	var success := super(map, result)
	if success:
		# Override the message to be in second person for the player
		result.message = "You rest for a moment..."
	return success


func _to_string() -> String:
	return "PlayerRestAction()"
