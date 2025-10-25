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

	# Resolve combat
	var combat_result := Combat.resolve_melee_attack(actor, target_monster)

	# Apply damage (TODO: Shield absorption system)
	target_monster.hp = max(0, target_monster.hp - combat_result.damage)

	# Set message
	result.message = Combat.format_melee_attack_message(actor, target_monster, combat_result)
	if target_monster == World.player:
		result.message_level = LogMessages.Level.BAD

	# Add attack effect for actor
	result.add_effect(AttackEffect.new(actor, Vector2(direction) * -1, target_monster, current_pos))

	# Mark the action as exercise for nutrition processing
	result.extra_nutrition_consumed = 2

	# Handle death
	if combat_result.killed:
		target_monster.is_dead = true

		# Only remove monster if it's not the player
		if target_monster != World.player:
			target_monster.drop_everything()
			map.find_and_remove_monster(target_monster)
			result.message_level = LogMessages.Level.GOOD
		# Add death effect
		var death_effect := DeathEffect.new(target_monster, target_pos, actor == World.player)
		result.add_effect(death_effect)

	return true


func _to_string() -> String:
	return "MeleeAction(actor: %s, direction: %s)" % [actor, direction]
