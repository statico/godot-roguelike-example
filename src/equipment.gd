class_name Equipment
extends RefCounted

# Order here is used to determine the best slot for an item
enum Slot {
	UPPER_ARMOR,  # Chest armor, jackets, tactical vests
	LOWER_ARMOR,  # Pants, leg armor
	BASE,  # Base layer
	CLOAK,  # Cloaks, capes
	FOOTWEAR,  # Boots, shoes
	MASK,  # Face masks, respirators
	GLOVES,  # Hand protection
	HEADWEAR,  # Helmets, hats
	BELT,  # Utility belt
	MELEE,  # Melee weapon
	RANGED,  # Ranged weapon
}

# Maps slots to valid item types
static var valid_slot_item_types := {
	Slot.UPPER_ARMOR: [Item.Type.UPPER_ARMOR],
	Slot.LOWER_ARMOR: [Item.Type.LOWER_ARMOR],
	Slot.BASE: [Item.Type.BASE],
	Slot.CLOAK: [Item.Type.CLOAK],
	Slot.FOOTWEAR: [Item.Type.FOOTWEAR],
	Slot.MASK: [Item.Type.MASK],
	Slot.GLOVES: [Item.Type.GLOVES],
	Slot.HEADWEAR: [Item.Type.HEADWEAR],
	Slot.BELT: [Item.Type.BELT],
	Slot.MELEE: Item.Type.values(),  # Any item
	Slot.RANGED: Item.Type.values(),  # Any item
}

var equipped_items: Dictionary = {}
var owner: Monster = null


func _init(p_owner: Monster) -> void:
	owner = p_owner
	# Initialize all slots as empty
	for slot: Slot in Slot.values():
		equipped_items[slot] = null


func _to_string() -> String:
	var result := "Equipment(\n"
	for slot: Slot in Slot.values():
		var item: Item = equipped_items[slot]
		result += "  %s: %s,\n" % [Slot.keys()[slot], str(item) if item else "empty"]
	return result + ")"


class CanEquipResult:
	extends RefCounted

	var can_equip: bool
	var reason: String

	func _init(p_can_equip: bool, p_reason: String = "") -> void:
		can_equip = p_can_equip
		reason = p_reason


static func can_use_slot(monster: Monster, slot: Slot) -> bool:
	match slot:
		Slot.HEADWEAR, Slot.MASK:
			return monster.has_head
		Slot.UPPER_ARMOR, Slot.BASE, Slot.CLOAK, Slot.BELT:
			return monster.has_torso
		Slot.LOWER_ARMOR, Slot.FOOTWEAR:
			return monster.has_legs
		Slot.GLOVES, Slot.MELEE, Slot.RANGED:
			return monster.has_hands
		_:
			return true


func can_equip(item: Item, slot: Slot, module_index: int = -1) -> CanEquipResult:
	if module_index == -1:
		# Item is a top-level equipment item
		if not slot in valid_slot_item_types:
			return CanEquipResult.new(false, "That slot does not exist.")
		if not item.type in valid_slot_item_types[slot]:
			return CanEquipResult.new(false, "That item cannot be equipped there.")
		if item.parent and not item.type == Item.Type.MODULE:
			return CanEquipResult.new(false, "That item is attached to something else.")
		if item == equipped_items[slot]:
			return CanEquipResult.new(false, "That item is already equipped there.")
		if not can_use_slot(owner, slot):
			return CanEquipResult.new(false, "This creature cannot use that equipment slot.")
		return CanEquipResult.new(true)
	else:
		var parent_item: Item = equipped_items[slot]
		if not parent_item:
			return CanEquipResult.new(false, "There is nothing there to attach it to.")
		var children: Array = parent_item.children.to_array()
		if parent_item.max_children <= module_index:
			return CanEquipResult.new(false, "There are no more module slots available.")
		if children.size() > module_index and item == children[module_index]:
			return CanEquipResult.new(false, "That module is already attached there.")
		if parent_item.type == Item.Type.GUN:
			if not item.type == Item.Type.AMMO:
				return CanEquipResult.new(false, "Only ammo can be attached to this item.")
			if item.ammo_type != parent_item.ammo_type:
				return CanEquipResult.new(false, "The ammo type does not match.")
		else:
			if not item.type == Item.Type.MODULE:
				return CanEquipResult.new(false, "Only modules can be attached.")
		return CanEquipResult.new(true)


func equip(item: Item, slot: Slot, module_index: int = -1) -> Item:
	Log.d("Equipping %s slot %s index %s" % [item, Equipment.Slot.keys()[slot], module_index])
	var result := can_equip(item, slot, module_index)
	if not result.can_equip:
		Log.w("  Can't equip! Should check with can_equip first (reason: %s)" % result.reason)
		return null

	if module_index == -1:
		Log.d("Equipping top-level equipment item")

		# Item is a top-level equipment item
		var origin_slot: Variant = get_slot_where_item_is_equipped(item)
		Log.d("  Origin slot: %s" % [Equipment.Slot.keys()[origin_slot] if origin_slot else null])

		# Store currently equipped item to return, if any
		var previous_item: Item = equipped_items[slot]
		Log.d("  Previous item: %s" % previous_item)

		# Remove previous item from origin slot or module
		unequip_item(item)
		unequip_item(previous_item)

		# Equip new item
		equipped_items[slot] = item

		Log.d("  Previous item: %s" % previous_item)
		return previous_item

	else:
		Log.d("Equipping module or power source")

		# Item is a module or power source, or ammo for a gun
		var parent_item: Item = equipped_items[slot]
		Log.d("  Parent item: %s" % parent_item)
		if not parent_item:
			Log.w("  No item equipped in slot %s to add module to" % slot)
			return null

		# Store currently equipped module to return, if any
		var previous_item: Item = null
		var children: Array = parent_item.children.to_array()
		if children.size() > module_index:
			Log.d("  Removing previous item")
			previous_item = children[module_index]
			parent_item.remove_child(previous_item)
			previous_item.parent = null

		# Add new module
		if not parent_item.add_child(item, module_index):
			Log.w("  Failed to add module %s to %s at index %s" % [item, parent_item, module_index])
			return null

		Log.d("  Previous item: %s" % previous_item)
		return previous_item


func unequip(slot: Slot) -> Item:
	var item: Item = equipped_items[slot]
	equipped_items[slot] = null
	return item


func unequip_item(item: Item) -> Item:
	# First check if item is directly equipped in a slot
	for slot: Slot in Slot.values():
		if equipped_items[slot] == item:
			return unequip(slot)

	# Then check if item is a child of any equipped items
	for slot: Slot in Slot.values():
		var equipped: Item = equipped_items[slot]
		if equipped and equipped.remove_child(item):
			return item

	return null


func get_equipped_item(slot: Slot) -> Item:
	return equipped_items[slot]


func is_slot_empty(slot: Slot) -> bool:
	return equipped_items[slot] == null


func get_slot_where_item_is_equipped(item: Item) -> Variant:
	for slot: Slot in Slot.values():
		var equipped: Item = equipped_items[slot]
		if equipped == item:
			return slot
		# Check if item is a child of the equipped item
		if equipped and equipped.has_child(item):
			return slot
	return null


func is_item_equipped(item: Item) -> bool:
	return get_slot_where_item_is_equipped(item) != null


func get_all_equipped_items() -> Array[Item]:
	var items: Array[Item] = []
	for slot: Slot in Slot.values():
		var item: Item = get_equipped_item(slot)
		if item:
			items.append(item)
			for child: Item in item.children.to_array():
				items.append(child)
	return items


func get_best_slot_for_item(item: Item) -> Variant:
	for slot: Slot in Slot.values():
		var check := can_equip(item, slot)
		if check.can_equip:
			return slot
		else:
			Log.d("Can't get best slot for %s: %s" % [item, check.reason])
	return null


func get_total_slot_count() -> int:
	return Slot.values().size()


func get_used_slot_count() -> int:
	var count: int = 0
	for slot: Slot in Slot.values():
		if equipped_items[slot]:
			count += 1
	return count
