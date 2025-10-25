class_name PlayerFireAction
extends FireAction

var source_pos: Vector2i


func _init(p_target_pos: Vector2i) -> void:
	super(World.player, p_target_pos)
	target_pos = p_target_pos
	source_pos = World.current_map.find_monster_position(World.player)


func _to_string() -> String:
	return "PlayerFireAction(target_pos: %s)" % target_pos


func _execute(map: Map, result: ActionResult) -> bool:
	# Get the wielded weapon
	var weapon := World.player.equipment.get_equipped_item(Equipment.Slot.RANGED)
	if not weapon:
		result.message = "You need to wield a ranged weapon first."
		return false
	if not weapon.is_ranged_weapon():
		result.message = "You need to wield a ranged weapon first."
		return false

	# Check ammo before executing
	if weapon.ammo_type != Damage.AmmoType.NONE:
		var has_ammo := false
		var children: Array = weapon.children.to_array()
		for child: Item in children:
			if child.type == Item.Type.AMMO:
				has_ammo = true
				if child.ammo_type != weapon.ammo_type:
					result.message = (
						"The ammo loaded in %s does not match."
						% weapon.get_name(Item.NameFormat.CAPITALIZED)
					)
					return false
				elif child.quantity <= 0:
					result.message = (
						"Click! %s is empty." % child.get_name(Item.NameFormat.CAPITALIZED)
					)
					return false
				break

		if not has_ammo:
			result.message = "Click! %s needs ammo." % weapon.get_name(Item.NameFormat.CAPITALIZED)
			return false

	return super(map, result)
