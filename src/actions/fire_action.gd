class_name FireAction
extends ActorAction

var target_pos: Vector2i


func _init(p_actor: Monster, p_target_pos: Vector2i) -> void:
	super(p_actor)
	target_pos = p_target_pos


func _to_string() -> String:
	return "FireAction(actor: %s, target_pos: %s)" % [actor, target_pos]


func _execute(map: Map, result: ActionResult) -> bool:
	if not super(map, result):
		return false

	# Get the actor's position
	var source_pos := map.find_monster_position(actor)
	if not source_pos:
		Log.e("Actor not found in map: %s" % actor)
		return false

	if actor.has_status_effect(StatusEffect.Type.PARALYZED):
		if actor == World.player:
			result.message = "You are paralyzed and cannot fire!"
			result.message_level = LogMessages.Level.TERRIBLE
		else:
			result.message = "%s tries to fire but is paralyzed!" % actor.name
			result.message_level = LogMessages.Level.BAD
		return true

	# If the actor is confused, pick a random adjacent position
	if actor.has_status_effect(StatusEffect.Type.CONFUSED):
		target_pos = source_pos + Utils.ALL_DIRECTIONS.pick_random()

	# Get the wielded weapon
	var weapon := actor.equipment.get_equipped_item(Equipment.Slot.RANGED)
	if not weapon:
		return false
	if not weapon.is_ranged_weapon():
		return false

	# Does the weapon need ammo?
	var ammo: Item = null
	if weapon.ammo_type != Damage.AmmoType.NONE:
		# Get the ammo from the weapon's children
		var children: Array = weapon.children.to_array()
		for child: Item in children:
			if child.type == Item.Type.AMMO:
				ammo = child
				break

		# If we didn't find any ammo, fail
		if not ammo:
			return false

		# Check if the ammo type matches the weapon's ammo type
		if ammo.ammo_type != weapon.ammo_type:
			return false

		# Check if the ammo is empty
		if ammo.quantity <= 0:
			return false

		# Consume the ammo if it's the player -- monsters cheat!
		if actor == World.player:
			ammo.quantity -= 1

		# If the ammo is now empty, unequip it and remove it from the inventory
		if ammo.quantity <= 0:
			actor.equipment.unequip_item(ammo)
			actor.inventory.remove(ammo)

	# Resolve the ranged attack
	var ranged_result := Combat.resolve_ranged_attack(map, actor, target_pos, weapon, ammo)
	if not ranged_result:
		Log.e("No ranged result for fire action")
		return false

	# Show a miss message if we tried to hit a monster but the projectile went past it
	var distance_to_target := target_pos.distance_to(source_pos)
	var distance_to_hit := ranged_result.hit_pos.distance_to(source_pos)
	if distance_to_hit > distance_to_target:
		var target_monster := map.get_monster(target_pos)
		if target_monster:
			var is_player_attacker := actor == World.player
			var is_player_defender := target_monster == World.player
			var subject := "you" if is_player_attacker else actor.get_name(Monster.NameFormat.THE)
			var object := (
				"you" if is_player_defender else target_monster.get_name(Monster.NameFormat.THE)
			)
			result.message = "%s miss %s!" % [Utils.capitalize_first(subject), object]
			if is_player_defender:
				result.message_level = LogMessages.Level.BAD
		return true

	# Handle hit effects if we hit a monster
	if ranged_result.hit_monster:
		var monster: Monster = ranged_result.hit_monster
		var monster_pos: Vector2i = ranged_result.hit_pos

		result.effects.append(
			ProjectileEffect.new(
				actor, ranged_result.hit_monster, source_pos, monster_pos, ammo if ammo else weapon
			)
		)

		# Add hit effect
		var direction := Vector2(monster_pos - source_pos).normalized()
		var hit_effect := HitEffect.new(
			monster, Vector2(direction), source_pos, actor, ranged_result.damage != 0
		)
		result.add_effect(hit_effect)

		# Add damage popup effect
		if ranged_result.damage != 0:
			var status_effect := StatusPopupEffect.new(
				monster, monster_pos, str(ranged_result.damage)
			)
			result.add_effect(status_effect)

		# Format hit message
		var is_player_attacker := actor == World.player
		var is_player_defender := monster == World.player
		var subject := "you" if is_player_attacker else actor.get_name(Monster.NameFormat.THE)
		var object := "you" if is_player_defender else monster.get_name(Monster.NameFormat.THE)
		var verb := "hit" if is_player_attacker else "hits"

		if ranged_result.killed:
			if is_player_defender:
				result.message = (
					"%s %s %s. You die." % [Utils.capitalize_first(subject), verb, object]
				)
				result.message_level = LogMessages.Level.FATAL
			else:
				result.message = (
					"%s %s %s. %s is killed!"
					% [
						Utils.capitalize_first(subject),
						verb,
						object,
						monster.get_name(Monster.NameFormat.THE).capitalize()
					]
				)
				result.message_level = LogMessages.Level.GOOD
		else:
			result.message = "%s %s %s." % [Utils.capitalize_first(subject), verb, object]
			if is_player_defender:
				result.message_level = LogMessages.Level.BAD

		# Handle death
		if monster.hp <= 0:
			monster.is_dead = true
			if monster != World.player:
				monster.drop_everything()
				World.current_map.find_and_remove_monster(monster)
			result.add_effect(DeathEffect.new(monster, target_pos, actor == World.player))

	# Add projectile effect for non-monster hits
	elif ranged_result.hit_obstacle or ranged_result.hit_terrain:
		result.effects.append(
			ProjectileEffect.new(
				actor, null, source_pos, ranged_result.hit_pos, ammo if ammo else weapon
			)
		)

		# Format hit message for obstacles/terrain
		var is_player_attacker := actor == World.player
		var subject := "you" if is_player_attacker else actor.get_name(Monster.NameFormat.THE)
		var verb := "hit" if is_player_attacker else "hits"
		var object: String
		if ranged_result.hit_obstacle:
			object = ranged_result.hit_obstacle.get_name(Obstacle.NameFormat.THE)
		else:
			object = ranged_result.hit_terrain.get_name(Terrain.NameFormat.THE)
		result.message = "%s %s %s." % [Utils.capitalize_first(subject), verb, object]

	return true
