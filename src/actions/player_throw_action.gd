class_name PlayerThrowAction
extends ThrowAction


func _init(p_selections: Array[ItemSelection], p_target_pos: Vector2i) -> void:
	super(World.player, p_selections, p_target_pos)


func _execute(map: Map, result: ActionResult) -> bool:
	Log.d("PlayerThrowAction: %s" % selections)

	# Verify that the selection contains a single item with a quantity of 1 or more.
	if selections.size() != 1:
		result.message = "You must select a single item."
		return false
	if selections[0].quantity <= 0:
		Log.e("Invalid quantity: %s" % selections[0].quantity)
		return false

	var item: Item = selections[0].item

	# Verify actor has the item
	if not actor.has_item(item):
		result.message = "You don't have that item."
		return false

	# Verify item is throwable
	if item.type != Item.Type.THROWABLE and item.type != Item.Type.GRENADE:
		result.message = "You can't throw that."
		return false

	var success := super(map, result)
	if success:
		# Messages are already in second person for the player in ThrowAction
		pass
	return success


func _to_string() -> String:
	return "PlayerThrowAction(%s)" % [selections]
