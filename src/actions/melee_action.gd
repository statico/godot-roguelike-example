class_name MeleeAction
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

	if actor.has_status_effect(StatusEffect.Type.PARALYZED):
		if actor == World.player:
			result.message = "You are paralyzed and cannot attack!"
			result.message_level = LogMessages.Level.TERRIBLE
		else:
			result.message = "%s tries to attack but is paralyzed!" % actor.name
			result.message_level = LogMessages.Level.BAD
		return true

	if actor.has_status_effect(StatusEffect.Type.CONFUSED):
		direction = Utils.ALL_DIRECTIONS.pick_random()

	var target_pos := current_pos + direction

	# Handle monster collision
	var target_monster := map.get_monster(target_pos)
	if not target_monster:
		return false

	if not actor.is_hostile_to(target_monster):
		Log.w("[Combat Patch] MeleeAction prevented friendly fire attack from %s to %s" % [
			actor.name, target_monster.name
		])
		return false

	# Extra Attack: 파이터 5레벨부터 같은 ACTION으로 N번 공격
	var attacks := actor.class_comp.get_extra_attacks()
	var last_msg := ""

	for _i in attacks:
		if target_monster.is_dead:
			break

		var combat_result := Combat.resolve_melee_attack(actor, target_monster)

		target_monster.hp = max(0, target_monster.hp - combat_result.damage)

		EventBus.melee_attack_made.emit(actor, target_monster)
		if combat_result.damage > 0:
			EventBus.monster_damaged.emit(actor, target_monster, combat_result.damage, combat_result.damage_type)

		last_msg = Combat.format_melee_attack_message(actor, target_monster, combat_result)

		result.add_effect(AttackEffect.new(actor, Vector2(direction) * -1, target_monster, current_pos))
		result.add_effect(HitEffect.new(
			target_monster, Vector2(direction), current_pos, actor, combat_result.damage > 0
		))

		if combat_result.killed:
			target_monster.is_dead = true
			EventBus.monster_killed.emit(actor, target_monster)
			if target_monster != World.player:
				target_monster.drop_everything()
				map.find_and_remove_monster(target_monster)
				result.message_level = LogMessages.Level.GOOD
			result.add_effect(DeathEffect.new(target_monster, target_pos, actor == World.player))
			break

	result.message = last_msg
	if target_monster == World.player:
		result.message_level = LogMessages.Level.BAD

	result.extra_nutrition_consumed = 2
	return true


func _to_string() -> String:
	return "MeleeAction(actor: %s, direction: %s)" % [actor, direction]
