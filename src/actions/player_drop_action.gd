class_name PlayerDropAction
extends DropAction


func _init(p_selections: Array[ItemSelection]) -> void:
	super(World.player, p_selections)


func _execute(map: Map, result: ActionResult) -> bool:
	var success := super(map, result)
	if success:
		# Override the message to be in second person for the player
		result.message = "Dropped %s" % result.message.split("dropped")[1].strip_edges()
	return success


func _to_string() -> String:
	return "PlayerDropAction(%s)" % [selections]
