class_name DropAction
extends ActorAction

var selections: Array[ItemSelection]


func _init(p_actor: Monster, p_selections: Array[ItemSelection]) -> void:
	super(p_actor)
	selections = p_selections


func _execute(map: Map, result: ActionResult) -> bool:
	if not super(map, result):
		return false

	Log.d("[DragDrop] Executing DropAction for %d selections" % selections.size())

	# Get actor's current position
	var current_pos := map.find_monster_position(actor)
	if not current_pos:
		Log.e("Actor not found in map: %s" % actor)
		return false

	# If this selection includes non-containers with children, split them out.
	for selection in selections:
		if selection.item.type == Item.Type.CONTAINER:
			continue
		Log.d(
			(
				"[DragDrop] Non-container item with children: %s (children: %d)"
				% [selection.item.get_name(Item.NameFormat.THE), selection.item.children.size()]
			)
		)
		var children: Array = selection.item.children.to_array()
		for child: Item in children:
			child.parent = null
			selections.append(ItemSelection.new(child, child.quantity))

	var success := false
	var dropped_items := []

	# Process each selection
	for selection in selections:
		var item := selection.item
		var quantity := selection.quantity

		Log.d(
			(
				"[DragDrop] Processing drop selection: %s (quantity: %d)"
				% [item.get_name(Item.NameFormat.THE), quantity]
			)
		)

		# Verify actor has the item
		if not actor.has_item(item):
			Log.e("Actor does not have item: %s" % item.get_name())
			continue

		# Handle quantity
		var actual_quantity := mini(quantity, item.quantity)
		if actual_quantity <= 0:
			Log.e("Tried to drop 0 or less items: %s" % item.get_name())
			continue

		var dropped_item: Item
		if item.max_stack_size > 1:
			# Split off the dropped portion
			Log.d(
				(
					"[DragDrop] Splitting stackable item: %s (dropping %d of %d)"
					% [item.get_name(Item.NameFormat.THE), actual_quantity, item.quantity]
				)
			)
			dropped_item = item.split(actual_quantity)
			# Remove the original item if it's now empty
			if item.quantity == 0:
				Log.d("[DragDrop] Original item is now empty, removing from inventory")
				assert(actor.remove_item(item))
		else:
			dropped_item = item
			Log.d(
				(
					"[DragDrop] Removing non-stackable item from inventory: %s"
					% item.get_name(Item.NameFormat.THE)
				)
			)
			assert(actor.remove_item(item))

		assert(dropped_item)
		dropped_item.parent = null

		# Add item to map with stacking
		Log.d(
			(
				"[DragDrop] Adding item to map at position %s: %s"
				% [current_pos, dropped_item.get_name(Item.NameFormat.THE)]
			)
		)
		var final_item := map.add_item_with_stacking(current_pos, dropped_item)
		if final_item:
			dropped_items.append(final_item)
			result.add_effect(DropEffect.new(actor, final_item, current_pos))
			success = true

	if success:
		# Make sure items are no longer equipped
		for item: Item in dropped_items:
			if actor.equipment.get_slot_where_item_is_equipped(item) != null:
				Log.d(
					"[DragDrop] Unequipping dropped item: %s" % item.get_name(Item.NameFormat.THE)
				)
			actor.equipment.unequip_item(item)

		# Format message based on dropped items
		if dropped_items.size() == 1:
			var item: Item = dropped_items[0]
			result.message = "%s dropped %s." % [actor, item.get_name(Item.NameFormat.AN)]
		else:
			result.message = "%s dropped multiple items." % actor

	return success


func _to_string() -> String:
	return "DropAction(%s)" % [selections]
