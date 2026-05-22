class_name Roles
extends RefCounted

# =============================================================
# ⚔️ [구역 1] D&D 클래스 타입 (D&D CLASS TYPES)
# =============================================================

enum Type { NONE, FIGHTER, RANGER, CLERIC, ROGUE, BARBARIAN }

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
	Type.FIGHTER:
	{
		"name": "Fighter",
		"description": "A classic martial warrior. Expert with heavy weapons, swords, and shields.",
		"allowed_species":
		[
			Species.Type.HUMAN,
		],
		"starting_skills":
		{
			Skills.Type.SWORD: Skills.Level.INTERMEDIATE,
			Skills.Type.HAMMER: Skills.Level.INTERMEDIATE,
		},
		"faction": Factions.Type.HUMAN,
	},
	Type.RANGER:
	{
		"name": "Ranger",
		"description": "A ranged hunter. Deadly from a distance with bows and quick with knives.",
		"allowed_species":
		[
			Species.Type.HUMAN,
		],
		"starting_skills":
		{
			Skills.Type.BOW: Skills.Level.ADVANCED,
			Skills.Type.KNIFE: Skills.Level.BASIC,
			Skills.Type.THROWING: Skills.Level.INTERMEDIATE,
		},
		"faction": Factions.Type.HUMAN,
	},
	Type.CLERIC:
	{
		"name": "Cleric",
		"description": "A holy supporter. Wields hammers and heals/buffs allies.",
		"allowed_species":
		[
			Species.Type.HUMAN,
		],
		"starting_skills":
		{
			Skills.Type.HAMMER: Skills.Level.INTERMEDIATE,
			Skills.Type.UTILITY: Skills.Level.ADVANCED,
		},
		"faction": Factions.Type.HUMAN,
	},
	Type.ROGUE:
	{
		"name": "Rogue",
		"description": "A stealthy assassin. Hits hard and fast with knives, escaping to shadows.",
		"allowed_species":
		[
			Species.Type.HUMAN,
		],
		"starting_skills":
		{
			Skills.Type.KNIFE: Skills.Level.ADVANCED,
			Skills.Type.THROWING: Skills.Level.INTERMEDIATE,
		},
		"faction": Factions.Type.HUMAN,
	},
	Type.BARBARIAN:
	{
		"name": "Barbarian",
		"description": "A savage warrior who enters a battle rage. High health, devastating melee power, and unarmored durability.",
		"allowed_species":
		[
			Species.Type.HUMAN,
		],
		"starting_skills":
		{
			Skills.Type.SWORD: Skills.Level.INTERMEDIATE,
		},
		"faction": Factions.Type.HUMAN,
	},
}

# =============================================================
# 🔧 [구역 2] 정보 조회 API (GETTERS)
# =============================================================

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

# =============================================================
# 📦 [구역 3] 시작 장비 세팅 (STARTER EQUIPMENT)
# =============================================================

static func equip_monster(monster: Monster, role_type: Type) -> void:
	match role_type:
		Type.NONE:
			pass
		Type.FIGHTER:
			_equip_fighter(monster)
		Type.RANGER:
			_equip_ranger(monster)
		Type.CLERIC:
			_equip_cleric(monster)
		Type.ROGUE:
			_equip_rogue(monster)
		Type.BARBARIAN:
			_equip_barbarian(monster)
		_:
			assert(false, "Unhandled role type: %s" % role_type)


static func _equip_fighter(monster: Monster) -> void:
	var sword := ItemFactory.create_item(&"longsword")
	sword.enhancement = 1
	monster.add_item(sword)
	monster.equipment.equip(sword, Equipment.Slot.MELEE)

	var armor := ItemFactory.create_item(&"silver_armor")
	armor.enhancement = 1
	monster.add_item(armor)
	monster.equipment.equip(armor, Equipment.Slot.UPPER_ARMOR)

	var helm := ItemFactory.create_item(&"tufted_helm")
	monster.add_item(helm)
	monster.equipment.equip(helm, Equipment.Slot.HEADWEAR)

	for i in range(randi_range(2, 4)):
		monster.add_item(ItemFactory.create_item(&"food_ration"))


static func _equip_ranger(monster: Monster) -> void:
	var bow := ItemFactory.create_item(&"bow")
	monster.add_item(bow)
	monster.equipment.equip(bow, Equipment.Slot.RANGED)

	var arrows := ItemFactory.create_item(&"arrow")
	arrows.quantity = randi_range(20, 30)
	bow.add_child(arrows)

	var knife := ItemFactory.create_item(&"dagger")
	monster.add_item(knife)

	var armor := ItemFactory.create_item(&"bronze_armor")
	monster.add_item(armor)
	monster.equipment.equip(armor, Equipment.Slot.UPPER_ARMOR)

	for i in range(randi_range(2, 4)):
		monster.add_item(ItemFactory.create_item(&"food_ration"))


static func _equip_cleric(monster: Monster) -> void:
	# Clerics start with a mace (hammer category) and a shield/armor
	var mace := ItemFactory.create_item(&"mace") if ItemFactory.item_data.has(&"mace") else ItemFactory.create_item(&"longsword")
	monster.add_item(mace)
	monster.equipment.equip(mace, Equipment.Slot.MELEE)

	var armor := ItemFactory.create_item(&"bronze_armor")
	monster.add_item(armor)
	monster.equipment.equip(armor, Equipment.Slot.UPPER_ARMOR)

	var helm := ItemFactory.create_item(&"soldier_helm")
	monster.add_item(helm)
	monster.equipment.equip(helm, Equipment.Slot.HEADWEAR)

	# Utility / Healing potions
	for i in range(2):
		var heal_pot := ItemFactory.create_item(&"health_potion") if ItemFactory.item_data.has(&"health_potion") else ItemFactory.create_item(&"food_ration")
		monster.add_item(heal_pot)

	for i in range(2):
		monster.add_item(ItemFactory.create_item(&"food_ration"))


static func _equip_rogue(monster: Monster) -> void:
	var dagger := ItemFactory.create_item(&"dagger")
	dagger.enhancement = 1
	monster.add_item(dagger)
	monster.equipment.equip(dagger, Equipment.Slot.MELEE)

	# Rogues carry throwing daggers / potions
	for i in range(3):
		var poison := ItemFactory.create_item(&"poison_splash_potion")
		monster.add_item(poison)

	for i in range(3):
		monster.add_item(ItemFactory.create_item(&"food_ration"))


static func _equip_barbarian(monster: Monster) -> void:
	var greataxe := ItemFactory.create_item(&"greataxe")
	monster.add_item(greataxe)
	monster.equipment.equip(greataxe, Equipment.Slot.MELEE)

	for i in range(2):
		var handaxe := ItemFactory.create_item(&"handaxe")
		monster.add_item(handaxe)

	for i in range(3):
		monster.add_item(ItemFactory.create_item(&"food_ration"))
