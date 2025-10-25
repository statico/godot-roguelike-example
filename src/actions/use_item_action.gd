class_name UseItemAction
extends ActorAction

var item: Item


func _init(p_actor: Monster, p_item: Item) -> void:
	super(p_actor)
	item = p_item


## Returns true if the item can be used. Copy the logic to here from _execute() to allow the UI to check if the item can be used.
static func can_use_item(p_item: Item) -> bool:
	return p_item.stim_level > 0 or p_item.nutrition > 0 or p_item.hp > 0 or p_item.is_container()


func _execute(map: Map, result: ActionResult) -> bool:
	if not super(map, result):
		return false

	# Check if actor has the item
	if not actor.has_item(item):
		result.message = "You don't have that item."
		return false

	# Handle containers
	if item.is_container():
		var toggle_action := ToggleContainerAction.new(actor, item)
		return toggle_action._execute(map, result)

	# Handle stim effects
	if item.stim_level > 0:
		actor.apply_status_effect(StatusEffect.Type.STIM, item.stim_turns, item.stim_level)
		result.message += " You feel energized!"
		result.message_level = LogMessages.Level.GOOD

		actor.hp = min(actor.hp + item.stim_level * 10, actor.max_hp)

		actor.remove_item(item)
		return true

	# Handle nutrition
	if item.nutrition > 0:
		result.message = "You consume %s." % item.get_name(Item.NameFormat.AN, false)

		if item.delicious:
			result.message += " It is delicious!"
		elif item.palatable and Dice.chance(0.5):
			result.message += " It tastes acceptable."
		elif item.gross:
			result.message += " Gross!"

		var nutrition_result := actor.nutrition.increase(item.nutrition)
		if nutrition_result.message:
			result.message += " " + nutrition_result.message
			result.message_level = (
				LogMessages.Level.BAD if nutrition_result.died else LogMessages.Level.GOOD
			)
		if nutrition_result.died:
			actor.is_dead = true
			result.add_effect(DeathEffect.new(actor, map.find_monster_position(actor), true))
			return true

		actor.remove_item(item)
		return true

	# Handle healing
	if item.hp > 0:
		var old_hp := actor.hp
		actor.hp = min(actor.hp + item.hp, actor.max_hp)
		var healed := actor.hp - old_hp
		result.message = "You apply %s." % item.get_name(Item.NameFormat.THE)
		if healed > 0:
			result.message += " You feel better."
			result.message_level = LogMessages.Level.GOOD
		else:
			result.message += " Nothing happens."

		actor.remove_item(item)
		return true

	# Otherwise, not sure what to do
	result.message = "You're not sure how to use that."
	return false


func _to_string() -> String:
	return "UseItemAction(actor: %s, item: %s)" % [actor, item]
