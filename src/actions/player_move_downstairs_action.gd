class_name PlayerMoveDownstairsAction
extends ActorAction


func _init() -> void:
	super(World.player)


func _execute(map: Map, result: ActionResult) -> bool:
	if not super(map, result):
		return false

	var current_pos := map.find_monster_position(actor)
	if not current_pos:
		return false

	# Check if we're on stairs
	var obstacle := map.get_obstacle(current_pos)
	if not obstacle or obstacle.type != Obstacle.Type.STAIRS_DOWN:
		result.message = "There are no stairs down here."
		return false

	# Handle the level transition
	World.handle_level_transition(obstacle.destination_level, obstacle.type)
	return true


func _to_string() -> String:
	return "PlayerMoveDownstairsAction()"
