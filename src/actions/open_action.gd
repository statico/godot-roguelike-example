class_name OpenAction
extends ActorAction

var direction: Vector2i


func _init(p_actor: Monster, dir: Vector2i) -> void:
	super(p_actor)
	direction = dir


func _execute(map: Map, result: ActionResult) -> bool:
	if not super(map, result):
		return false

	var current_pos := map.find_monster_position(actor)
	if not current_pos:
		return false

	var target_pos := current_pos + direction

	# Check if there's a door at the target position
	var obstacle := map.get_obstacle(target_pos)
	if not obstacle:
		result.message = "There is nothing there to open."
		return false
	elif obstacle.type == Obstacle.Type.DOOR_OPEN:
		result.message = "That door is already open."
		return false
	elif obstacle.type != Obstacle.Type.DOOR_CLOSED:
		result.message = "There is no door there to open."
		return false

	# Open the door
	obstacle.type = Obstacle.Type.DOOR_OPEN
	result.message = "%s opened the door." % actor
	return true


func _to_string() -> String:
	return "OpenAction(actor: %s, direction: %s)" % [actor, direction]
