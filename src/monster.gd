class_name Monster
extends RefCounted

enum Behavior {
	PASSIVE,  # Doesn't actively pursue targets
	AGGRESSIVE,  # Pursues and attacks targets
	FEARFUL,  # Runs away from threats
	CURIOUS,  # Follows player but doesn't attack
}

enum NameFormat {
	THE,
	AN,
	PLAIN,
	CAPITALIZED,
}

const SPEED_VERY_SLOW = 3
const SPEED_SLOW = 6
const SPEED_NORMAL = 12
const SPEED_FAST = 18
const SPEED_VERY_FAST = 24

# Immutable properties
var slug: StringName  # The ID from the monster factory for data lookup
var name: String
var species: Species.Type
var variant: int = 0
var hit_particles_color := Color(1.0, 0.1, 0.1)

# Stats and mutables
var hp: int
var max_hp: int
var role: Roles.Type = Roles.Type.NONE  # Add role property
var _base_strength: int
var _base_speed: int = SPEED_NORMAL
var _base_hp_regen: int = 1  # Base HP regen per 3 turns
var intelligence: int = 5
var behavior: Behavior
var sight_radius: int
var is_dead: bool = false
var equipment: Equipment = Equipment.new(self)
var inventory: Set = Set.new([], typeof(Item))
var energy: int = 0
var nutrition := Nutrition.new()
var status_effects: Array[StatusEffect] = []

# Behavior
var behavior_tree: MonsterAI.BTNode
var next_action: ActorAction
var faction: Factions.Type = Factions.Type.NONE
var hates_player: bool = false

# Body part properties that determine equipment usage
var has_head: bool = true
var has_torso: bool = true
var has_legs: bool = true
var has_hands: bool = true

# Skill levels for each skill type, defaulting to UNSKILLED
var skill_levels: Dictionary = {
	Skills.Type.KNIFE: Skills.Level.UNSKILLED,
	Skills.Type.SWORD: Skills.Level.UNSKILLED,
	Skills.Type.HAMMER: Skills.Level.UNSKILLED,
	Skills.Type.SPEAR: Skills.Level.UNSKILLED,
	Skills.Type.FISTS: Skills.Level.UNSKILLED,
	Skills.Type.UTILITY: Skills.Level.UNSKILLED,
	Skills.Type.THROWING: Skills.Level.UNSKILLED,
}


func _init(constructed_via_factory: bool = false) -> void:
	assert(constructed_via_factory, "Monsters must be created through MonsterFactory")


func _to_string() -> String:
	return get_name(NameFormat.PLAIN)


func get_name(format: NameFormat = NameFormat.THE) -> String:
	if self == World.player:
		match format:
			NameFormat.CAPITALIZED:
				return "You"
			NameFormat.THE:
				return "the player"
			_:
				return "you"

	# Alternatively, include the species name. Right now this gives you "the rodent rat" which is a bit redundant.
	# var n := "%s %s" % [Species.get_adjective(species), name]
	var n := name

	match format:
		NameFormat.THE:
			return "the " + n
		NameFormat.AN:
			return ("an " if n[0] in ["a", "e", "i", "o", "u"] else "a ") + n
		NameFormat.PLAIN:
			return n
		NameFormat.CAPITALIZED:
			return "The " + n

	return "the " + n  # Default fallback


# Getters for stats that can be modified by status effects
func get_strength() -> int:
	var strength := _base_strength

	# Apply stim effects
	if has_status_effect(StatusEffect.Type.STIM):
		var stim := get_status_effect(StatusEffect.Type.STIM)
		strength += 3 * stim.magnitude  # +3 STR per magnitude level

	return strength


func get_speed() -> int:
	# Apply encumbrance effects
	if has_status_effect(StatusEffect.Type.OVERTAXED):
		return SPEED_VERY_SLOW  # Severely overloaded
	elif has_status_effect(StatusEffect.Type.BURDENED):
		return SPEED_SLOW  # Moderately overloaded

	# Get base speed
	var speed := _base_speed

	# Apply stim effects
	if has_status_effect(StatusEffect.Type.STIM):
		var stim := get_status_effect(StatusEffect.Type.STIM)
		match stim.magnitude:
			1:
				speed = mini(SPEED_VERY_FAST, speed + 6)  # +6 speed but cap at VERY_FAST
			_:
				speed = SPEED_VERY_FAST  # Higher magnitudes always VERY_FAST
	elif has_status_effect(StatusEffect.Type.STIM_RECOVERY):
		speed = maxi(SPEED_VERY_SLOW, speed - SPEED_SLOW)  # Reduce speed but don't go below VERY_SLOW

	return speed


func get_hp_regen() -> int:
	var regen := _base_hp_regen

	# Apply stim effects
	if has_status_effect(StatusEffect.Type.STIM):
		var stim := get_status_effect(StatusEffect.Type.STIM)
		regen += stim.magnitude  # +1 HP per 3 turns per magnitude level
	elif has_status_effect(StatusEffect.Type.STIM_RECOVERY):
		regen = 0  # Disable HP regen during recovery

	return regen


func get_hover_info() -> String:
	var info := ""

	if self == World.player:
		info += get_name(NameFormat.CAPITALIZED) + "\n"
		info += ("a %s %s\n" % [Species.Type.keys()[species], Roles.Type.keys()[role]]).to_lower()
	else:
		info += get_name(NameFormat.CAPITALIZED) + "\n"

	# Basic stats
	info += (
		"HP: %d/%d - STR: %d - INT: %d - AC: %d\n"
		% [hp, max_hp, get_strength(), intelligence, get_armor_class()]
	)
	info += "Speed: "
	match get_speed():
		SPEED_VERY_SLOW:
			info += "Very Slow"
		SPEED_SLOW:
			info += "Slow"
		SPEED_NORMAL:
			info += "Normal"
		SPEED_FAST:
			info += "Fast"
		SPEED_VERY_FAST:
			info += "Very Fast"
	info += "\n"

	# Behavior and faction info
	info += "Faction: %s\n" % Factions.get_name.call(faction)
	info += "Behavior: "
	match behavior:
		Behavior.PASSIVE:
			info += "Peaceful"
		Behavior.AGGRESSIVE:
			info += "Hostile"
		Behavior.FEARFUL:
			info += "Cowardly"
		Behavior.CURIOUS:
			info += "Inquisitive"

	# Resistances based on species
	info += "\n\nResistances:"
	var resistances := get_resistances()
	if resistances.is_empty():
		info += "\nNone"
	else:
		for damage_type: Damage.Type in resistances:
			info += "\n• %s: %d" % [Damage.Type.keys()[damage_type], resistances[damage_type]]

	# Equipment
	var equipped_items := equipment.get_all_equipped_items()
	if not equipped_items.is_empty():
		info += "\n\nEquipped:"
		for item in equipped_items:
			info += "\n• " + item.get_name()

	# Skills
	var has_skills := false
	for skill_type: Skills.Type in skill_levels:
		if skill_levels[skill_type] > Skills.Level.UNSKILLED:
			if not has_skills:
				info += "\n\nSkills:"
				has_skills = true
			info += (
				"\n• %s: %s"
				% [Skills.Type.keys()[skill_type], Skills.Level.keys()[skill_levels[skill_type]]]
			)

	return info


func get_next_action(map: Map) -> ActorAction:
	next_action = null
	Log.i("Get next action for %s" % self)
	behavior_tree.tick(self, map)
	Log.d("  Next action: %s" % next_action)
	return next_action


func is_adjacent_to(pos1: Vector2i, pos2: Vector2i) -> bool:
	return abs(pos1.x - pos2.x) <= 1 and abs(pos1.y - pos2.y) <= 1


func get_safe_move_direction(map: Map, start: Vector2i, preferred_dir: Vector2i) -> Vector2i:
	return Pathfinding.get_safe_move_direction(map, start, preferred_dir)


func get_next_step_towards_player(
	map: Map, start: Vector2i, target: Vector2i, avoid_monsters: bool = false
) -> Vector2i:
	return Pathfinding.get_next_step(map, start, target, avoid_monsters)


func is_hostile_to(other: Monster) -> bool:
	# If dealing with the player, check their faction affinity
	if other == World.player:
		if hates_player:
			return true

		# Default to hostile if faction affinity isn't defined
		if not faction in World.faction_affinities:
			return true

		var affinity: Variant = World.faction_affinities[faction]
		if affinity is int:
			return affinity < 0
		return true

	# Peaceful monsters are never hostile
	if other.behavior == Behavior.PASSIVE:
		return false

	return Factions.are_hostile(faction, other.faction)


func add_item(item: Item) -> void:
	# If it's already in inventory, do nothing
	if inventory.has(item):
		return

	if item.max_stack_size > 1:
		# Try to find existing stack
		for existing: Item in inventory.to_array():
			if existing.matches(item):
				var space_left := existing.max_stack_size - existing.quantity
				if space_left > 0:
					var amount_to_add := mini(space_left, item.quantity)
					existing.quantity += amount_to_add
					item.quantity -= amount_to_add
					if item.quantity == 0:
						return

	# No existing stack found, stack is full, or item not stackable
	inventory.add(item)


func remove_item(item: Item, quantity: int = 1) -> bool:
	# First check direct inventory
	if inventory.has(item):
		if item.quantity > quantity:
			item.quantity -= quantity
			return true
		else:
			inventory.remove(item)
			equipment.unequip_item(item)
			return true

	# Then check all items in inventory recursively
	for inv_item: Item in inventory.to_array():
		if inv_item.has_child(item):
			if inv_item.remove_child(item):
				equipment.unequip_item(item)
				return true

	return false


func has_item(item: Item) -> bool:
	# First check direct inventory
	if inventory.has(item):
		return true

	# Then check all items in inventory recursively
	for inv_item: Item in inventory.to_array():
		if inv_item.has_child(item):
			return true

	return false


## Unequips and drops all items (used when a monster is killed)
func drop_everything() -> void:
	for item: Item in equipment.get_all_equipped_items():
		equipment.unequip_item(item)

	var pos := World.current_map.find_monster_position(self)
	var items_to_drop: Array = inventory.to_array()
	inventory.clear()

	for item: Item in items_to_drop:
		World.current_map.add_item_with_stacking(pos, item)


func get_armor_class() -> int:
	var total_ac := 0

	# Check each equipment slot
	for item: Item in equipment.get_all_equipped_items():
		# Add base AC from item
		total_ac += item.armor_class

		# Add AC from any attached modules
		for child: Item in item.children.to_array():
			if child:
				total_ac += child.armor_class

	return total_ac


## Returns a dictionary of resistances with the damage type as the key and the number of resistances as the value
func get_resistances() -> Dictionary:
	var resistances := {}

	# Add species resistances
	var species_resistances := Species.get_resistances()
	assert(
		species_resistances.has(species),
		"No resistances defined for species %s" % Species.Type.keys()[species]
	)
	for resistance: Damage.Type in species_resistances[species]:
		if resistance not in resistances:
			resistances[resistance] = 0
		resistances[resistance] += 1

	# Add resistances from equipped items
	for item in equipment.get_all_equipped_items():
		for resistance: Damage.Type in item.resistances:
			if resistance not in resistances:
				resistances[resistance] = 0
			resistances[resistance] += 1

		# Add resistances from any attached modules
		for child: Item in item.children.to_array():
			if child:
				for resistance: Damage.Type in child.resistances:
					if resistance not in resistances:
						resistances[resistance] = 0
					resistances[resistance] += 1

	return resistances


## Returns the skill level for a given skill type
func get_skill_level(skill_type: Skills.Type) -> Skills.Level:
	return skill_levels.get(skill_type, Skills.Level.UNSKILLED)


## Returns the hit bonus for a given skill type
func get_skill_hit_bonus(skill_type: Skills.Type) -> float:
	return Skills.get_hit_bonus(get_skill_level(skill_type))


## Adds a status effect to the monster, removing any existing effect of the same type and adding the new effect
func add_status_effect(type: StatusEffect.Type, magnitude: int = 1) -> void:
	# Check if we already have this effect
	for effect in status_effects:
		if effect.type == type:
			# Update magnitude and duration if higher
			effect.magnitude = maxi(effect.magnitude, magnitude)
			return

	# Add new effect
	var effect := StatusEffect.new(type, magnitude)
	status_effects.append(effect)


## Applies a status effect to the monster, removing any existing effect of the same type and adding the new effect, with special handling for stim
func apply_status_effect(type: StatusEffect.Type, turns: int, magnitude: int = 1) -> void:
	# Remove any existing effect of the same type
	var old_effect: StatusEffect = remove_status_effect(type)

	# If applying stim, remove any stim recovery effects
	if type == StatusEffect.Type.STIM:
		remove_status_effect(StatusEffect.Type.STIM_RECOVERY)

	# Add the new effect
	var effect := StatusEffect.new(type, turns, magnitude)
	status_effects.append(effect)
	Log.d("Applied status effect to %s: %s" % [self, effect])

	# If applying stim, add the original turns to the effect in order to make the withdrawal effect last longer
	if type == StatusEffect.Type.STIM and old_effect:
		effect.original_turns += old_effect.original_turns


func remove_status_effect(type: StatusEffect.Type) -> StatusEffect:
	for i in range(status_effects.size() - 1, -1, -1):
		if status_effects[i].type == type:
			var effect := status_effects[i]
			status_effects.remove_at(i)
			return effect
	return null


func has_status_effect(type: StatusEffect.Type) -> bool:
	for effect in status_effects:
		if effect.type == type:
			return true
	return false


func get_status_effect(type: StatusEffect.Type) -> StatusEffect:
	for effect in status_effects:
		if effect.type == type:
			return effect
	return null


## Update status effects at the start of each turn
func tick_status_effects() -> void:
	# Work on a copy since we'll be modifying the array
	var current_effects := status_effects.duplicate()

	for effect: StatusEffect in current_effects:
		effect.turns_remaining -= 1
		if effect.turns_remaining <= 0:
			status_effects.erase(effect)

			# When stim wears off, apply stim recovery
			if effect.type == StatusEffect.Type.STIM:
				var recovery_turns := int(effect.original_turns / 2.0)
				if recovery_turns > 0:
					apply_status_effect(
						StatusEffect.Type.STIM_RECOVERY, recovery_turns, effect.magnitude
					)
					if self == World.player:
						var adjective := "exhausted" if effect.magnitude == 1 else "very exhausted"
						World.message_logged.emit(
							"The stim wears off. You feel %s." % adjective, LogMessages.Level.BAD
						)

	# Reduce health if poisoned
	if has_status_effect(StatusEffect.Type.POISONED):
		hp = maxi(0, hp - 2)
		if self == World.player:
			World.message_logged.emit("You are poisoned!", LogMessages.Level.TERRIBLE)
		else:
			World.message_logged.emit("%s is poisoned!" % name, LogMessages.Level.BAD)


# Based on NetHack's carrying capacity formula
func get_max_carrying_capacity() -> int:
	var base_capacity := 25 + (get_strength() * 25)

	# Bonus capacity from certain roles
	if role == Roles.Type.KNIGHT:
		base_capacity += 50  # Knights can carry more

	return base_capacity


func get_current_load() -> int:
	var total_mass := 0

	# Add inventory items (using recursive mass calculation)
	for item: Item in inventory.to_array():
		total_mass += int(item.get_mass())

	# Add equipped items (using recursive mass calculation)
	for item in equipment.get_all_equipped_items():
		total_mass += int(item.get_mass())

	return total_mass


func tick_encumbrance() -> void:
	var current_load := get_current_load()
	var max_capacity := get_max_carrying_capacity()

	# Remove existing encumbrance effects
	remove_status_effect(StatusEffect.Type.BURDENED)
	remove_status_effect(StatusEffect.Type.OVERTAXED)

	# Check thresholds and apply effects
	if current_load >= max_capacity * 2:  # Over 200% capacity
		add_status_effect(StatusEffect.Type.OVERTAXED)
	elif current_load >= max_capacity:  # Over 100% capacity
		add_status_effect(StatusEffect.Type.BURDENED)
