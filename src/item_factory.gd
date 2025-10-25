class_name ItemFactory
extends RefCounted

const CSV_PATH = &"res://assets/data/items.csv"


## Data structure for area of effect damage
class AreaOfEffectConfig:
	extends RefCounted

	var type: Damage.Type
	var radius: int
	var turns: int

	func _init(p_type: Damage.Type, p_radius: int, p_turns: int) -> void:
		type = p_type
		radius = p_radius
		turns = p_turns

	func _to_string() -> String:
		return "AoE(%s:r%d:t%d)" % [Damage.Type.keys()[type], radius, turns]


static var item_data: Dictionary = {}
static var _column_indices: Dictionary = {}


static func _static_init() -> void:
	_load_item_data()


## Loads item data from CSV file
static func _load_item_data() -> void:
	item_data.clear()
	_column_indices.clear()
	var file := FileAccess.open(CSV_PATH, FileAccess.READ)
	assert(file, "Failed to open CSV file at %s" % CSV_PATH)

	# Parse header row to get column indices
	var headers := file.get_csv_line()
	for i in headers.size():
		_column_indices[StringName(headers[i])] = i

	# Read item data
	while !file.eof_reached():
		var row := file.get_csv_line()
		if row.size() < _column_indices.size() or row[0].is_empty():
			continue

		# Slugify the item name
		var slug := StringName(
			(
				row[_get_col(&"name")]
				. to_lower()
				. replace(" ", "_")
				. replace("-", "_")
				# Remove special characters and collapse multiple underscores
				. replace("(", "")
				. replace(")", "")
				. replace("[", "")
				. replace("]", "")
				. replace("{", "")
				. replace("}", "")
				. replace(".", "")
				. replace(",", "")
				. replace("!", "")
				. replace("?", "")
				. replace("'", "")
				. replace('"', "")
				. replace(":", "")
				. replace(";", "")
				. replace("/", "_")
				. replace("\\", "_")
				. replace("+", "_plus")
				. replace("=", "_equals")
				. replace("@", "_at")
				. replace("#", "_hash")
				. replace("$", "_dollar")
				. replace("%", "_percent")
				. replace("^", "_caret")
				. replace("&", "_and")
				. replace("*", "_star")
				. replace("|", "_pipe")
				. replace("<", "_lt")
				. replace(">", "_gt")
				. replace("~", "_tilde")
				. replace("`", "")
				# Collapse multiple underscores into one
				. replace("__", "_")
				. strip_edges()
			)
		)

		# Ensure no duplicate items
		assert(!item_data.has(slug), "Duplicate item slug: %s" % slug)

		# Record simple columns
		var data := {
			&"slug": slug,
			&"name": row[_get_col(&"name")],
			&"sprite_name": _split_to_stringnames(row[_get_col(&"sprite")]),
			&"mass": row[_get_col(&"mass")].to_float(),
			&"armor_class": row[_get_col(&"ac")].to_int(),
			&"skill": row[_get_col(&"skill")],
			&"ammo_type": Damage.AmmoType.NONE,
			&"probability": row[_get_col(&"probability")].to_int(),
			&"nutrition": row[_get_col(&"nutrition")].to_int(),
			&"delicious": false,
			&"palatable": false,
			&"gross": false,
			&"hp": 0,
			&"damage": [1, 1],
			&"damage_types": [Damage.Type.BLUNT] as Array[Damage.Type],
			&"max_stack_size": row[_get_col(&"max_stack_size")].to_int(),
			&"max_children": 0,
			&"resistance_multiplier": row[_get_col(&"resistance_multiplier")].to_int(),
			&"aoe": null,
			&"skill_type": Skills.Type.NONE,
			&"stim_level": 0,  # 0 = no stim, 1 = STIM1, 2 = STIM2
			&"stim_turns": 0,  # Number of turns the stim effect lasts
		}

		# Set default values
		if not data[&"probability"]:
			data[&"probability"] = 0
		if not data[&"nutrition"]:
			data[&"nutrition"] = 0
		if not data[&"mass"]:
			data[&"mass"] = 1.0
		if not data[&"max_stack_size"]:
			data[&"max_stack_size"] = 1
		if not data[&"max_children"]:
			data[&"max_children"] = 0

		# Parse type
		var type_name := row[_get_col(&"type")]
		assert(type_name, "Item type cannot be empty")
		var item_type: Item.Type
		var type_found := false
		for type_key: StringName in Item.Type.keys():
			if type_name.to_upper() == type_key.to_upper():
				item_type = Item.Type[type_key]
				type_found = true
				break
		assert(type_found, "Invalid item type: %s" % type_name)
		data[&"type"] = item_type

		# Parse damage dice (format: "1d4") into tuple
		var damage := row[_get_col(&"damage")]
		if not damage.is_empty():
			var parts := damage.split("d")
			data[&"damage"] = [parts[0].to_int(), parts[1].to_int()]

		# Parse damage type
		if !row[_get_col(&"damage_types")].is_empty():
			var strings := row[_get_col(&"damage_types")].split(",")
			if not strings.is_empty():
				var types: Array[Damage.Type] = []
				for type_str in strings:
					for key: StringName in Damage.Type.keys():
						if type_str.to_upper() == key.to_upper():
							types.append(Damage.Type[key])
							break
				data[&"damage_types"] = types

		# Parse ammo type
		if !row[_get_col(&"ammo_type")].is_empty():
			match row[_get_col(&"ammo_type")]:
				"arrow":
					data[&"ammo_type"] = Damage.AmmoType.ARROW
				"bolt":
					data[&"ammo_type"] = Damage.AmmoType.BOLT
				_:
					Log.e("Invalid ammo type: %s" % row[_get_col(&"ammo_type")])

		# Parse flags, which are like sparse columns. Flags are in the format of
		# "flag_name[:value1[:value2[:...]]]", so they should be first split by
		# commas, and then the value of each flag should be split by colons
		var flags := row[_get_col(&"flags")]
		if !flags.is_empty() and not flags.begins_with("??"):  # "??" is a comment
			_parse_flags(flags, data)

		# Parse resistances from flags that start with "resist_"
		var resistances := {}
		for key: StringName in data:
			var key_str := String(key)
			if key_str.begins_with("resist_"):
				var resistance := key_str.substr(7).to_upper()  # Remove "resist_" prefix
				var damage_type: Variant = Damage.Type.get(resistance)
				assert(
					damage_type is Damage.Type, "Invalid resistance for %s: %s" % [slug, resistance]
				)

				# Get resistance value from flag
				var value: int = 0
				if data[key] is bool:
					value = 1 if data[key] else 0
				elif data[key] is String:
					value = (data[key] as String).to_int()
				elif data[key] is int:
					value = data[key]

				# Apply resistance multiplier if defined
				var multiplier := 1
				if data.has(&"resistance_multiplier"):
					multiplier = Utils.to_int(data.resistance_multiplier)
				value *= multiplier

				# Add to existing value if present
				if resistances.has(damage_type):
					resistances[damage_type] += value
				else:
					resistances[damage_type] = value

		data[&"resistances"] = resistances

		# Guns that have an ammo type must have max_children = 1
		if data[&"ammo_type"] != Damage.AmmoType.NONE and data[&"type"] == Item.Type.GUN:
			data[&"max_children"] = 1

		# Parse area of effect data
		if data[&"aoe"] is Array:
			var parts: Array = data[&"aoe"]
			assert(parts.size() == 3, "Invalid AoE data for %s: %s" % [slug, data[&"aoe"]])
			var damage_type: Variant = Damage.Type.get((parts[0] as String).to_upper())
			assert(damage_type != null, "Invalid AoE type for %s: %s" % [slug, parts[0]])
			data[&"aoe"] = AreaOfEffectConfig.new(
				damage_type as Damage.Type,
				(parts[1] as String).to_int(),
				(parts[2] as String).to_int()
			)

		# Parse skill type
		if !row[_get_col(&"skill")].is_empty():
			var skill_str := row[_get_col(&"skill")].to_upper()
			var skill_found := false
			for skill_key: StringName in Skills.Type.keys():
				if skill_str == skill_key:
					data[&"skill_type"] = Skills.Type[skill_key]
					skill_found = true
					break
			assert(skill_found, "Invalid skill type for %s: %s" % [slug, skill_str])

		item_data[slug] = data


static func _get_col(name: StringName) -> int:
	assert(_column_indices.has(name), "Missing column in items.csv: %s" % name)
	return _column_indices[name]


static func _split_to_stringnames(text: String, separator: String = ",") -> Array[StringName]:
	if text.is_empty():
		return []
	var parts := Array(text.split(separator))
	var ret: Array[StringName] = []
	for part: String in parts:
		ret.append(StringName(part.strip_edges()))
	return ret


static func create_item(slug: StringName) -> Item:
	var item := Item.new(true)
	var data := item_data.get(slug, {}) as Dictionary

	if data.is_empty():
		var closest_name := find_closest_item_name(slug)
		Log.e("Item not found: %s -- did you mean %s?" % [slug, closest_name])
		assert(false, "Item not found: %s" % slug)

	item.name = data.name
	item.type = data.type
	item.skill_type = data.get(&"skill_type", Skills.Type.KNIFE)  # Default to KNIFE if not specified
	item.damage = Utils.array_of_ints(data.damage)
	item.damage_types = data.damage_types
	item.ammo_type = data.ammo_type
	item.max_stack_size = data.max_stack_size
	item.max_children = Utils.to_int(data.max_children) if data.has(&"max_children") else 0
	item.armor_class = Utils.to_int(data.armor_class)
	item.resistances = data.resistances
	item.sprite_name = Utils.array_of_stringnames(data.sprite_name).pick_random()
	item.aoe_config = data.aoe
	item.nutrition = Utils.to_int(data.nutrition)
	item.delicious = data.delicious
	item.palatable = data.palatable
	item.gross = data.gross
	item.hp = Utils.to_int(data.hp)
	item.stim_level = Utils.to_int(data.stim_level)
	item.stim_turns = Utils.to_int(data.stim_turns)
	item._mass = Utils.to_float(data.mass)

	# Set default grenade timing properties
	if item.type == Item.Type.GRENADE:
		item.turns_to_activate = 2

	_apply_flags(item, data)

	return item


# Keep any assignment logic close to create_item()
static func clone(item: Item) -> Item:
	var new_item := Item.new(true)
	new_item.name = item.name
	new_item.type = item.type
	new_item.skill_type = item.skill_type
	new_item.sprite_name = item.sprite_name
	new_item.damage = item.damage
	new_item.damage_types = item.damage_types
	new_item.ammo_type = item.ammo_type
	new_item.max_stack_size = item.max_stack_size
	new_item.armor_class = item.armor_class
	new_item.resistances = item.resistances
	new_item.aoe_config = item.aoe_config
	new_item.is_armed = item.is_armed
	new_item.turns_to_activate = item.turns_to_activate
	new_item.nutrition = item.nutrition
	new_item.delicious = item.delicious
	new_item.palatable = item.palatable
	new_item.gross = item.gross
	new_item.hp = item.hp
	new_item.stim_level = item.stim_level
	new_item.stim_turns = item.stim_turns
	new_item._mass = item._mass
	return new_item


static func find_closest_item_name(name: String) -> StringName:
	var min_distance := 999999
	var closest_name: StringName

	# Search through all item IDs
	for item_id: StringName in item_data.keys():
		var distance := Utils.levenshtein_distance(name.to_lower(), item_id.to_lower())
		if distance < min_distance:
			min_distance = distance
			closest_name = item_id

	return closest_name


static func _parse_flags(flags_str: String, data: Dictionary) -> void:
	if flags_str.is_empty():
		return

	var flags := flags_str.split(",")
	for flag in flags:
		var parts := flag.strip_edges().split(":")
		var flag_name := StringName(parts[0])

		# Ensure flag name doesn't conflict with column names
		assert(
			not _column_indices.has(flag_name),
			"Flag name '%s' conflicts with column name" % [flag_name]
		)

		if parts.size() == 1:
			# Simple boolean flag
			data[flag_name] = true
			continue

		match flag_name:
			&"stim":
				assert(
					parts.size() == 3,
					"Stim flag must have 2 values (level, turns) but got %s" % [parts.slice(1)]
				)
				data[&"stim_level"] = parts[1].to_int()
				data[&"stim_turns"] = parts[2].to_int()
			&"aoe":
				assert(
					parts.size() == 4,
					(
						"AoE flag must have 3 values (type, radius, turns) but got %s"
						% [parts.slice(1)]
					)
				)
				var damage_type: Variant = Damage.Type.get(parts[1].to_upper())
				assert(damage_type != null, "Invalid AoE damage type: %s" % parts[1])
				data[&"aoe"] = AreaOfEffectConfig.new(
					damage_type as Damage.Type,
					(parts[2] as String).to_int(),
					(parts[3] as String).to_int()
				)
			_:
				# Handle other flags with values
				if parts.size() == 2:
					data[flag_name] = parts[1]
				else:
					data[flag_name] = true


static func _apply_flags(item: Item, data: Dictionary) -> void:
	if data.has("stim_level"):
		item.stim_level = data.stim_level
		item.stim_turns = data.stim_turns
