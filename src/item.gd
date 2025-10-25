class_name Item
extends RefCounted

enum Type {
	AMMO,
	AXE,
	BASE,
	BELT,
	CLOAK,
	CONSUMABLE,
	CONTAINER,
	FOOTWEAR,
	GLOVES,
	GRENADE,
	GUN,
	HAMMER,
	HEADWEAR,
	KNIFE,
	LOWER_ARMOR,
	MASK,
	MELEE,
	MISC,
	MODULE,
	RING,
	SCROLL,
	SPEAR,
	SWORD,
	THROWABLE,
	TOOL,
	UPPER_ARMOR,
	WAND,
}

# Item properties
var name: String = "UNINITIALIZED ITEM"
var type: Type = Type.CONSUMABLE
var sprite_name: StringName = &"hamburger"

# Container and module system
var parent: Item = null
var max_children: int = 0
var children: Set = Set.new([], typeof(Item))
var is_open: bool = false  # Whether this container is currently open

var quantity: int = 1
var _mass: float = 1.0
var max_stack_size: int = 1

# # Combat properties
var skill_type: Skills.Type = Skills.Type.NONE  # Default to NONE for now
var damage: Array[int] = [1, 1]  # [dice, sides]
var damage_types: Array[Damage.Type] = []
var ammo_type: Damage.AmmoType = Damage.AmmoType.NONE
var armor_class: int = 0  # Protection value (higher is better)
var enhancement: int = 0  # How much better (or worse) than normal
var resistances: Dictionary = {}  # Damage types this item resists
var aoe_config: ItemFactory.AreaOfEffectConfig
var is_armed: bool = false
var turns_to_activate: int = 0

# # Consumable properties
var nutrition: int = 0
var delicious: bool = false
var palatable: bool = false
var gross: bool = false
var hp: int = 0
var stim_level: int = 0  # 0 = no stim, 1 = STIM1, 2 = STIM2
var stim_turns: int = 0  # Number of turns the stim effect lasts


func _init(i_know_what_im_doing: bool = false) -> void:
	# We need to be super careful about instantiating items directly, therefore
	# we only allow it in a few places.
	assert(i_know_what_im_doing, "Items must be created through ItemFactory")


func _to_string() -> String:
	var quantity_str := " ⨯ %d" % quantity if quantity > 1 else ""
	return "Item<%s%s>" % [name, quantity_str]


enum NameFormat {
	THE,
	AN,
	PLAIN,
	CAPITALIZED,
}


func get_name(format: NameFormat = NameFormat.PLAIN, with_quantity: bool = true) -> String:
	var prefix := Utils.with_sign(enhancement) + " " if is_weapon() or is_armor() else ""
	var n := prefix + name
	var quantity_str := " ⨯ %d" % quantity if quantity > 1 and with_quantity else ""

	match format:
		NameFormat.THE:
			return "the " + n + quantity_str
		NameFormat.AN:
			return ("an " if n[0] in ["a", "e", "i", "o", "u"] else "a ") + n + quantity_str
		NameFormat.PLAIN:
			return n + quantity_str
		NameFormat.CAPITALIZED:
			return "The " + n + quantity_str

	return "the " + n + quantity_str  # Default fallback


func get_info() -> String:
	var info := get_name(NameFormat.PLAIN) + "\n\n"

	var type_str: String = Item.Type.keys()[type] as String
	info += "Type: " + type_str.replace("_", " ").capitalize() + "\n"

	info += "Mass: %.1f kg\n" % _mass

	if parent:
		info += "Currently inside " + parent.get_name(NameFormat.PLAIN) + "\n"

	if max_stack_size > 1:
		info += "Quantity: %d/%d\n" % [quantity, max_stack_size]

	if is_container():
		info += "Status: %s\n" % ["Open" if is_open else "Closed"]
		info += "Contains %d/%d items\n" % [children.size(), max_children]
	elif children.size() > 0:
		info += "Contains %d items\n" % children.size()

	if is_weapon():
		if damage.size() != 2:
			Log.e("Invalid damage for %s: %s" % [name, damage])
		else:
			info += "Base damage: %sd%s\n" % [damage[0], damage[1]]
		info += "Damage Bonus: %s\n" % Utils.with_sign(enhancement)

	if is_armor():
		info += "Armor Bonus: %s\n" % Utils.with_sign(enhancement)

	if uses_damage_type():
		var damage_type_strs: Array[String] = []
		for damage_type in damage_types:
			damage_type_strs.append(
				str(Damage.Type.keys()[damage_type]).to_lower().replace("_", " ").capitalize()
			)
		info += "Damage type: %s\n" % [", ".join(damage_type_strs)]

	if ammo_type != Damage.AmmoType.NONE:
		info += "Ammo type: %s\n" % [Damage.ammo_type_to_string(ammo_type)]

	if type == Type.GRENADE:
		info += "Armed: %s\n" % is_armed
		if turns_to_activate > 0:
			info += "Turns to activate: %d\n" % turns_to_activate

	if not resistances.is_empty():
		info += "\nResistances:"
		for damage_type: Damage.Type in resistances:
			var resistance_str := str(Damage.Type.keys()[damage_type])
			var value: int = resistances[damage_type]
			info += "\n• %s: %s" % [resistance_str.capitalize(), Utils.with_sign(value)]

	return info


static func get_item_summary(items: Array[Item]) -> String:
	if items.size() == 0:
		return "Nothing"
	elif items.size() == 1:
		return items[0].name
	else:
		var first := items[0].name
		var suffix := (
			" and %s more item%s" % [items.size() - 1, "s" if items.size() - 1 > 1 else ""]
		)
		return first + suffix


func matches(other: Item) -> bool:
	return name == other.name and type == other.type


func split(n: int) -> Item:
	if n <= 0:
		Log.e("Cannot split a non-positive quantity")
		return null

	if n > quantity:
		Log.e("Cannot split more than available quantity")
		return null

	if max_children > 0:
		Log.e("Splitting a container doesn't make sense")
		return null

	# Clone the item
	var new_item := ItemFactory.clone(self)
	new_item.quantity = n

	# Adjust the quantity of the original item
	quantity -= n

	return new_item


func is_weapon() -> bool:
	return (
		type
		in [
			Type.GUN,
			Type.SWORD,
			Type.SPEAR,
			Type.KNIFE,
			Type.HAMMER,
			Type.MELEE,
			Type.THROWABLE,
		]
	)


func uses_damage_type() -> bool:
	return is_weapon() or type in [Type.AMMO, Type.THROWABLE]


func is_armor() -> bool:
	return (
		type
		in [
			Type.LOWER_ARMOR,
			Type.BASE,
			Type.UPPER_ARMOR,
			Type.MASK,
			Type.GLOVES,
			Type.FOOTWEAR,
			Type.HEADWEAR,
		]
	)


func is_ranged_weapon() -> bool:
	return type == Type.GUN or type == Type.THROWABLE


func add_child(item: Item, at_index: int = -1) -> bool:
	if item.parent != null:
		item.parent.remove_child(item)

	# Add the item at the specified index
	if at_index != -1:
		# Check if we can add more children
		if max_children <= 0 or children.size() >= max_children:
			Log.e("Cannot add more children")
			return false

		children.add(item)
	else:
		# Check if we can add more children
		if max_children <= 0 or children.size() >= max_children:
			Log.e("Cannot add more children")
			return false

		children.add(item)

	item.parent = self
	return true


func has_child(item: Item) -> bool:
	# First check direct children
	if children.has(item):
		return true

	# Recursively check children's children
	for child: Item in children.to_array():
		if child.has_child(item):
			return true

	return false


func remove_child(item: Item) -> bool:
	# First check direct children
	if children.has(item):
		children.remove(item)
		item.parent = null
		return true

	# Recursively check children's children
	for child: Item in children.to_array():
		if child.remove_child(item):
			return true

	return false


func get_mass() -> float:
	var total_mass := _mass * quantity  # Base _mass times quantity

	# Add _mass of contained items recursively
	for child: Item in children.to_array():
		total_mass += child.get_mass()

	return total_mass


func is_container() -> bool:
	return type == Type.CONTAINER and max_children > 0


func open() -> void:
	is_open = true


func close() -> void:
	is_open = false


func toggle_open() -> void:
	is_open = not is_open


class CanAcceptChildResult:
	extends RefCounted
	var can_accept: bool = false
	var reason: String = ""


## Checks if this item can accept another item as a child
## This handles both containers and items with modules (guns, armor)
func can_accept_child(child_item: Item) -> CanAcceptChildResult:
	var result := CanAcceptChildResult.new()

	# If the item is itself, accept it, and let reparent_item_action handle the rest
	if child_item == self:
		result.can_accept = true
		return result

	# Check if the item can accept children
	if max_children == 0:
		result.reason = "You can't put that in there."
		return result

	# Check if we have space for more children
	if children.size() >= max_children:
		result.reason = "The %s is full." % get_name(NameFormat.THE)
		return result

	# Check for circular references
	if child_item == self or (child_item.is_container() and child_item.has_child(self)):
		result.reason = "You cannot put something inside itself."
		return result

	# Handle different item types
	if is_container():
		# Regular container logic
		if not is_open:
			result.reason = "The %s is closed." % get_name(NameFormat.THE)
			return result
		result.can_accept = true
		return result
	elif type == Type.GUN:
		# Gun can only accept matching ammo
		if child_item.type != Type.AMMO:
			result.reason = "Only ammo can be loaded into a gun."
			return result
		if child_item.ammo_type != ammo_type:
			result.reason = "This ammo doesn't fit."
			return result
		result.can_accept = true
		return result
	elif is_armor():
		# Armor can only accept modules and power sources
		if not child_item.type == Type.MODULE:
			result.reason = (
				"Only modules can be attached to %s." % get_name(NameFormat.THE)
			)
			return result
		result.can_accept = true
		return result

	# Default case - item doesn't accept children
	result.reason = "%s doesn't have attachments." % get_name(NameFormat.THE)
	return result


## Checks if this item is "open" for showing children
## This handles both containers and items with modules
func is_open_for_children() -> bool:
	if is_container():
		return is_open
	elif type == Type.GUN:
		# Guns are always "open" for showing ammo
		return true
	elif is_armor():
		return true
	elif children.size() > 0:
		# Other items with children use the is_open flag
		return is_open
	return false
