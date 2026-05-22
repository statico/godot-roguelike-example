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
			&"strength":     row[_get_col(&"strength")].to_int(),
			&"dexterity":    _col_int(row, &"dex", 10),
			&"constitution": _col_int(row, &"con", 10),
			&"wisdom":       _col_int(row, &"wis", 10),
			&"charisma":     _col_int(row, &"cha", 10),
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
			&"xp_reward": row[_get_col(&"xp_reward")].to_int() if _column_indices.has(&"xp_reward") else 0,
		}


static func _get_col(name: String) -> int:
	assert(_column_indices.has(name), "Missing column in monsters.csv: %s" % name)
	return _column_indices[name]


static func _col_int(row: PackedStringArray, col: StringName, default_val: int) -> int:
	if not _column_indices.has(col):
		return default_val
	var idx: int = _column_indices[col]
	if idx >= row.size() or row[idx].is_empty():
		return default_val
	return row[idx].to_int()


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
	monster.hp     = data.max_hp
	monster.max_hp = data.max_hp
	monster._base_strength              = data.strength
	monster.stats._base_dexterity       = data.get(&"dexterity",    10)
	monster.stats._base_constitution    = data.get(&"constitution", 10)
	monster.stats._base_wisdom          = data.get(&"wisdom",       10)
	monster.stats._base_intelligence    = data.get(&"intelligence", 10)
	monster.stats._base_charisma        = data.get(&"charisma",     10)
	monster._base_speed    = _convert_speed(data.speed as String)
	monster.sight_radius   = data.sight_radius
	monster.hit_particles_color = data.hit_particles_color
	monster.slug = slug
	monster.name = data.name
	monster.role = role
	monster.has_head = data.has_head
	monster.has_torso = data.has_torso
	monster.has_legs = data.has_legs
	monster.has_hands = data.has_hands
	monster.xp_reward = data.get(&"xp_reward", 0)

	if data.appearance is Array and not (data.appearance as Array).is_empty():
		var appearances := data.appearance as Array
		if not appearances.is_empty():
			monster.variant = randi() % appearances.size()

	# 클래스 컴포넌트 초기화 (역할 기반)
	var class_type := ClassComponent.Type.NONE
	match role:
		Roles.Type.FIGHTER: class_type = ClassComponent.Type.FIGHTER
		Roles.Type.ROGUE:   class_type = ClassComponent.Type.ROGUE
		Roles.Type.CLERIC:  class_type = ClassComponent.Type.CLERIC
		Roles.Type.RANGER:  class_type = ClassComponent.Type.RANGER
		Roles.Type.BARBARIAN: class_type = ClassComponent.Type.BARBARIAN
	if class_type != ClassComponent.Type.NONE:
		monster.class_comp = ClassComponent.new(monster, class_type)
		# 파이터 기본 전투 스타일: 결투
		if class_type == ClassComponent.Type.FIGHTER:
			monster.class_comp.fighting_style = ClassComponent.FightingStyle.DUELING
		elif class_type == ClassComponent.Type.RANGER:
			monster.class_comp.fighting_style = ClassComponent.FightingStyle.ARCHERY
			Log.i("[MonsterFactory] Ranger initialized with ARCHERY fighting style.")

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

		# Set starting skills from role (SkillComponent API 사용)
		var starting_skills := Roles.get_starting_skills(role)
		for skill_type: Skills.Type in starting_skills:
			monster.skills.set_level(skill_type, starting_skills[skill_type] as Skills.Level)
		Log.d("[MonsterFactory] Applied role skills for %s: %s" % [
			Roles.Type.keys()[role], starting_skills
		])

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
