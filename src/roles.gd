class_name Roles
extends RefCounted

enum Type { NONE, KNIGHT, MONK, VALKYRIE }

const ROLE_DATA := {
	Type.NONE:
	{
		"name": "None",
		"description": "No special role.",
		"allowed_species":
		[
			Species.Type.HUMAN,
			Species.Type.ARACHNID,
			Species.Type.DOG,
			Species.Type.FELINE,
			Species.Type.MOLLUSK,
			Species.Type.REPTILE,
			Species.Type.RODENT,
			Species.Type.UNDEAD,
		],
		"starting_skills": {},
		"faction": Factions.Type.NONE,
	},
	Type.KNIGHT:
	{
		"name": "Knight",
		"description": "A knight is a warrior trained in the use of a sword and shield.",
		"allowed_species":
		[
			Species.Type.HUMAN,
		],
		"starting_skills":
		{
			Skills.Type.SWORD: Skills.Level.INTERMEDIATE,
			Skills.Type.KNIFE: Skills.Level.INTERMEDIATE,
		},
		"faction": Factions.Type.HUMAN,
	},
	Type.MONK:
	{
		"name": "Monk",
		"description": "A monk is a warrior trained in the use of a sword and shield.",
		"allowed_species":
		[
			Species.Type.HUMAN,
		],
		"starting_skills":
		{
			Skills.Type.FISTS: Skills.Level.ADVANCED,
			Skills.Type.BOW: Skills.Level.ADVANCED,
		},
	},
	Type.VALKYRIE:
	{
		"name": "Valkyrie",
		"description": "A valkyrie is a warrior trained in the use of a sword and shield.",
		"allowed_species":
		[
			Species.Type.HUMAN,
		],
		"starting_skills":
		{
			Skills.Type.SWORD: Skills.Level.INTERMEDIATE,
			Skills.Type.SPEAR: Skills.Level.INTERMEDIATE,
			Skills.Type.BOW: Skills.Level.INTERMEDIATE,
		},
		"faction": Factions.Type.HUMAN,
	},
}


static func get_role_data(role_type: Type) -> Dictionary:
	assert(ROLE_DATA.has(role_type), "Invalid role type: %s" % role_type)
	return ROLE_DATA[role_type]


static func get_allowed_species(role_type: Type) -> Array[Species.Type]:
	var ret: Array[Species.Type] = []
	for species: Species.Type in get_role_data(role_type).allowed_species:
		ret.append(species)
	return ret


static func get_starting_skills(role_type: Type) -> Dictionary:
	return get_role_data(role_type).starting_skills


static func get_faction(role_type: Type) -> Factions.Type:
	return get_role_data(role_type).faction


static func equip_monster(monster: Monster, role_type: Type) -> void:
	match role_type:
		Type.NONE:
			pass  # No starting equipment
		Type.KNIGHT:
			_equip_knight(monster)
		Type.MONK:
			_equip_monk(monster)
		Type.VALKYRIE:
			_equip_valkyrie(monster)
		_:
			assert(false, "Unhandled role type: %s" % role_type)


static func _equip_knight(monster: Monster) -> void:
	var sword := ItemFactory.create_item(&"longsword")
	sword.enhancement = 1
	monster.add_item(sword)
	monster.equipment.equip(sword, Equipment.Slot.MELEE)

	var knife := ItemFactory.create_item(&"dagger")
	knife.enhancement = 1
	monster.add_item(knife)

	var bow := ItemFactory.create_item(&"bow")
	monster.add_item(bow)
	monster.equipment.equip(bow, Equipment.Slot.RANGED)

	var arrows := ItemFactory.create_item(&"arrow")
	arrows.quantity = randi_range(15, 25)
	bow.add_child(arrows)

	var armor := ItemFactory.create_item(&"silver_armor")
	armor.enhancement = 1
	monster.add_item(armor)
	monster.equipment.equip(armor, Equipment.Slot.UPPER_ARMOR)

	var helm := ItemFactory.create_item(&"tufted_helm")
	monster.add_item(helm)
	monster.equipment.equip(helm, Equipment.Slot.HEADWEAR)

	for i in range(randi_range(3, 4)):
		var grenade := ItemFactory.create_item(&"poison_splash_potion")
		monster.add_item(grenade)

	for i in range(randi_range(2, 4)):
		monster.add_item(ItemFactory.create_item(&"food_ration"))


static func _equip_monk(monster: Monster) -> void:
	monster.add_item(ItemFactory.create_item(&"godot_user_guide"))
	monster.add_item(ItemFactory.create_item(&"gdscript_reference"))
	for i in range(randi_range(2, 4)):
		monster.add_item(ItemFactory.create_item(&"apple"))


static func _equip_valkyrie(monster: Monster) -> void:
	var sword := ItemFactory.create_item(&"longsword")
	sword.enhancement = 2
	monster.add_item(sword)
	monster.equipment.equip(sword, Equipment.Slot.MELEE)

	var armor := ItemFactory.create_item(&"bronze_armor")
	armor.enhancement = 2
	monster.add_item(armor)
	monster.equipment.equip(armor, Equipment.Slot.UPPER_ARMOR)

	var helm := ItemFactory.create_item(&"soldier_helm")
	monster.add_item(helm)
	monster.equipment.equip(helm, Equipment.Slot.HEADWEAR)

	for i in range(randi_range(2, 4)):
		monster.add_item(ItemFactory.create_item(&"food_ration"))
