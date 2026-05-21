class_name AttackMoveAction
extends ActorAction

var direction: Vector2i


func _init(p_actor: Monster, dir: Vector2i) -> void:
	super(p_actor)  # action_cost = ACTION by default
	direction = dir
	# 적이 없으면 이동 행동 → MOVE 예산 소모
	if World.current_map:
		var cur := World.current_map.find_monster_position(p_actor)
		if cur != Utils.INVALID_POS:
			var target := World.current_map.get_monster(cur + dir)
			if not (target and p_actor.is_hostile_to(target)):
				action_cost = ActionBudget.Cost.MOVE


func _execute(map: Map, result: ActionResult) -> bool:
	if not super(map, result):
		return false

	var current_pos := map.find_monster_position(actor)
	if not current_pos:
		return false

	if actor.has_status_effect(StatusEffect.Type.CONFUSED):
		direction = Utils.ALL_DIRECTIONS.pick_random()

	if actor.has_status_effect(StatusEffect.Type.PARALYZED):
		if actor == World.player:
			result.message = "You are paralyzed!"
			result.message_level = LogMessages.Level.TERRIBLE
		else:
			result.message = "%s tries to move but is paralyzed!" % actor.name

	var new_pos := current_pos + direction

	# First try melee attack if there's a monster
	var target_monster := map.get_monster(new_pos)
	if target_monster:
		if actor.is_hostile_to(target_monster):
			var melee := MeleeAction.new(actor, direction)
			return melee._execute(map, result)
		else:
			Log.i("[Combat Patch] Swapping places between friendly units: %s at %s and %s at %s" % [
				actor.name, current_pos, target_monster.name, new_pos
			])
			map.cells[current_pos.x][current_pos.y].monster = target_monster
			map.cells[new_pos.x][new_pos.y].monster = actor
			
			result.add_effect(MoveEffect.new(actor, new_pos, current_pos))
			result.add_effect(MoveEffect.new(target_monster, current_pos, new_pos))
			
			if actor == World.player:
				result.message = "You swap places with %s." % target_monster.name
			elif target_monster == World.player:
				result.message = "%s swaps places with you." % actor.name
			else:
				result.message = "%s swaps places with %s." % [actor.name, target_monster.name]
			
			result.message_level = LogMessages.Level.NORMAL
			result.extra_nutrition_consumed = 1
			# [EventBus] 아군 위치 교환 이벤트 발송
			EventBus.allies_swapped.emit(actor, target_monster)
			return true

	# Otherwise try to move
	var move := MoveAction.new(actor, direction)
	return move._execute(map, result)


func _to_string() -> String:
	return "AttackMoveAction(actor: %s, direction: %s)" % [actor, direction]
