class_name PlayerPickupAction
extends PickupAction


func _init(p_selections: Array[ItemSelection] = []) -> void:
	super(World.player, p_selections)


func _execute(map: Map, result: ActionResult) -> bool:
	var success := super(map, result)
	if success:
		# Override the message to be in second person for the player
		if "x" in result.message:  # Check if it's a quantity message
			result.message = result.message.split("picked up")[1].strip_edges()
		else:
			result.message = "Picked up %s" % result.message.split("picked up")[1].strip_edges()
	return success


func _to_string() -> String:
	return "PlayerPickupAction(%s)" % [selections]
