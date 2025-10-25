class_name MonsterAI
extends RefCounted

enum BTStatus {
	SUCCESS,
	FAILURE,
	RUNNING,
}


# Base class for all behavior tree nodes
class BTNode:
	extends RefCounted

	func tick(_actor: Monster, _map: Map) -> BTStatus:
		return BTStatus.FAILURE


# Node that explicitly does nothing and always succeeds
class DoNothing:
	extends BTNode

	func tick(_actor: Monster, _map: Map) -> BTStatus:
		Log.d("  DoNothing: Doing nothing")
		return BTStatus.SUCCESS


# Sequence node: Executes children nodes in order until one fails, like a logical AND
class BTSequence:
	extends BTNode
	var children: Array[BTNode]

	func _init(p_children: Array[BTNode] = []) -> void:
		children = p_children

	func tick(actor: Monster, map: Map) -> BTStatus:
		for child in children:
			match child.tick(actor, map):
				BTStatus.FAILURE:
					return BTStatus.FAILURE
				BTStatus.RUNNING:
					# If any child is RUNNING, immediately return RUNNING
					# without executing subsequent children
					return BTStatus.RUNNING
				BTStatus.SUCCESS:
					# Continue to next child only on SUCCESS
					continue
		return BTStatus.SUCCESS


# Selector node: Executes children nodes in order until one succeeds, like a logical OR
class BTSelector:
	extends BTNode
	var children: Array[BTNode]

	func _init(p_children: Array[BTNode] = []) -> void:
		children = p_children

	func tick(actor: Monster, map: Map) -> BTStatus:
		for child in children:
			match child.tick(actor, map):
				BTStatus.SUCCESS:
					return BTStatus.SUCCESS
				BTStatus.RUNNING:
					return BTStatus.RUNNING
		return BTStatus.FAILURE


# Check if the player is visible
class CheckPlayerVisible:
	extends BTNode

	func tick(actor: Monster, map: Map) -> BTStatus:
		var monster_pos := map.find_monster_position(actor)
		var player_pos := map.find_monster_position(World.player)

		if monster_pos == Utils.INVALID_POS or player_pos == Utils.INVALID_POS:
			Log.d("  CheckPlayerVisible: Invalid position")
			return BTStatus.FAILURE

		var distance := (monster_pos - player_pos).length()
		var visible := distance <= 20
		Log.d(
			(
				"  CheckPlayerVisible: Player %s (distance: %.1f)"
				% ["visible" if visible else "not visible", distance]
			)
		)
		return BTStatus.SUCCESS if visible else BTStatus.FAILURE


# Attack the player if they are adjacent
class AttackPlayer:
	extends BTNode

	func tick(actor: Monster, map: Map) -> BTStatus:
		var monster_pos := map.find_monster_position(actor)
		var player_pos := map.find_monster_position(World.player)

		if actor.is_adjacent_to(monster_pos, player_pos):
			var direction := player_pos - monster_pos
			actor.next_action = AttackMoveAction.new(actor, direction)
			Log.d("  AttackPlayer: Attacking player in direction %s" % direction)
			return BTStatus.SUCCESS
		Log.d("  AttackPlayer: Player not adjacent")
		return BTStatus.FAILURE


# Move toward the player
class MoveTowardPlayer:
	extends BTNode

	func tick(actor: Monster, map: Map) -> BTStatus:
		var monster_pos := map.find_monster_position(actor)
		var player_pos := map.find_monster_position(World.player)

		# First try to find a path that avoids other monsters
		var move_dir := actor.get_next_step_towards_player(map, monster_pos, player_pos, true)

		# If no path found avoiding monsters, and we're not adjacent to player,
		# try again allowing paths through monsters as a fallback
		if move_dir == Vector2i.ZERO and not actor.is_adjacent_to(monster_pos, player_pos):
			move_dir = actor.get_next_step_towards_player(map, monster_pos, player_pos, false)

		if move_dir != Vector2i.ZERO:
			actor.next_action = MoveAction.new(actor, move_dir)
			Log.d("  MoveTowardPlayer: Moving toward player in direction %s" % move_dir)
			return BTStatus.SUCCESS
		Log.d("  MoveTowardPlayer: No valid path to player")
		return BTStatus.FAILURE


# Flee from the player
class FleeFromPlayer:
	extends BTNode

	func tick(actor: Monster, map: Map) -> BTStatus:
		var monster_pos := map.find_monster_position(actor)
		var player_pos := map.find_monster_position(World.player)

		var away_dir := Vector2(monster_pos - player_pos).normalized()
		var move_dir := actor.get_safe_move_direction(map, monster_pos, away_dir)
		if move_dir != Vector2i.ZERO:
			actor.next_action = AttackMoveAction.new(actor, move_dir)
			Log.d("  FleeFromPlayer: Fleeing from player in direction %s" % move_dir)
			return BTStatus.SUCCESS
		Log.d("  FleeFromPlayer: No valid escape direction")
		return BTStatus.FAILURE


# Check if monster is hostile to player
class CheckHostileToPlayer:
	extends BTNode

	func tick(actor: Monster, _map: Map) -> BTStatus:
		if actor.is_hostile_to(World.player):
			Log.d("  CheckHostileToPlayer: Monster is hostile")
			return BTStatus.SUCCESS
		Log.d("  CheckHostileToPlayer: Monster is not hostile")
		return BTStatus.FAILURE


# Move randomly
class MoveRandomly:
	extends BTNode

	func tick(actor: Monster, _map: Map) -> BTStatus:
		var move_dir := Utils.ALL_DIRECTIONS.pick_random() as Vector2i
		actor.next_action = AttackMoveAction.new(actor, move_dir)
		Log.d("  MoveRandomly: Moving in random direction %s" % move_dir)
		return BTStatus.SUCCESS


# Check if a random chance succeeds
class CheckRandomChance:
	extends BTNode
	var chance: float

	func _init(p_chance: float) -> void:
		chance = Utils.to_float(p_chance)

	func tick(_actor: Monster, _map: Map) -> BTStatus:
		var success := Dice.chance(chance)
		Log.d("  CheckRandomChance: chance %.2f, success: %s" % [chance, success])
		return BTStatus.SUCCESS if success else BTStatus.FAILURE


# Check if monster has a ranged weapon equipped
class CheckHasRangedWeapon:
	extends BTNode

	func tick(actor: Monster, _map: Map) -> BTStatus:
		var weapon := actor.equipment.get_equipped_item(Equipment.Slot.RANGED)
		if weapon and weapon.is_ranged_weapon():
			Log.d("  CheckHasRangedWeapon: Has ranged weapon %s" % weapon)
			return BTStatus.SUCCESS
		Log.d("  CheckHasRangedWeapon: No ranged weapon")
		return BTStatus.FAILURE


# Check if monster should equip a ranged weapon
class CheckAndEquipRangedWeapon:
	extends BTNode

	func tick(actor: Monster, _map: Map) -> BTStatus:
		# If already has a ranged weapon equipped, we're good
		var equipped_ranged := actor.equipment.get_equipped_item(Equipment.Slot.RANGED)
		if equipped_ranged and equipped_ranged.is_ranged_weapon():
			# Check if weapon needs ammo
			if equipped_ranged.ammo_type != Damage.AmmoType.NONE:
				# Check if weapon already has ammo attached
				var has_ammo := false
				var children: Array = equipped_ranged.children.to_array()
				for child: Item in children:
					if (
						child.type == Item.Type.AMMO
						and child.ammo_type == equipped_ranged.ammo_type
					):
						has_ammo = true
						break

				if has_ammo:
					# Already has ammo attached, we're good
					Log.d("  CheckAndEquipRangedWeapon: Already equipped with ammo")
					return BTStatus.SUCCESS

				# Look for compatible ammo in inventory
				for item: Item in actor.inventory.to_array():
					if (
						item.type == Item.Type.AMMO
						and item.ammo_type == equipped_ranged.ammo_type
						and not item.parent
					):  # Not already attached to something
						# Found compatible ammo, attach it
						equipped_ranged.add_child(item)
						Log.d(
							(
								"  CheckAndEquipRangedWeapon: Attached ammo %s to %s"
								% [item, equipped_ranged]
							)
						)
						return BTStatus.SUCCESS
			else:
				# Weapon doesn't need ammo, we're good
				Log.d("  CheckAndEquipRangedWeapon: Already equipped, no ammo needed")
				return BTStatus.SUCCESS

		# Look for an unequipped ranged weapon in inventory
		for item: Item in actor.inventory.to_array():
			if item.is_ranged_weapon() and not item.parent and item != equipped_ranged:  # Not attached to something else  # Not the one already equipped
				# Found a ranged weapon, equip it
				if equipped_ranged:
					actor.equipment.unequip_item(equipped_ranged)
				actor.equipment.equip(item, Equipment.Slot.RANGED)
				Log.d("  CheckAndEquipRangedWeapon: Equipped ranged weapon %s" % item)

				# If weapon needs ammo, try to find and attach compatible ammo
				if item.ammo_type != Damage.AmmoType.NONE:
					for ammo: Item in actor.inventory.to_array():
						if (
							ammo.type == Item.Type.AMMO
							and ammo.ammo_type == item.ammo_type
							and not ammo.parent
						):  # Not already attached to something
							# Found compatible ammo, attach it
							item.add_child(ammo)
							Log.d(
								"  CheckAndEquipRangedWeapon: Attached ammo %s to %s" % [ammo, item]
							)
							break

				return BTStatus.SUCCESS

		Log.d("  CheckAndEquipRangedWeapon: No suitable ranged weapon or ammo found")
		return BTStatus.FAILURE


# Fire ranged weapon at player if in range
class FireAtPlayer:
	extends BTNode

	func tick(actor: Monster, map: Map) -> BTStatus:
		var monster_pos := map.find_monster_position(actor)
		var player_pos := map.find_monster_position(World.player)
		var distance := monster_pos.distance_to(player_pos)

		# If too far, don't try to shoot
		if distance > 6:
			Log.d("  FireAtPlayer: Player too far (distance: %.1f)" % distance)
			return BTStatus.FAILURE

		# Get the ranged weapon
		var weapon := actor.equipment.get_equipped_item(Equipment.Slot.RANGED)
		if not weapon or not weapon.is_ranged_weapon():
			Log.d("  FireAtPlayer: No ranged weapon equipped")
			return BTStatus.FAILURE

		actor.next_action = FireAction.new(actor, player_pos)
		Log.d("  FireAtPlayer: Firing at player at position %s" % player_pos)
		return BTStatus.SUCCESS


# Check if monster has sufficient intelligence to use weapons
class CheckIntelligentEnough:
	extends BTNode

	func tick(actor: Monster, _map: Map) -> BTStatus:
		if actor.intelligence >= 4:
			Log.d("  CheckIntelligentEnough: Intelligence sufficient (%d)" % actor.intelligence)
			return BTStatus.SUCCESS
		Log.d("  CheckIntelligentEnough: Intelligence too low (%d)" % actor.intelligence)
		return BTStatus.FAILURE


# Check if monster has a melee weapon equipped
class CheckHasMeleeWeapon:
	extends BTNode

	func tick(actor: Monster, _map: Map) -> BTStatus:
		var weapon := actor.equipment.get_equipped_item(Equipment.Slot.MELEE)
		if weapon and weapon.is_weapon() and not weapon.is_ranged_weapon():
			Log.d("  CheckHasMeleeWeapon: Has melee weapon %s" % weapon)
			return BTStatus.SUCCESS
		Log.d("  CheckHasMeleeWeapon: No melee weapon")
		return BTStatus.FAILURE


# Look for nearby melee weapons and remember their location
class FindNearbyMeleeWeapon:
	extends BTNode

	# Store the weapon location so other nodes can use it
	static var weapon_location: Vector2i = Utils.INVALID_POS
	static var weapon_distance: float = 999999.0

	func tick(actor: Monster, map: Map) -> BTStatus:
		var monster_pos := map.find_monster_position(actor)
		var items := map.get_items(monster_pos)

		# Reset stored location
		weapon_location = Utils.INVALID_POS
		weapon_distance = 999999.0

		# First check our current position
		for item in items:
			if item.is_weapon() and not item.is_ranged_weapon():
				Log.d("  FindNearbyMeleeWeapon: Found melee weapon at current position: %s" % item)
				weapon_location = monster_pos
				weapon_distance = 0
				return BTStatus.SUCCESS

		# Then check positions within sight radius
		# Search in a square area around the monster up to sight radius
		for y in range(-actor.sight_radius, actor.sight_radius + 1):
			for x in range(-actor.sight_radius, actor.sight_radius + 1):
				var check_pos := monster_pos + Vector2i(x, y)

				# Skip if out of bounds or not visible
				if not map.is_in_bounds(check_pos) or not map.is_visible(check_pos):
					continue

				# Skip if distance is greater than sight radius (to make it circular)
				var distance := monster_pos.distance_to(check_pos)
				if distance > actor.sight_radius:
					continue

				items = map.get_items(check_pos)
				for item in items:
					if item.is_weapon() and not item.is_ranged_weapon():
						# Found a weapon - track if it's the closest one
						if distance < weapon_distance:
							weapon_distance = distance
							weapon_location = check_pos

		# If we found a weapon, return success
		if weapon_location != Utils.INVALID_POS:
			Log.d(
				(
					"  FindNearbyMeleeWeapon: Found melee weapon at %s (distance: %.1f)"
					% [weapon_location, weapon_distance]
				)
			)
			return BTStatus.SUCCESS

		Log.d("  FindNearbyMeleeWeapon: No nearby melee weapons found")
		return BTStatus.FAILURE


# Move to a weapon's location and pick it up
class MoveToAndPickupWeapon:
	extends BTNode

	func tick(actor: Monster, map: Map) -> BTStatus:
		# Make sure we have a valid weapon location
		if FindNearbyMeleeWeapon.weapon_location == Utils.INVALID_POS:
			Log.d("  MoveToAndPickupWeapon: No weapon location set")
			return BTStatus.FAILURE

		var monster_pos := map.find_monster_position(actor)
		var distance := monster_pos.distance_to(FindNearbyMeleeWeapon.weapon_location)

		# If we're at the weapon location, try to pick it up
		if distance < 0.1:  # Use a small threshold to handle floating point comparison
			var items := map.get_items(monster_pos)
			for item in items:
				if item.is_weapon() and not item.is_ranged_weapon():
					Log.d("  MoveToAndPickupWeapon: Picking up weapon %s" % item)
					actor.next_action = PickupAction.new(actor, [ItemSelection.new(item)])
					# Return RUNNING here so we wait for the pickup to complete
					return BTStatus.RUNNING
			# If we get here, the weapon is no longer here
			FindNearbyMeleeWeapon.weapon_location = Utils.INVALID_POS
			return BTStatus.FAILURE

		# If we're adjacent, move onto it
		if distance <= 1.5:
			var dir := FindNearbyMeleeWeapon.weapon_location - monster_pos
			Log.d(
				(
					"  MoveToAndPickupWeapon: Moving onto weapon at %s"
					% FindNearbyMeleeWeapon.weapon_location
				)
			)
			actor.next_action = MoveAction.new(actor, dir)
			return BTStatus.RUNNING

		# Otherwise pathfind toward it
		var next_pos := actor.get_next_step_towards_player(
			map, monster_pos, FindNearbyMeleeWeapon.weapon_location
		)
		if next_pos != Vector2i.ZERO:
			Log.d(
				(
					"  MoveToAndPickupWeapon: Moving toward weapon at %s"
					% FindNearbyMeleeWeapon.weapon_location
				)
			)
			actor.next_action = MoveAction.new(actor, next_pos)
			return BTStatus.RUNNING

		# If we can't find a path, give up
		FindNearbyMeleeWeapon.weapon_location = Utils.INVALID_POS
		Log.d("  MoveToAndPickupWeapon: Cannot find path to weapon")
		return BTStatus.FAILURE


# Equip a melee weapon from inventory
class EquipMeleeWeapon:
	extends BTNode

	func tick(actor: Monster, _map: Map) -> BTStatus:
		# Check if we already have a melee weapon equipped
		var equipped_melee := actor.equipment.get_equipped_item(Equipment.Slot.MELEE)
		if equipped_melee and equipped_melee.is_weapon() and not equipped_melee.is_ranged_weapon():
			Log.d("  EquipMeleeWeapon: Already have melee weapon equipped")
			return BTStatus.SUCCESS

		# Look for an unequipped melee weapon in inventory
		for item: Item in actor.inventory.to_array():
			if item.is_weapon() and not item.is_ranged_weapon() and not item.parent:
				# Found a melee weapon, equip it
				if equipped_melee:
					actor.equipment.unequip_item(equipped_melee)
				actor.equipment.equip(item, Equipment.Slot.MELEE)
				Log.d("  EquipMeleeWeapon: Equipped melee weapon %s" % item)
				return BTStatus.SUCCESS

		Log.d("  EquipMeleeWeapon: No suitable melee weapon found in inventory")
		return BTStatus.FAILURE


# DSL helper methods for building behavior trees
static func sequence(
	a: Variant,
	b: Variant = null,
	c: Variant = null,
	d: Variant = null,
	e: Variant = null,
	f: Variant = null
) -> BTNode:
	var nodes: Array[Variant] = []
	if a != null:
		nodes.append(a)
	if b != null:
		nodes.append(b)
	if c != null:
		nodes.append(c)
	if d != null:
		nodes.append(d)
	if e != null:
		nodes.append(e)
	if f != null:
		nodes.append(f)
	return BTSequence.new(_convert_to_nodes(nodes))


static func selector(
	a: Variant,
	b: Variant = null,
	c: Variant = null,
	d: Variant = null,
	e: Variant = null,
	f: Variant = null
) -> BTNode:
	var nodes: Array[Variant] = []
	if a != null:
		nodes.append(a)
	if b != null:
		nodes.append(b)
	if c != null:
		nodes.append(c)
	if d != null:
		nodes.append(d)
	if e != null:
		nodes.append(e)
	if f != null:
		nodes.append(f)
	return BTSelector.new(_convert_to_nodes(nodes))


static func _convert_to_nodes(children: Array) -> Array[BTNode]:
	var nodes: Array[BTNode] = []
	for child: Variant in children:
		if child is BTNode:
			nodes.append(child)
		elif child is GDScript:
			nodes.append((child as GDScript).new())
		elif child is Array:
			# Support nested arrays for backward compatibility
			nodes.append_array(_convert_to_nodes(child as Array))
	return nodes


# Create a behavior tree for a monster
static func create_behavior_tree(monster: Monster) -> BTNode:
	match monster.behavior:
		Monster.Behavior.AGGRESSIVE:
			return sequence(
				selector(
					# Try to attack player if visible and hostile
					sequence(
						CheckHostileToPlayer,
						CheckPlayerVisible,
						selector(
							# Try ranged combat first
							sequence(
								CheckAndEquipRangedWeapon,
								CheckHasRangedWeapon,
								selector(
									FireAtPlayer,
									MoveTowardPlayer,
								)
							),
							# Try melee combat with weapon seeking
							sequence(
								CheckIntelligentEnough,
								# First try to get and use a melee weapon
								selector(
									CheckHasMeleeWeapon,  # Already have one equipped
									EquipMeleeWeapon,  # Try to equip from inventory
									# Need to find and get one - this whole sequence must complete
									sequence(
										FindNearbyMeleeWeapon,
										MoveToAndPickupWeapon,
									),
								),
								# Only try combat actions once we have a weapon
								selector(
									AttackPlayer,
									MoveTowardPlayer,
								)
							),
							# Fall back to basic melee combat
							sequence(
								selector(
									AttackPlayer,
									MoveTowardPlayer,
								)
							)
						)
					),
					# If not hostile, move randomly sometimes
					sequence(
						CheckRandomChance.new(0.5),
						MoveRandomly,
					),
					# Otherwise stay still
					DoNothing
				)
			)

		Monster.Behavior.FEARFUL:
			return sequence(
				CheckPlayerVisible,
				FleeFromPlayer,
				# Otherwise stay still
				DoNothing
			)

		Monster.Behavior.CURIOUS:
			return sequence(
				CheckPlayerVisible,
				selector(
					MoveTowardPlayer,
				)
			)

		Monster.Behavior.PASSIVE:
			return sequence(
				selector(
					# 20% chance to move randomly
					sequence(
						CheckRandomChance.new(0.50),
						MoveRandomly,
					),
					# Otherwise stay still
					DoNothing
				)
			)

		_:
			assert(false, "Invalid behavior: %s" % monster.behavior)
			return BTNode.new()
