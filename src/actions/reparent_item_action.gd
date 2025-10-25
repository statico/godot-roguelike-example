class_name ReparentItemAction
extends ActorAction

var item: Item
var new_parent: Item  # null means move to top-level inventory


func _init(p_actor: Monster, p_item: Item, p_new_parent: Item = null) -> void:
	super(p_actor)
	item = p_item
	new_parent = p_new_parent


func _execute(map: Map, result: ActionResult) -> bool:
	if not super(map, result):
		return false

	# Check if we dragged something onto itself
	if item == new_parent:
		Log.d("[DragDrop] Item dragged onto itself: %s" % item)
		return false

	# If the item is already in the desired parent, do nothing
	if item.parent == new_parent:
		Log.d("[DragDrop] Item is already in the desired parent: %s" % item)
		return false

	# Check if actor has the item
	if not actor.has_item(item):
		result.message = "You don't have that item."
		return false

	# Moving to top-level inventory
	if new_parent == null:
		# If item is already at top level, do nothing
		if item.parent == null:
			result.message = "The item is already in your inventory."
			return false

		# Store the old parent for the message
		var old_parent := item.parent

		# Remove from current parent
		old_parent.remove_child(item)

		# Add to actor's inventory (it's already there, but this ensures it's at the top level)
		actor.add_item(item)

		result.message = (
			"You take %s out of %s."
			% [item.get_name(Item.NameFormat.THE), old_parent.get_name(Item.NameFormat.THE)]
		)
		return true

	# Moving to a new parent container/item

	# Check if new parent is accessible
	if not actor.has_item(new_parent):
		# Check if new parent is on the ground at the actor's position
		var actor_pos := map.find_monster_position(actor)
		var ground_items := map.get_items(actor_pos)
		if not ground_items.has(new_parent):
			result.message = "You don't have access to that container."
			return false

	# Check if the new parent can accept this item
	var check := new_parent.can_accept_child(item)
	if not check.can_accept:
		result.message = check.reason
		return false

	# All checks passed, perform the reparenting

	# Remove from current parent
	if item.parent:
		item.parent.remove_child(item)
	else:
		# Remove from actor's top-level inventory
		actor.remove_item(item)

	# Add to new parent
	if new_parent.add_child(item):
		result.message = (
			"You put %s into %s."
			% [item.get_name(Item.NameFormat.THE), new_parent.get_name(Item.NameFormat.THE)]
		)
		return true
	else:
		# If adding failed, put the item back where it was
		actor.add_item(item)
		result.message = "Failed to put the item in the container."
		return false


func _to_string() -> String:
	return "ReparentItemAction(actor: %s, item: %s, new_parent: %s)" % [actor, item, new_parent]
