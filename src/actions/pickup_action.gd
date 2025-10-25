class_name PickupAction
extends ActorAction

var selections: Array[ItemSelection]


func _init(p_actor: Monster, p_selections: Array[ItemSelection] = []) -> void:
	super(p_actor)
	selections = p_selections


func _execute(map: Map, result: ActionResult) -> bool:
	if not super(map, result):
		return false

	Log.d("[DragDrop] Executing PickupAction")

	# Get actor's current position
	var current_pos := map.find_monster_position(actor)
	if not current_pos:
		return false

	# If no selections provided, pick up top item
	if selections.is_empty():
		var item := map.get_top_item(current_pos)
		if not item:
			Log.d("[DragDrop] No items to pick up at position: %s" % current_pos)
			result.message = "Nothing to pick up here."
			return false
		Log.d("[DragDrop] Auto-selecting top item: %s" % item.get_name(Item.NameFormat.THE))
		selections = [ItemSelection.new(item)]

	var success := false
	var picked_up_items := []

	# Process each selection
	for selection in selections:
		var item := selection.item
		var quantity := selection.quantity

		Log.d(
			(
				"[DragDrop] Processing pickup selection: %s (quantity: %d)"
				% [item.get_name(Item.NameFormat.THE), quantity]
			)
		)

		# Verify item exists at location
		if not map.get_items(current_pos).has(item):
			Log.d("[DragDrop] Item not found at location: %s" % item.get_name(Item.NameFormat.THE))
			continue

		# Handle quantity
		var actual_quantity := mini(quantity, item.quantity)
		if actual_quantity <= 0:
			Log.d("[DragDrop] Invalid quantity: %d" % actual_quantity)
			continue

		# Add items to actor's inventory
		var new_item: Item
		if actual_quantity == item.quantity:
			# Taking whole stack
			Log.d(
				(
					"[DragDrop] Taking whole stack: %s (quantity: %d)"
					% [item.get_name(Item.NameFormat.THE), item.quantity]
				)
			)
			new_item = item
			map.remove_item(current_pos, item)
		else:
			# Taking partial stack
			Log.d(
				(
					"[DragDrop] Taking partial stack: %s (taking %d of %d)"
					% [item.get_name(Item.NameFormat.THE), actual_quantity, item.quantity]
				)
			)
			new_item = item.split(actual_quantity)
			if not new_item:
				Log.d("[DragDrop] Failed to split item")
				continue

		Log.d("[DragDrop] Adding item to inventory: %s" % new_item.get_name(Item.NameFormat.THE))
		actor.add_item(new_item)
		picked_up_items.append(new_item)
		success = true

		# Add pickup effect
		result.add_effect(PickupEffect.new(actor, new_item, current_pos))

	if success:
		# Format message based on picked up items
		if picked_up_items.size() == 1:
			var item: Item = picked_up_items[0]
			result.message = "%s picked up %s." % [actor, item.get_name(Item.NameFormat.AN)]
		else:
			result.message = "%s picked up multiple items." % actor

	return success


func _to_string() -> String:
	return "PickupAction(actor: %s)" % actor
