class_name MoveAction
extends ActorAction

var direction: Vector2i


func _init(p_actor: Monster, dir: Vector2i) -> void:
	super(p_actor)
	direction = dir


func _execute(map: Map, result: ActionResult) -> bool:
	if not super(map, result):
		return false

	var current_pos: Vector2i = map.find_monster_position(actor)
	if not current_pos:
		return false

	if actor.has_status_effect(StatusEffect.Type.PARALYZED):
		if actor == World.player:
			result.message = "You are paralyzed and cannot move!"
			result.message_level = LogMessages.Level.TERRIBLE
		else:
			result.message = "%s tries to move but is paralyzed!" % actor.name
			result.message_level = LogMessages.Level.BAD
		return true

	if actor.has_status_effect(StatusEffect.Type.CONFUSED):
		direction = Utils.ALL_DIRECTIONS.pick_random()

	var new_pos: Vector2i = current_pos + direction

	# Check if target position is walkable
	if not map.get_cell(new_pos).is_walkable():
		# Check if there's a pushable obstacle
		var target_cell: MapCell = map.get_cell(new_pos)
		if target_cell.obstacle and target_cell.obstacle.is_pushable():
			if _try_push_obstacle(map, current_pos, direction, result):
				# The push was successful, but the actor stays in place
				return true
		return false

	# Check for monster collision - can't move into space with monster
	var target_monster: Monster = map.get_monster(new_pos)
	if target_monster:
		return false

	# Move actor
	map.find_and_remove_monster(actor)
	map.cells[new_pos.x][new_pos.y].monster = actor
	result.add_effect(MoveEffect.new(actor, new_pos, current_pos))

	# Mark the action as exercise for nutrition processing
	result.extra_nutrition_consumed = 1

	# Only show item notifications for the player
	if actor == World.player:
		var items: Array[Item] = map.get_items(new_pos)
		if not items.is_empty():
			if items.size() == 1:
				result.message = "There is %s here." % items[0].name
			elif items.size() <= 5:
				result.message = "There are some items here."
			else:
				result.message = "There are many items here."

		# Add staircase notifications
		var obstacle := map.get_obstacle(new_pos)
		if obstacle:
			match obstacle.type:
				Obstacle.Type.STAIRS_UP:
					result.message = "There is a staircase up here."
				Obstacle.Type.STAIRS_DOWN:
					result.message = "There is a staircase down here."
	return true


func _try_push_obstacle(
	map: Map, pos: Vector2i, p_direction: Vector2i, result: ActionResult
) -> bool:
	# Try to push the obstacle
	var target_pos := Vector2i(pos.x + p_direction.x, pos.y + p_direction.y)
	if map.push_obstacle(target_pos, p_direction):
		# Add push effects
		result.add_effect(PushActorEffect.new(actor, p_direction, pos))
		result.add_effect(PushObstacleEffect.new(target_pos, target_pos + p_direction, pos))
		return true
	return false


func _to_string() -> String:
	return "MoveAction(actor: %s, direction: %s)" % [actor, direction]
