class_name EquipAction
extends ActorAction

var item: Item
var slot: Equipment.Slot
var module_index: int


func _init(
	p_actor: Monster, p_item: Item, p_slot: Equipment.Slot, p_module_index: int = -1
) -> void:
	super(p_actor)
	item = p_item
	slot = p_slot
	module_index = p_module_index


func _execute(map: Map, result: ActionResult) -> bool:
	if not super(map, result):
		return false

	# Verify actor still has the item
	if not actor.has_item(item):
		result.message = "You no longer have that item."
		return false

	# Verify item can be equipped to slot
	var check := actor.equipment.can_equip(item, slot, module_index)
	if not check.can_equip:
		result.message = check.reason
		return false

	# Is this the same item as the currently equipped item?
	if actor.equipment.equipped_items[slot] == item:
		result.message = "%s is already equipped." % item.get_name(Item.NameFormat.THE)
		return false

	# Equip and handle previous item
	var previous_item := actor.equipment.equip(item, slot, module_index)
	var new_slot: Variant = actor.equipment.get_slot_where_item_is_equipped(previous_item)
	if slot == Equipment.Slot.MELEE and not item.is_weapon():
		result.message = "You are now wielding %s." % item.get_name(Item.NameFormat.AN)
	elif (
		previous_item
		and slot in [Equipment.Slot.MELEE, Equipment.Slot.RANGED]
		and new_slot in [Equipment.Slot.MELEE, Equipment.Slot.RANGED]
	):
		result.message = (
			"You swap %s for %s."
			% [item.get_name(Item.NameFormat.THE), previous_item.get_name(Item.NameFormat.THE)]
		)
	elif item.parent:
		result.message = (
			"You attach %s to %s."
			% [
				item.get_name(Item.NameFormat.THE),
				item.parent.get_name(Item.NameFormat.THE),
			]
		)
	else:
		result.message = "You equip %s." % item.get_name(Item.NameFormat.AN)

	return true
