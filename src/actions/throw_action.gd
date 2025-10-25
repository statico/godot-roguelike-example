class_name ThrowAction
extends ActorAction

var selections: Array[ItemSelection]
var target_pos: Vector2i


func _init(p_actor: Monster, p_selections: Array[ItemSelection], p_target_pos: Vector2i) -> void:
	super(p_actor)
	selections = p_selections
	target_pos = p_target_pos


func _to_string() -> String:
	return "ThrowAction(selections: %s)" % selections


func _execute(map: Map, result: ActionResult) -> bool:
	if not super(map, result):
		return false

	# Verify that the selection contains a single item with a quantity of 1 or more.
	if selections.size() != 1:
		Log.e("Invalid number of selections: %s" % selections.size())
		return false
	if selections[0].quantity <= 0:
		Log.e("Invalid quantity: %s" % selections[0].quantity)
		return false
	var item: Item = selections[0].item

	# Split off one item if we're throwing from a stack
	var thrown_item: Item
	if item.quantity > 1:
		thrown_item = item.split(1)
	else:
		thrown_item = item
		World.player.remove_item(item)  # Remove the entire item if it's the last one

	# Get the actor's position
	var current_pos := map.find_monster_position(actor)
	if not current_pos:
		Log.e("Actor not found in map: %s" % actor)
		return false

	# If the actor is paralyzed, don't throw
	if actor.has_status_effect(StatusEffect.Type.PARALYZED):
		if actor == World.player:
			result.message = "You are paralyzed!"
			result.message_level = LogMessages.Level.TERRIBLE
		else:
			result.message = "%s tries to throw something but is paralyzed!" % actor.name
			result.message_level = LogMessages.Level.BAD
		return true

	# Resolve the ranged attack
	var throw_result := Combat.resolve_thrown_item(map, actor, target_pos, thrown_item)
	if not throw_result:
		Log.e("No throw result for throw action")
		return false

	# Create a thrown item effect
	var effect := ThrownItemEffect.new(actor, current_pos, throw_result.end_pos, thrown_item)
	result.add_effect(effect)

	# Mark the action as exercise for nutrition processing
	result.extra_nutrition_consumed = 1

	# If this is a grenade with delayed activation, add it to the map
	if thrown_item.type == Item.Type.GRENADE and thrown_item.turns_to_activate > 0:
		thrown_item.turns_to_activate += 1  # HACK: because update_area_effects() is called after the throw
		thrown_item.is_armed = true
		map.add_item(throw_result.end_pos, thrown_item)

	return true
