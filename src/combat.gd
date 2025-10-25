class_name Combat
extends RefCounted


## Returns the damage after applying the damage reduction
static func _calculate_damage_reduction(
	damage_type: Damage.Type, resistance: int, damage: int
) -> int:
	if damage_type in [Damage.Type.POISON]:
		# Things like poison aren't physical damage
		return 0
	else:
		return max(0, damage - resistance)



class MeleeAttackResult:
	extends RefCounted

	var damage: int = 0
	var damage_type: Damage.Type = Damage.Type.BLUNT
	var killed: bool = false
	var missed: bool = false

	func _to_string() -> String:
		return (
			"MeleeAttackResult(damage=%d, killed=%s, missed=%s)"
			% [
				damage,
				killed,
				missed,
			]
		)


## Handles a melee interaction between an attacker and defender
## Returns a MeleeAttackResult containing damage dealt and any special effects
static func resolve_melee_attack(attacker: Monster, defender: Monster) -> MeleeAttackResult:
	var attacker_name := attacker.get_name(Monster.NameFormat.THE)
	var defender_name := defender.get_name(Monster.NameFormat.THE)
	var item := attacker.equipment.get_equipped_item(Equipment.Slot.MELEE)
	Log.i("Resolving melee attack from %s to %s with %s" % [attacker_name, defender_name, item])

	var result := MeleeAttackResult.new()

	# 1. Attack roll
	var attack_roll := Dice.roll(1, 20)

	var to_hit_bonus := 0
	var attacker_strength := attacker.get_strength()
	if attacker_strength <= 5:
		to_hit_bonus = -2
	elif attacker_strength <= 7:
		to_hit_bonus = -1
	elif attacker_strength <= 16:
		to_hit_bonus = 0
	elif attacker_strength <= 20:
		to_hit_bonus = 1
	elif attacker_strength <= 29:
		to_hit_bonus = 2
	else:
		to_hit_bonus = 3

	# Add skill bonus
	var skill_bonus := 0
	if item:
		var skill_hit_bonus := attacker.get_skill_hit_bonus(item.skill_type)
		skill_bonus = int(20.0 * skill_hit_bonus)  # Convert percentage to bonus (e.g. 20% -> +4)
		Log.d("    Skill bonus from %s: %d" % [Skills.Type.keys()[item.skill_type], skill_bonus])

	# TODO: dexterity
	# TODO: equipment enhancement bonuses

	var target_ac := defender.get_armor_class()

	var is_hit := attack_roll + to_hit_bonus + skill_bonus >= target_ac

	var params := [
		attack_roll,
		to_hit_bonus,
		skill_bonus,
		target_ac,
		is_hit,
	]
	Log.d("  1. Attack roll: %d + %d + %d >= %d -> %s" % params)

	if not is_hit:
		Log.d("    Missed")
		_show_popup(attacker, "Miss")
		result.missed = true
		return result

	# 2. Calculate base damage
	Log.d("    Equipped item: %s" % item)
	var base_damage := Dice.roll(item.damage[0], item.damage[1]) if item else 1

	var damage_type := item.damage_types.pick_random() as Damage.Type if item else Damage.Type.BLUNT
	Log.d("    Damage type: %s" % Damage.Type.keys()[damage_type])

	var modifier := 0
	if attacker_strength <= 5:
		modifier = -1
	elif attacker_strength <= 15:
		modifier = 0
	elif attacker_strength <= 17:
		modifier = 1
	elif attacker_strength <= 20:
		modifier = 2
	elif attacker_strength <= 23:
		modifier = 3
	elif attacker_strength <= 26:
		modifier = 5
	elif attacker_strength <= 29:
		modifier = 5
	else:
		modifier = 6

	var damage := base_damage + modifier

	params = [
		Dice.format(item.damage[0], item.damage[1]) if item else "null",
		base_damage,
		modifier,
		damage,
	]
	Log.d("  2. Base damage: (%s -> %d) + %d = %d" % params)

	# TODO: weapon enchantment
	# TODO: role bonus
	# TODO: monster class vulnerability

	# 3. Critical hit
	# TODO: items with immediate death, like vorpal blade
	Log.d("  3. Critical hits efects: TODO")

	# 4. Damage reductions
	Log.d("  4. Damage reductions:")

	# TODO: Shield absorption system

	# Check resistances
	if damage > 0:
		var resistances := defender.get_resistances()
		if damage_type in resistances:
			var resistance: int = resistances[damage_type]
			Log.d("    %s resistance: %d" % [Damage.Type.keys()[damage_type], resistance])
			_show_popup(defender, "Resist")
			damage = _calculate_damage_reduction(damage_type, resistance, damage)
			Log.d("    Damage after reduction: %d" % damage)

	# 5. Apply damage
	result.damage = damage
	Log.d("  5. Damage applied: %d" % damage)

	_show_popup(defender, damage)

	# 6. Check for death
	if defender.hp <= result.damage:
		result.killed = true
		Log.d("  6. %s is killed" % defender)

	Log.d("  Result: %s" % result)
	return result


## Shows a popup for a monster
static func _show_popup(monster: Monster, damage: Variant) -> void:
	var defender_pos := World.current_map.find_monster_position(monster)
	var popup_text: String
	if damage is int:
		if damage != 0:
			popup_text = str(damage as int)
	elif damage:
		popup_text = str(damage)
	if popup_text:
		var popup := StatusPopupEffect.new(monster, defender_pos, popup_text)
		World.effect_occurred.emit(popup)


## Format combat message
static func format_melee_attack_message(
	attacker: Monster, defender: Monster, result: MeleeAttackResult
) -> String:
	var is_player_attacker := attacker == World.player
	var is_player_defender := defender == World.player

	var subject := "you" if is_player_attacker else attacker.get_name(Monster.NameFormat.THE)
	var object := "you" if is_player_defender else defender.get_name(Monster.NameFormat.THE)
	var verb := "hit" if is_player_attacker else "hits"

	if result.missed:
		if is_player_attacker:
			return "You miss."
		return "%s misses." % Utils.capitalize_first(subject)

	var message := "%s %s %s." % [Utils.capitalize_first(subject), verb, object]

	if result.killed:
		if is_player_defender:
			message += " You die."
		else:
			message += " %s is killed!" % Utils.capitalize_first(defender.get_name(Monster.NameFormat.THE))

	return message


class RangedAttackResult:
	extends RefCounted

	var hit_pos: Vector2i = Utils.INVALID_POS
	var hit_monster: Monster = null
	var hit_obstacle: Obstacle = null
	var hit_terrain: Terrain = null
	var damage: int = 0
	var damage_type: Damage.Type = Damage.Type.BLUNT
	var killed: bool = false


## Handles a ranged attack between an attacker and target
## Returns a RangedAttackResult containing damage dealt and any special effects
static func resolve_ranged_attack(
	map: Map, attacker: Monster, target_pos: Vector2i, weapon: Item, ammo: Item
) -> RangedAttackResult:
	var source_pos := map.find_monster_position(attacker)
	Log.i("Resolving ranged attack from %s to %s" % [source_pos, target_pos])

	var result := RangedAttackResult.new()

	# Calculate end position
	# TODO: bullet drop
	const MAX_DISTANCE := 20
	var angle := Vector2(target_pos - source_pos).angle()
	Log.i("  Angle: %.2f rad - %.2f deg " % [angle, angle * 180 / PI])
	var end_pos := Vector2i(Vector2(source_pos) + Vector2.RIGHT.rotated(angle) * MAX_DISTANCE)
	Log.i("  End position: %s" % end_pos)

	# Calculate trajectory
	var trajectory := Utils.calculate_trajectory(source_pos, end_pos)
	if trajectory.is_empty():
		Log.e("No trajectory from %s to %s" % [source_pos, end_pos])
		return null

	# Calculate damage
	var damage_roll := 0
	var bonus := weapon.enhancement
	if weapon.ammo_type:
		Log.i("  Calculating damage from ammo %s" % ammo)
		if not ammo:
			Log.e("  Weapon %s needs ammo but got null" % weapon)
			return null
		damage_roll = Dice.roll(ammo.damage[0], ammo.damage[1])
		result.damage_type = ammo.damage_types.pick_random()
	else:
		Log.i("  Calculating damage from weapon %s" % weapon)
		if ammo:
			Log.e("  Weapon %s does not need ammo but got %s" % [weapon, ammo])
			return null
		damage_roll = Dice.roll(weapon.damage[0], weapon.damage[1])
		result.damage_type = weapon.damage_types.pick_random()

	result.damage = damage_roll + bonus
	Log.i(
		(
			"    Damage: %d + %d = %d %s"
			% [damage_roll, bonus, result.damage, Damage.Type.keys()[result.damage_type]]
		)
	)

	# Check for hits along trajectory
	for pos in trajectory:
		# Skip the source position
		if pos == source_pos:
			continue

		# Check for monster hit
		var monster := map.get_monster(pos)
		if monster:
			Log.i("  Monster %s found at %s" % [monster, pos])

			# Calculate hit chance based on distance and skill
			var distance := source_pos.distance_to(pos)
			var base_hit_chance := 100.0
			if distance <= 10:
				base_hit_chance = 100.0 - (distance * 1.5)  # 1.5% per tile up to 15% at 10 tiles
			else:
				var remaining_distance := distance - 10
				var remaining_penalty := remaining_distance * (25.0 / (MAX_DISTANCE - 10))  # Scale remaining 25% over remaining distance
				base_hit_chance = 85.0 - remaining_penalty  # Start at 85% (after -15% from first 10 tiles)

			# Apply skill bonus
			var skill_bonus := attacker.get_skill_hit_bonus(weapon.skill_type)
			var hit_chance := base_hit_chance * (1.0 + skill_bonus)  # e.g. 80% * (1 + 0.2) = 96% for Expert
			Log.i(
				(
					"    Base hit chance: %.2f%% + skill bonus %.2f%% = %.2f%%"
					% [base_hit_chance, skill_bonus * 100, hit_chance]
				)
			)
			var is_hit := Dice.chance(hit_chance)

			if is_hit:
				Log.i("    Monster %s hit!" % monster)
				result.hit_pos = pos
				result.hit_monster = monster
				break
			else:
				Log.i("    Monster %s missed!" % monster)

		# Check for obstacle hit
		var obstacle := map.get_obstacle(pos)
		if obstacle:
			Log.i("  Obstacle %s found at %s" % [obstacle, pos])

			# Calculate hit chance based on obstacle height
			var hit_chance := 0.0
			match obstacle.get_height():
				Obstacle.Height.NONE:
					hit_chance = 0.0  # Can't hit something with no height
				Obstacle.Height.LOW:
					hit_chance = 25.0  # Low obstacles are harder to hit
				Obstacle.Height.MEDIUM:
					hit_chance = 50.0  # Medium obstacles have average hit chance
				Obstacle.Height.HIGH:
					hit_chance = 75.0  # High obstacles are easier to hit
				Obstacle.Height.FULL:
					hit_chance = 100.0  # Full height obstacles always get hit

			Log.i("    Hit chance based on height: %.2f%%" % hit_chance)
			var roll := randf() * 100.0
			var is_hit := roll <= hit_chance
			Log.i("    Rolled %.2f vs %.2f: %s" % [roll, hit_chance, "HIT" if is_hit else "MISS"])

			if is_hit:
				Log.i("    Obstacle %s hit!" % obstacle)
				result.hit_pos = pos
				result.hit_obstacle = obstacle
				break
			else:
				Log.i("    Obstacle %s missed!" % obstacle)

		# Check for wall hit
		if not map.get_cell(pos).is_walkable():
			Log.i("  Wall found at %s" % pos)
			result.hit_pos = pos
			result.hit_terrain = map.get_cell(pos).terrain
			break

	# Apply damage to whatever was hit
	if result.hit_monster:
		Log.d("  Monster %s hit!" % result.hit_monster)

		# 1. Calculate base damage
		var damage := result.damage
		Log.d("    Base damage: %d" % damage)

		# # 2. First check shield absorption
		# var shield_result := _handle_shield_absorption(
		# 	result.damage_type, damage, result.hit_monster
		# )
		# damage = shield_result.damage

		# 3. Calculate damage reduction from resistances
		var resistances := result.hit_monster.get_resistances()
		if result.damage_type in resistances:
			var resistance: int = resistances[result.damage_type]
			(
				Log
				. d(
					(
						"    %s resistance: %d"
						% [
							Damage.Type.keys()[result.damage_type],
							resistance,
						]
					)
				)
			)
			_show_popup(result.hit_monster, "Resist")
			damage = _calculate_damage_reduction(result.damage_type, resistance, damage)
			Log.d("    Damage after reduction: %d" % damage)
		else:
			Log.d("    No resistance for %s" % Damage.Type.keys()[result.damage_type])

		# 4. Apply damage
		Log.d("    Applying damage: %d" % damage)
		result.hit_monster.hp = max(0, result.hit_monster.hp - damage)
		if result.hit_monster.hp <= 0:
			Log.d("      %s is killed" % result.hit_monster)
			result.killed = true

	elif result.hit_obstacle:
		Log.d("  Obstacle %s hit!" % result.hit_obstacle)
		# TODO: obstacle damage
		pass
	elif result.hit_terrain:
		Log.d("  Terrain %s hit!" % result.hit_terrain)
		# TODO: terrain damage
		pass

	return result


class ThrownItemResult:
	extends RefCounted

	var end_pos: Vector2i
	var hit_monster: Monster
	var hit_obstacle: Obstacle
	var hit_terrain: Terrain
	var item: Item
	var aoe_type: Damage.Type  # Type of area effect damage
	var aoe_radius: int  # Radius of effect in cells
	var aoe_turns: int  # How many turns effect persists
	var aoe_damage: Array[int]  # Damage dice (e.g. [1,10] for 1d10)

	func _to_string() -> String:
		return (
			"ThrownItemResult(end_pos=%s, hit_monster=%s, hit_obstacle=%s, hit_terrain=%s, aoe=%s:%d:%d)"
			% [
				end_pos,
				hit_monster,
				hit_obstacle,
				hit_terrain,
				Damage.Type.keys()[aoe_type] if aoe_type != null else "none",
				aoe_radius,
				aoe_turns
			]
		)


## Handles a thrown item between a thrower and target
## Returns a ThrownItemResult containing the item and any special effects
static func resolve_thrown_item(
	map: Map, thrower: Monster, target_pos: Vector2i, item: Item
) -> ThrownItemResult:
	Log.i("Resolving thrown item from %s to %s" % [thrower, target_pos])
	var result := ThrownItemResult.new()
	result.item = item

	# Calculate max throw distance based on strength and throwing skill
	var base_distance := maxi(5, thrower.get_strength())
	var skill_bonus := thrower.get_skill_hit_bonus(Skills.Type.THROWING)
	var max_distance := int(base_distance * (1.0 + skill_bonus))  # e.g. distance 10 * (1 + 0.2) = 12 for Expert
	Log.i(
		(
			"  Max distance: %d (base: %d, skill bonus: %.1f%%)"
			% [max_distance, base_distance, skill_bonus * 100]
		)
	)

	var source_pos := map.find_monster_position(thrower)
	if source_pos == Utils.INVALID_POS:
		Log.e("Failed to find source position for thrower %s" % thrower)
		return result

	# Calculate trajectory points
	var points := Utils.calculate_trajectory(source_pos, target_pos)
	# Limit points to max distance
	points = points.slice(0, max_distance + 1)
	Log.i("  Trajectory points: %s" % [points])

	# Chance to deviate based on throwing skill
	var deviation_chance := 0.25 * (1.0 - skill_bonus)  # e.g. 25% * (1 - 0.2) = 20% for Expert
	if Dice.chance(deviation_chance):
		var deviation := Dice.roll(1, 3) - 2
		var target_idx := points.find(target_pos)
		if target_idx != -1:
			target_idx = clampi(target_idx + deviation, 0, points.size() - 1)
			target_pos = points[target_idx]
			Log.i(
				(
					"  Adjusted target position: %s (deviation chance: %.1f%%)"
					% [target_pos, deviation_chance * 100]
				)
			)

	# Check each point along trajectory
	for pos in points:
		if pos == source_pos:
			continue

		# Chance to hit a monster based on throwing skill
		var monster := map.get_monster(pos)
		if monster and monster != thrower:
			var hit_chance := 0.1 * (1.0 + skill_bonus)  # e.g. 10% * (1 + 0.2) = 12% for Expert
			if Dice.chance(hit_chance):
				Log.i(
					"  Hit monster %s at %s (hit chance: %.1f%%)" % [monster, pos, hit_chance * 100]
				)
				result.hit_monster = monster
				result.end_pos = pos
				break

		# Chance to hit an obstacle based on its size and throwing skill
		var obstacle := map.get_obstacle(pos)
		if obstacle:
			var base_hit_chance := 0.15  # Base 15% chance
			match obstacle.get_height():
				Obstacle.Height.NONE:
					base_hit_chance = 0.0
				Obstacle.Height.LOW:
					base_hit_chance = 0.1
				Obstacle.Height.MEDIUM:
					base_hit_chance = 0.4
				Obstacle.Height.HIGH:
					base_hit_chance = 0.8
				Obstacle.Height.FULL:
					base_hit_chance = 1.0

			# Reduce chance to hit obstacles based on throwing skill
			var hit_chance := base_hit_chance * (1.0 - (skill_bonus * 0.5))  # Skilled throwers are better at avoiding obstacles
			if Dice.chance(hit_chance):
				Log.i(
					(
						"  Hit obstacle %s at %s (hit chance: %.1f%%)"
						% [obstacle, pos, hit_chance * 100]
					)
				)
				result.hit_obstacle = obstacle
				result.end_pos = pos
				break

		# Stop at target position or if we hit something
		if pos == target_pos or not map.get_cell(pos).is_walkable():
			Log.i("  Final position %s at %s" % [map.get_cell(pos).terrain, pos])
			result.end_pos = pos
			result.hit_terrain = map.get_cell(pos).terrain
			break

	# Add area of effect data if item has it
	if item.aoe_config:
		# Only add AOE data if this isn't a delayed grenade
		if not (item.type == Item.Type.GRENADE and item.turns_to_activate > 0):
			result.aoe_type = item.aoe_config.type
			result.aoe_radius = item.aoe_config.radius
			result.aoe_turns = item.aoe_config.turns
			result.aoe_damage = item.damage

	Log.i("  Result: %s" % result)
	return result


class AreaOfEffectDamageResult:
	extends RefCounted

	var hit_monster: Monster = null
	var damage: int = 0
	var damage_type: Damage.Type = Damage.Type.BLUNT
	var killed: bool = false


## Resolves area effect damage for a single monster
static func resolve_aoe_damage(
	monster: Monster, damage_tuple: Array[int], damage_type: Damage.Type
) -> AreaOfEffectDamageResult:
	Log.i("Resolving area effect damage for %s" % monster)
	var result := AreaOfEffectDamageResult.new()
	result.hit_monster = monster

	var damage := Dice.roll(damage_tuple[0], damage_tuple[1])
	Log.d("  Damage: %d type %s" % [damage, Damage.type_to_string(damage_type)])

	var resistances := monster.get_resistances()
	if damage_type in resistances:
		_show_popup(monster, "Resist")
		var resistance: int = resistances[damage_type]
		Log.d("  Resistance to %s: %d" % [Damage.type_to_string(damage_type), resistance])
		damage = _calculate_damage_reduction(damage_type, resistance, damage)
		Log.d("  Damage after reduction: %d" % damage)

	if damage > 0:
		result.damage = damage
		result.damage_type = damage_type
		monster.hp = max(0, monster.hp - damage)
		_show_popup(monster, damage)
		if monster.hp <= 0:
			Log.d("    %s is killed" % monster)
			result.killed = true

	Log.d("  Result: %s" % result)
	return result
