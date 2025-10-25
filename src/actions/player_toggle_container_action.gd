class_name PlayerToggleContainerAction
extends ToggleContainerAction


func _init(p_container: Item) -> void:
	super(World.player, p_container)


func _execute(map: Map, result: ActionResult) -> bool:
	var success := super(map, result)
	if success:
		# Override the message to be in second person for the player
		result.message = (
			"You %s %s."
			% ["opened" if container.is_open else "closed", container.get_name(Item.NameFormat.THE)]
		)
	return success


func _to_string() -> String:
	return "PlayerToggleContainerAction(container: %s)" % [container]
