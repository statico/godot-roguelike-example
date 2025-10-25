class_name MonsterFactory
extends RefCounted

const CSV_PATH = &"res://assets/data/monsters.csv"

static var monster_data: Dictionary = {}
static var _column_indices: Dictionary = {}


static func _static_init() -> void:
	_load_monster_data()


static func _load_monster_data() -> void:
	var file := FileAccess.open(CSV_PATH, FileAccess.READ)
	if not file:
		printerr("Failed to open CSV file at ", CSV_PATH)
		return

	# Parse header row to get column indices
	var headers := file.get_csv_line()
	for i in headers.size():
		_column_indices[StringName(headers[i])] = i

	# Read monster data
	while !file.eof_reached():
		var row := file.get_csv_line()
		if row.size() < _column_indices.size() or row[0].is_empty():
			continue

		var appearances := []
		if !row[_get_col(&"appearance")].is_empty():
			appearances = row[_get_col(&"appearance")].split(",")

		monster_data[StringName(row[_get_col(&"slug")])] = {
			&"name": row[_get_col(&"name")],
			&"species": row[_get_col(&"species")],
			&"faction": row[_get_col(&"faction")],
			&"appearance": appearances,
			&"speed": row[_get_col(&"speed")],
			&"strength": row[_get_col(&"strength")].to_int(),
			&"max_hp": row[_get_col(&"max_hp")].to_int(),
			&"behavior": row[_get_col(&"behavior")],
			&"sight_radius": row[_get_col(&"sight_radius")].to_int(),
			&"hit_particles_color":
			Color.from_string(row[_get_col(&"hit_particles_color")], Color(1.0, 0.1, 0.1)),
			&"intelligence": row[_get_col(&"intelligence")].to_int(),
			&"has_head": row[_get_col(&"has_head")].to_lower() == "true",
			&"has_torso": row[_get_col(&"has_torso")].to_lower() == "true",
			&"has_legs": row[_get_col(&"has_legs")].to_lower() == "true",
			&"has_hands": row[_get_col(&"has_hands")].to_lower() == "true",
		}


static func _get_col(name: String) -> int:
	assert(_column_indices.has(name), "Missing column in monsters.csv: %s" % name)
	return _column_indices[name]


## Create a monster from a monster slug
## @param slug The slug of the monster to create
## @param role The role of the monster if it's a player
## @return The created monster
static func create_monster(slug: StringName, role: Roles.Type = Roles.Type.NONE) -> Monster:
	if monster_data.is_empty():
		_load_monster_data()

	var data := monster_data.get(slug, {}) as Dictionary
	assert(!data.is_empty(), "Monster not found: %s" % slug)

	var monster := Monster.new(true)
	monster.species = Species.Type.get((data.species as String).to_upper(), Species.Type.RODENT)
	monster.faction = Factions.Type.get((data.faction as String).to_upper(), Factions.Type.NONE)
	monster.behavior = _convert_behavior(data.behavior as String)
	monster.hp = data.max_hp
	monster.max_hp = data.max_hp
	monster._base_strength = data.strength
	monster._base_speed = _convert_speed(data.speed as String)
	monster.sight_radius = data.sight_radius
	monster.hit_particles_color = data.hit_particles_color
	monster.intelligence = data.intelligence
	monster.slug = slug
	monster.name = data.name
	monster.role = role
	monster.has_head = data.has_head
	monster.has_torso = data.has_torso
	monster.has_legs = data.has_legs
	monster.has_hands = data.has_hands

	if data.appearance is Array and not (data.appearance as Array).is_empty():
		var appearances := data.appearance as Array
		if not appearances.is_empty():
			monster.variant = randi() % appearances.size()

	# If a role is specified, validate species and apply role data
	if role != Roles.Type.NONE:
		var allowed_species := Roles.get_allowed_species(role)
		assert(
			monster.species in allowed_species,
			(
				"Species %s not allowed for role %s"
				% [Species.Type.keys()[monster.species], Roles.Type.keys()[role]]
			)
		)

		# Set faction from role
		monster.faction = Roles.get_faction(role)

		# Set starting skills from role
		var starting_skills := Roles.get_starting_skills(role)
		for skill_type: Skills.Type in starting_skills:
			monster.skill_levels[skill_type] = starting_skills[skill_type] as Skills.Level

	# If role is none, equip starting items
	if role == Roles.Type.NONE:
		_equip_starting_monster(monster)

	# Initialize behavior tree after all properties are set
	monster.behavior_tree = MonsterAI.create_behavior_tree(monster)
	return monster


static func _convert_speed(speed_value: String) -> int:
	match speed_value.to_upper():
		&"VERY_SLOW":
			return Monster.SPEED_VERY_SLOW
		&"SLOW":
			return Monster.SPEED_SLOW
		&"NORMAL":
			return Monster.SPEED_NORMAL
		&"FAST":
			return Monster.SPEED_FAST
		&"VERY_FAST":
			return Monster.SPEED_VERY_FAST
		"":
			return Monster.SPEED_NORMAL
		_:
			assert(false, "Invalid speed value in CSV: %s" % speed_value)
			return Monster.SPEED_NORMAL


static func _convert_behavior(behavior_value: String) -> Monster.Behavior:
	if behavior_value == "":
		return Monster.Behavior.PASSIVE

	return Monster.Behavior.get(behavior_value.to_upper(), Monster.Behavior.PASSIVE)


static func _equip_starting_monster(monster: Monster) -> void:
	var add := func(item_name: StringName, quantity: int = 1, slot: Variant = null) -> void:
		if quantity < 1:
			return
		var item := ItemFactory.create_item(item_name)
		item.quantity = quantity
		monster.add_item(item)
		if slot is Equipment.Slot:
			monster.equipment.equip(item, slot as Equipment.Slot)

	# A very simple loot system
	match monster.species:
		Species.Type.UNDEAD:
			add.call(&"gold", Dice.roll(1, 50) if Dice.chance(0.5) else 0)
		Species.Type.HUMAN:
			add.call(&"apple", Dice.roll(1, 2) if Dice.chance(0.3) else 0)
			add.call(&"orange", Dice.roll(1, 2) if Dice.chance(0.3) else 0)
			add.call(&"banana", Dice.roll(1, 2) if Dice.chance(0.3) else 0)
