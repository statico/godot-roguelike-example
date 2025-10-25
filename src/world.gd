extends Node

const ESCAPE_LEVEL = "_exit"

# World is a main global singleton that holds the game state and handles
# mutations. Eventually it should be serializable and loadable from a save file.

signal world_initialized
signal map_changed(map: Map)
signal effect_occurred(effect: ActionEffect)
signal message_logged(message: String, level: int)
signal turn_started
signal turn_ended
signal game_ended
signal energy_updated(monster: Monster)

# Like NetHack, we world_plan the dungeon in advance, but levels are only created when
# they are first visited.
var world_plan: WorldPlan

# Always keep a reference to the player
var player: Monster

# Keep track of generated maps
var maps: Dictionary  # Map[id] -> Map
var current_map: Map

# Turn management
var current_turn: int

# Is the game over?
var game_over: bool = false

# Keep track of the max depth reached
var max_depth: int = 1

# The player's faction affinity
var faction_affinities: Dictionary = {
	Factions.Type.HUMAN: 100,  # There could be different human factions with different affinities
	Factions.Type.CRITTERS: -30,  # Somewhat hostile. Maybe add taming?
	Factions.Type.MONSTERS: -100,  # Initially hostile but can improve
	Factions.Type.UNDEAD: -100,  # Initially hostile but can improve
}


func _init() -> void:
	Log.i("===========================")
	Log.i("= Godot Roguelike Example =")
	Log.i("===========================")
	Log.i("")


func _ready() -> void:
	initialize()


func initialize() -> void:
	Log.i("Initializing world...")

	# Initialize all vars
	current_turn = 1
	game_over = false
	max_depth = 1

	# Create a new world world_plan
	world_plan = WorldPlan.new(WorldPlan.WorldType.NORMAL)
	Log.i("World world_plan created: %s" % world_plan)

	# Create the player with starting equipment
	# TODO: Choose role based at main menu
	player = MonsterFactory.create_monster(&"knight", Roles.Type.KNIGHT)
	Roles.equip_monster(player, Roles.Type.KNIGHT)
	Log.i("Player created: %s" % player)

	# Create the first level
	maps.clear()
	var plan := world_plan.get_first_level_plan()
	var map := _generate_map(plan)
	maps[map.id] = map
	current_map = map

	# Add the player to the main entrance
	assert(
		map.add_monster_at_stairs(player, Obstacle.Type.STAIRS_UP),
		"Failed to add player to main entrance"
	)

	# Compute FOV before the first turn
	update_vision()

	# Signal that the world is ready
	map_changed.emit(current_map)
	world_initialized.emit()


func _generate_map(plan: WorldPlan.LevelPlan) -> Map:
	match plan.type:
		WorldPlan.LevelType.ARENA:
			var generator := MapGeneratorFactory.create_generator(
				MapGeneratorFactory.GeneratorType.ARENA
			)
			return (
				generator
				. generate_map(
					20,
					15,
					{
						"depth": plan.depth,
					}
				)
			)

		WorldPlan.LevelType.DUNGEON:
			var generator := MapGeneratorFactory.create_generator(
				MapGeneratorFactory.GeneratorType.DUNGEON
			)
			return (
				generator
				. generate_map(
					30,
					20,
					{
						# Dungeon generation parameters
						"min_room_size": 5,
						"max_room_size": 9,
						"size_variation": 0.6,
						"room_placement_attempts": 500,
						"target_room_count": 30,
						"border_buffer": 3,
						"room_expansion_chance": 0.5,
						"max_expansion_attempts": 3,
						"horizontal_expansion_bias": 0.5,
						# Level parameters
						"depth": plan.depth,
						"has_up_stairs": plan.up_destination != "",
						"has_down_stairs": plan.down_destination != "",
						"has_amulet": plan.has_amulet
					}
				)
			)

		_:
			Log.e("Unsupported level type: %s" % plan.type)
			assert(false)
			return null


# Apply an action (presumably from the player) to the world and complete the turn.
func apply_player_action(action: BaseAction) -> ActionResult:
	Log.i("[color=lime]======== TURN %d STARTED ========[/color]" % World.current_turn)
	turn_started.emit()

	# Apply the player's action
	Log.i("Applying action: %s" % action)
	var result := action.apply(current_map)
	if not result:
		Log.i("[color=gray]==== TURN CANCELLED (Action Failed) ====[/color]")
		return null

	# If the action failed, return early without advancing the turn
	if not result.success:
		if result.message:
			message_logged.emit(result.message)
		Log.i("[color=gray]==== TURN CANCELLED (Result False) ====[/color]")
		return result

	# Update all monster systems
	for monster in current_map.get_monsters():
		# Update status effects
		monster.tick_status_effects()

		# Check encumbrance
		monster.tick_encumbrance()

	# Process player nutrition
	var nutrition_cost := 1 + result.extra_nutrition_consumed
	var nutrition_result := player.nutrition.decrease(nutrition_cost)
	if nutrition_result.message:
		message_logged.emit(nutrition_result.message, LogMessages.Level.BAD)
	if nutrition_result.died:
		player.is_dead = true
		effect_occurred.emit(
			DeathEffect.new(player, current_map.find_monster_position(player), true)
		)
		game_over = true
		game_ended.emit()
		return result

	# Process natural healing
	if player.nutrition.value >= Nutrition.THRESHOLD_STARVING and player.hp < player.max_hp:
		# Base healing of 1 HP every 3 turns
		if current_turn % 3 == 0:
			var heal_amount := 1
			# Bonus healing when well fed
			if player.nutrition.value >= Nutrition.THRESHOLD_SATIATED:
				heal_amount += 1
			player.hp = mini(player.hp + heal_amount, player.max_hp)

	# Accumulate energy for all monsters
	for monster in current_map.get_monsters():
		monster.energy += monster.get_speed()

	# Build a list of results from the action
	var results: Array[ActionResult] = [result]

	# Give turns to monsters that have enough energy
	var monsters := current_map.get_monsters()
	Log.d("Checking %d monsters for turns" % monsters.size())
	for monster in monsters:
		if monster == player:
			continue

		# Only act if we have enough energy
		if monster.energy >= Monster.SPEED_NORMAL:
			var monster_action := monster.get_next_action(current_map)
			if monster_action:
				var monster_result := monster_action.apply(current_map)
				results.append(monster_result)
			# Consume energy after acting
			monster.energy -= Monster.SPEED_NORMAL
			energy_updated.emit(monster)

	# Update area effects
	update_area_effects()

	# Update vision
	update_vision()

	# Now emit all the results
	for res in results:
		# Emit effects
		for effect in res.effects:
			effect_occurred.emit(effect)

		# Emit messages
		if res.message:
			message_logged.emit(res.message, res.message_level)

	# Emit turn ended signal
	Log.i("[color=lime]-------- TURN %d ENDED --------[/color]" % World.current_turn)
	turn_ended.emit()

	# Mark the turn as over
	current_turn += 1

	# Is the player dead?
	if player.is_dead:
		game_over = true
		game_ended.emit()

	return result


func handle_special_level(id: String) -> void:
	match id:
		ESCAPE_LEVEL:
			# Request confirmation before letting the player leave
			var confirmed: Variant = await Modals.confirm(
				"Confirm Escape",
				"Are you sure you want to leave the dungeon? This will end your adventure."
			)
			if confirmed:
				current_map.find_and_remove_monster(player)
				message_logged.emit("[color=cyan]You have escaped the dungeon.[/color]")
				game_ended.emit()


func handle_level_transition(destination_level: String, coming_from_stairs: Obstacle.Type) -> void:
	# Get the level plan for the destination
	var plan := world_plan.get_level_plan(destination_level)
	if not plan:
		Log.e("No level plan found for %s" % destination_level)
		return

	# Generate or load the next level
	if not maps.has(destination_level):
		var map := _generate_map(plan)
		map.id = destination_level
		maps[destination_level] = map

	# Remove player from current map
	current_map.find_and_remove_monster(player)

	# Switch to the new map
	current_map = maps[destination_level]
	max_depth = maxi(max_depth, current_map.depth)

	# Add player at appropriate entrance based on which stairs they used
	var target_stairs_type := (
		Obstacle.Type.STAIRS_DOWN
		if coming_from_stairs == Obstacle.Type.STAIRS_UP
		else Obstacle.Type.STAIRS_UP
	)
	assert(
		current_map.add_monster_at_stairs(player, target_stairs_type),
		"Failed to add player at stairs"
	)

	# Update FOV for new position
	var player_pos := current_map.find_monster_position(player)
	current_map.compute_fov(player_pos)

	# Signal that the map has changed
	map_changed.emit(current_map)


## Updates all area effects and applies their damage
func update_area_effects() -> void:
	var messages: Array[String] = []

	for x in range(current_map.width):
		for y in range(current_map.height):
			var cell := current_map.get_cell(Vector2i(x, y))
			var pos := Vector2i(x, y)

			# Check for armed grenades and handle their countdown
			for item in cell.items:
				if item.type == Item.Type.GRENADE and item.is_armed:
					item.turns_to_activate -= 1
					if item.turns_to_activate <= 0:
						# Remove the grenade from the map
						current_map.remove_item(pos, item)
						# Apply the grenade's area effect
						if item.aoe_config:
							current_map.apply_aoe(
								pos,
								item.aoe_config.radius,
								item.aoe_config.type,
								item.damage,
								item.aoe_config.turns
							)
							messages.append("%s explodes!" % item.get_name(Item.NameFormat.THE))
							# Create visual explosion effect
							await VisualEffects.create_explosion(
								get_tree().current_scene, pos, true
							)
						else:
							Log.e("Armed grenade has no AOE config: %s" % item)

	# Apply damage from each effect *after* the grenades have exploded
	for x in range(current_map.width):
		for y in range(current_map.height):
			var cell := current_map.get_cell(Vector2i(x, y))
			var pos := Vector2i(x, y)

			# Apply damage from each effect
			for effect in cell.area_effects:
				if cell.monster:
					var monster: Monster = cell.monster
					var result := Combat.resolve_aoe_damage(monster, effect.damage, effect.type)
					if result.killed:
						monster.is_dead = true
						if monster != player:
							messages.append(
								"%s is killed!" % monster.get_name(Monster.NameFormat.THE)
							)
							effect_occurred.emit(DeathEffect.new(monster, pos, monster == player))
							monster.drop_everything()
			# Update effect durations
			cell.update_effects()

	# Log all messages at once
	for msg in messages:
		message_logged.emit(msg)


func update_vision() -> void:
	var player_pos := current_map.find_monster_position(player)
	if player.has_status_effect(StatusEffect.Type.BLIND):
		current_map.clear_fov(player_pos)
	else:
		current_map.compute_fov(player_pos)
