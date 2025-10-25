extends Node2D

# Game is the main scene and is responsible for initializing the World, reading
# user input, rendering the map, and displaying effects.

var fast_mode: bool = true
var effects_queue: Array[ActionEffect] = []
var waiting_for_player_input: bool = false
var _last_mouse_tile_pos: Vector2i = Utils.INVALID_POS
var _throw_selection: Variant = null  # Track item being thrown

@onready var map_renderer: MapRenderer = %MapRenderer
@onready var actors: Node2D = %Actors
@onready var hud: HUD = %HUD
@onready var hit_effect_rect: ColorRect = %HitEffect
@onready var reticle: Reticle = %Reticle


func _ready() -> void:
	# Connect to World signals
	World.map_changed.connect(_on_map_changed)
	World.effect_occurred.connect(_on_effect)
	World.turn_started.connect(_on_turn_started)
	World.game_ended.connect(_on_game_over)

	# Initialize the world and other elements
	_initialize()

	# Start waiting for player input
	waiting_for_player_input = true

	# Hide the hit effect rect
	hit_effect_rect.visible = false

	# Hook up inventory signals
	Modals.inventory_opened.connect(
		func(inventory: InventoryModal) -> void:
			inventory.pickup_requested.connect(
				func(selections: Variant) -> void:
					var array := ItemSelection._from_selections(selections)
					_handle_player_action(PlayerPickupAction.new(array))
			)
			inventory.drop_requested.connect(
				func(selections: Variant) -> void:
					var array := ItemSelection._from_selections(selections)
					_handle_player_action(PlayerDropAction.new(array))
			)
			inventory.equip_requested.connect(
				func(action: PlayerEquipAction) -> void: _handle_player_action(action)
			)
			inventory.unequip_requested.connect(
				func(action: PlayerUnequipAction) -> void: _handle_player_action(action)
			)
			inventory.throw_requested.connect(
				func(selections: Variant) -> void:
					_throw_selection = ItemSelection._from_selections(selections)
			)
			inventory.use_requested.connect(
				func(item: Item) -> void:
					var action := PlayerUseItemAction.new(item)
					_handle_player_action(action)
			)
			inventory.reparent_requested.connect(
				func(action: PlayerReparentItemAction) -> void: _handle_player_action(action)
			)
			inventory.toggle_container_requested.connect(
				func(item: Item) -> void:
					var action := PlayerToggleContainerAction.new(item)
					_handle_player_action(action)
			)
			inventory.message_logged.connect(
				func(message: String) -> void: World.message_logged.emit(message)
			)
	)

	# Hook up HUD signals
	hud.drop_requested.connect(
		func(selections: Variant) -> void:
			var array := ItemSelection._from_selections(selections)
			_handle_player_action(PlayerDropAction.new(array))
	)


func _initialize() -> void:
	# Clear the effects queue
	effects_queue.clear()

	# Initialize the world
	World.initialize()

	# Update actors
	_update_actors()


func _process(_delta: float) -> void:
	# Update reticle position
	_update_reticle()

	# Update hud throw info
	hud.throw_info.visible = _throw_selection is Array[ItemSelection]


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_tree().change_scene_to_file("res://scenes/ui/quit.tscn")


func _on_effect(effect: ActionEffect) -> void:
	effects_queue.append(effect)


func _on_map_changed(map: Map) -> void:
	map_renderer.render_map(map)


func _on_turn_started() -> void:
	# Clear any existing status popups and wait for them to be freed
	var any_popup_destroyed: bool = false
	for actor: Actor in actors.get_children():
		if actor.popup and is_instance_valid(actor.popup):
			actor.popup.destroy()
			actor.popup = null
			any_popup_destroyed = true
	if any_popup_destroyed:
		await get_tree().process_frame


func _on_game_over() -> void:
	# Render the map
	map_renderer.render_map(World.current_map)

	# Update actors
	_update_actors()

	# Display the game over screen
	await get_tree().create_timer(1).timeout
	Modals.show_game_over()


func _unhandled_input(event: InputEvent) -> void:
	if Modals.has_visible_modals():
		if event.is_action_pressed("attack_move_to_location"):
			get_viewport().set_input_as_handled()
			Modals.hide_inventory()
		return

	if World.game_over or not hud.updates_enabled:
		return

	if not waiting_for_player_input:
		return

	# Handle throw targeting
	if _throw_selection is Array[ItemSelection]:
		if event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			_throw_selection = null
			hud.throw_info.visible = true
			return

		if (
			event.is_action_pressed("attack_move_to_location")
			or event.is_action_pressed("fire_at_location")
		):
			var mouse_pos := get_local_mouse_position()
			var tile_pos := Vector2i(mouse_pos / Constants.TILE_SIZE)

			if World.current_map.is_in_bounds(tile_pos):
				var terrain := World.current_map.get_terrain(tile_pos)
				if terrain.type != Terrain.Type.EMPTY:
					get_viewport().set_input_as_handled()
					var throw_action := PlayerThrowAction.new(
						_throw_selection as Array[ItemSelection], tile_pos
					)
					_throw_selection = null
					waiting_for_player_input = false
					_handle_player_action(throw_action)
					return
		# Don't return here - let other input handling continue if we didn't throw

	if event.is_action_pressed("attack_move_to_location"):
		var mouse_pos := get_local_mouse_position()
		var tile_pos := Vector2i(mouse_pos / Constants.TILE_SIZE)

		if World.current_map.is_in_bounds(tile_pos):
			var terrain := World.current_map.get_terrain(tile_pos)
			if terrain.type != Terrain.Type.EMPTY:
				get_viewport().set_input_as_handled()
				_on_tile_attack_move(tile_pos)

	elif event.is_action_pressed("fire_at_location"):
		var mouse_pos := get_local_mouse_position()
		var tile_pos := Vector2i(mouse_pos / Constants.TILE_SIZE)

		if World.current_map.is_in_bounds(tile_pos):
			var terrain := World.current_map.get_terrain(tile_pos)
			if terrain.type != Terrain.Type.EMPTY:
				get_viewport().set_input_as_handled()
				_on_tile_fire_at(tile_pos)

	elif event.is_action_pressed("toggle_debug"):
		hud.debug_mode = not hud.debug_mode

	var action := await _check_player_input()
	if action:
		waiting_for_player_input = false
		_handle_player_action(action)


func _check_player_input() -> BaseAction:
	if Input.is_action_just_pressed("toggle_inventory"):
		get_viewport().set_input_as_handled()
		Modals.toggle_inventory(InventoryModal.Tab.INVENTORY)
		return null

	if Input.is_action_just_pressed("toggle_equipment"):
		get_viewport().set_input_as_handled()
		Modals.toggle_inventory(InventoryModal.Tab.EQUIPMENT)
		return null

	if Input.is_action_just_pressed("rest"):
		get_viewport().set_input_as_handled()
		return PlayerRestAction.new()

	if Input.is_action_just_pressed("pick_up_item"):
		get_viewport().set_input_as_handled()
		var pos := World.current_map.find_monster_position(World.player)
		var items := World.current_map.get_items(pos)
		var selections: Array[ItemSelection] = []
		for item in items:
			selections.append(ItemSelection.new(item, item.quantity))
		return PlayerPickupAction.new(selections)

	if Input.is_action_just_pressed("move_up"):
		get_viewport().set_input_as_handled()
		return PlayerAttackMoveAction.new(Vector2i.UP)

	if Input.is_action_just_pressed("move_down"):
		get_viewport().set_input_as_handled()
		return PlayerAttackMoveAction.new(Vector2i.DOWN)

	if Input.is_action_just_pressed("move_left"):
		get_viewport().set_input_as_handled()
		return PlayerAttackMoveAction.new(Vector2i.LEFT)

	if Input.is_action_just_pressed("move_right"):
		get_viewport().set_input_as_handled()
		return PlayerAttackMoveAction.new(Vector2i.RIGHT)

	if Input.is_action_just_pressed("move_up_left"):
		get_viewport().set_input_as_handled()
		return PlayerAttackMoveAction.new(Vector2i.UP + Vector2i.LEFT)

	if Input.is_action_just_pressed("move_up_right"):
		get_viewport().set_input_as_handled()
		return PlayerAttackMoveAction.new(Vector2i.UP + Vector2i.RIGHT)

	if Input.is_action_just_pressed("move_down_left"):
		get_viewport().set_input_as_handled()
		return PlayerAttackMoveAction.new(Vector2i.DOWN + Vector2i.LEFT)

	if Input.is_action_just_pressed("move_down_right"):
		get_viewport().set_input_as_handled()
		return PlayerAttackMoveAction.new(Vector2i.DOWN + Vector2i.RIGHT)

	# Add explicit stair movement checks
	if Input.is_action_just_pressed("move_upstairs"):
		get_viewport().set_input_as_handled()
		return PlayerMoveUpstairsAction.new()

	if Input.is_action_just_pressed("move_downstairs"):
		get_viewport().set_input_as_handled()
		return PlayerMoveDownstairsAction.new()

	if Input.is_action_just_pressed("open"):
		get_viewport().set_input_as_handled()
		var direction := await Modals.prompt_for_direction()
		if direction != Vector3i.ZERO:  # Check if not cancelled
			return PlayerOpenAction.new(Vector2i(direction.x, direction.y))

	if Input.is_action_just_pressed("close"):
		get_viewport().set_input_as_handled()
		var direction := await Modals.prompt_for_direction()
		if direction != Vector3i.ZERO:  # Check if not cancelled
			return PlayerCloseAction.new(Vector2i(direction.x, direction.y))

	return null


func _handle_player_action(action: BaseAction) -> void:
	Log.i("Player action: %s" % action)

	# Apply the action
	World.apply_player_action(action)

	# Apply any status effect effects
	_render_status_effects()

	# Display the effects
	await _flush_effects_queue()

	# Render the map
	map_renderer.render_map(World.current_map)

	# Update actors
	_update_actors()

	# Ready for next input
	waiting_for_player_input = true


func _update_actors() -> void:
	# First, mark all existing actors for potential removal
	var actors_to_remove: Dictionary = {}
	for actor: Actor in actors.get_children():
		actors_to_remove[actor.monster] = actor

	# Get all visible monsters from the map
	var visible_monsters := World.current_map.get_visible_monsters()

	# Update or create actors for each visible monster
	for monster in visible_monsters:
		var actor: Actor = actors_to_remove.get(monster)
		if actor:
			# Actor exists, update position if needed
			var pos := World.current_map.find_monster_position(monster)
			if actor.grid_pos != pos:
				actor.move_to(pos)
			# Remove from the to-remove list since we're keeping it
			actors_to_remove.erase(monster)
		else:
			# Create new actor
			actor = preload("res://scenes/actor/actor.tscn").instantiate()
			actor.monster = monster
			actor.init(World.current_map.find_monster_position(monster))
			actors.add_child(actor)

			if monster == World.player:
				actor.add_to_group("player")

		# Make sure the actor is visible
		actor.visible = true

	# Remove actors that are no longer visible
	for actor: Actor in actors_to_remove.values():
		actor.queue_free()

	# Update the last mouse position to reset the reticle and path
	_last_mouse_tile_pos = Utils.INVALID_POS


func _get_effect_priority(effect: ActionEffect) -> int:
	# Lower numbers = higher priority
	if effect is MoveEffect:
		return 0  # Movement effects should happen first
	elif effect is ProjectileEffect:
		return 1  # Projectiles before their impacts
	elif effect is ThrownItemEffect:
		return 2  # Thrown items before their impacts
	elif effect is AttackEffect:
		return 3  # Attack animations before hits
	elif effect is HitEffect:
		return 4  # Hit effects after attacks
	elif effect is PushActorEffect:
		return 5
	elif effect is PushObstacleEffect:
		return 6
	elif effect is AreaOfEffectDamageEffect:
		return 7
	elif effect is DeathEffect:
		return 8  # Death effects should be last
	elif effect is StatusPopupEffect:
		return 9  # Status popups last
	return 100  # Unknown effects get lowest priority


func _render_status_effects() -> void:
	for actor: Actor in actors.get_children():
		if actor.monster.has_status_effect(StatusEffect.Type.POISONED):
			var monster_pos := World.current_map.find_monster_position(actor.monster)
			effects_queue.append(
				StatusPopupEffect.new(actor.monster, monster_pos, "Poisoned", GameColors.GREEN)
			)


func _flush_effects_queue() -> void:
	# Sort effects by priority
	effects_queue.sort_custom(
		func(a: ActionEffect, b: ActionEffect) -> bool:
			return _get_effect_priority(a) < _get_effect_priority(b)
	)

	# First handle player movement effects
	for effect in effects_queue:
		if not _is_effect_visible(effect):
			continue

		if effect is MoveEffect and effect.target == World.player:
			var callable := _get_effect_callable(effect)
			await callable.call()

	# Split into fire effects and other effects
	var projectile_effects: Array[Callable] = []
	var non_player_effects: Array[Callable] = []

	# Then handle all fire effects in parallel
	for effect in effects_queue:
		if not _is_effect_visible(effect):
			continue

		var callable := _get_effect_callable(effect)
		if effect is ProjectileEffect:
			projectile_effects.append(callable)

	if projectile_effects.size() > 0:
		Log.d("Waiting for %s fire effects" % projectile_effects.size())
		await Async.await_all(projectile_effects)

	# Then handle remaining effects
	for effect in effects_queue:
		if not _is_effect_visible(effect) or effect is ProjectileEffect:
			continue
		if effect is MoveEffect and effect.target == World.player:
			continue

		var callable := _get_effect_callable(effect)
		if effect is ProjectileEffect:
			continue
		elif effect.involves_player() and not World.player.is_dead and not fast_mode:
			Log.d("Calling effect %s" % effect)
			await callable.call()
		else:
			non_player_effects.append(callable)

	# Wait for all non-player effects to complete
	Log.d("Waiting for %s non-player effects" % non_player_effects.size())
	if non_player_effects.size() > 0:
		await Async.await_all(non_player_effects)

	effects_queue.clear()


func _get_effect_callable(effect: ActionEffect) -> Callable:
	return func() -> void:
		if effect is AttackEffect:
			await _handle_attack_effect(effect as AttackEffect)
		elif effect is HitEffect:
			await _handle_hit_effect(effect as HitEffect)
		elif effect is MoveEffect:
			await _handle_move_effect(effect as MoveEffect)
		elif effect is DeathEffect:
			await _handle_death_effect(effect as DeathEffect)
		elif effect is PushActorEffect:
			await _handle_push_actor_effect(effect as PushActorEffect)
		elif effect is PushObstacleEffect:
			await _handle_push_obstacle_effect(effect as PushObstacleEffect)
		elif effect is StatusPopupEffect:
			_handle_status_popup_effect(effect as StatusPopupEffect)
		elif effect is ProjectileEffect:
			await _handle_projectile_effect(effect as ProjectileEffect)
		elif effect is ThrownItemEffect:
			await _handle_thrown_item_effect(effect as ThrownItemEffect)
		elif effect is AreaOfEffectDamageEffect:
			await _handle_aoe_effect(effect as AreaOfEffectDamageEffect)
		else:
			Log.e("Unknown effect type: %s" % effect)


func _handle_attack_effect(effect: AttackEffect) -> void:
	var actor := _find_actor_for_monster(effect.target)
	if actor:
		var direction := effect.direction * -1
		await actor.trigger_attack_effect(direction)


func _handle_hit_effect(effect: HitEffect) -> void:
	var actor := _find_actor_for_monster(effect.target)
	if effect.target == World.player:
		flash_hit_effect()
	if actor:
		var direction := effect.direction
		await actor.trigger_hit_effect(direction)

		# Add stain with 75% chance at the hit location
		if effect.took_damage and randf() < 0.75:
			var target_pos := World.current_map.find_monster_position(effect.target)
			var frame := randi() % 6  # Choose random frame from 0-5
			var cell := World.current_map.get_cell(target_pos)
			cell.stain_color = effect.target.hit_particles_color
			cell.stain_frame = frame
			cell.stain_lifetime = Dice.roll(1, 20) + 90  # Stains last 91-110 turns


func _handle_move_effect(effect: MoveEffect) -> void:
	var actor := _find_actor_for_monster(effect.target)
	if actor:
		await actor.move_to(effect.to)


func _handle_death_effect(effect: DeathEffect) -> void:
	var actor := _find_actor_for_monster(effect.target)
	if actor:
		await actor.trigger_death_effect()
		# Only remove non-player monsters after death animation
		if effect.target != World.player:
			World.current_map.find_and_remove_monster(effect.target)


func _handle_push_actor_effect(effect: PushActorEffect) -> void:
	var actor := _find_actor_for_monster(effect.target)
	if actor:
		actor.set_facing_direction(effect.direction)
		await actor.trigger_attack_effect(effect.direction)


func _handle_push_obstacle_effect(effect: PushObstacleEffect) -> void:
	await _animate_obstacle_push(effect.from, effect.to)


func _handle_status_popup_effect(effect: StatusPopupEffect) -> void:
	var actor := _find_actor_for_monster(effect.target)
	if actor:
		if actor.popup and is_instance_valid(actor.popup):
			actor.popup.append(effect.text, effect.color)
		else:
			actor.popup = preload("res://scenes/fx/status_popup.tscn").instantiate()
			actor.popup.position = Vector2(Constants.TILE_SIZE / 2.0, 0)
			actor.add_child(actor.popup)
			actor.popup.show_popup(effect.text, effect.color)


func _handle_projectile_effect(effect: ProjectileEffect) -> void:
	await VisualEffects.animate_projectile(
		self, effect.start_pos, effect.end_pos, effect.source_item
	)
	await VisualEffects.create_explosion(self, effect.end_pos, false, effect.source_item)


func _handle_thrown_item_effect(effect: ThrownItemEffect) -> void:
	await VisualEffects.animate_projectile(
		self, effect.start_pos, effect.end_pos, effect.item, true
	)

	# Apply an AoE effect if this was a grenade or similar item
	var result := Combat.resolve_thrown_item(
		World.current_map, effect.source, effect.end_pos, effect.item
	)

	# Only show explosion and apply AOE if this isn't a delayed grenade
	if (
		result.aoe_type != null
		and not (effect.item.type == Item.Type.GRENADE and effect.item.turns_to_activate > 0)
	):
		await VisualEffects.create_explosion(self, effect.end_pos, true)
		# Apply the area effect
		World.current_map.apply_aoe(
			effect.end_pos, result.aoe_radius, result.aoe_type, result.aoe_damage, result.aoe_turns
		)


func _handle_aoe_effect(effect: AreaOfEffectDamageEffect) -> void:
	var actor := _find_actor_for_monster(effect.target)
	if effect.target == World.player:
		flash_hit_effect()
	if actor:
		# Show hit effect in random direction for area damage
		var angle := randf() * PI * 2
		var direction := Vector2.from_angle(angle)
		await actor.trigger_hit_effect(direction)


func _is_effect_visible(effect: ActionEffect) -> bool:
	if effect is PushObstacleEffect:
		var push_effect := effect as PushObstacleEffect
		return (
			World.current_map.is_visible(push_effect.from)
			or World.current_map.is_visible(push_effect.to)
		)
	elif effect.location != Utils.INVALID_POS:
		return World.current_map.is_visible(effect.location)
	return false


func _find_actor_for_monster(monster: Monster) -> Actor:
	for actor: Actor in actors.get_children():
		if actor.monster == monster:
			return actor
	return null


func _animate_obstacle_push(from_pos: Vector2i, to_pos: Vector2i) -> Signal:
	# Remove the obstacle tile from the source position
	map_renderer.obstacle_layer.erase_cell(from_pos)

	# Create a temporary sprite for animation
	var sprite := Sprite2D.new()
	sprite.texture = WorldTiles.TEXTURE
	sprite.centered = false

	# Get the obstacle tile coordinates from the renderer
	var obstacle := World.current_map.get_obstacle(from_pos)
	if not obstacle:
		# If no obstacle found at the source position, try the target position
		obstacle = World.current_map.get_obstacle(to_pos)

	if not obstacle:
		Log.e("No obstacle found at either source or target position")
		return get_tree().create_timer(0.0).timeout  # Return an immediately finished signal

	var tile := map_renderer.get_obstacle_tile(obstacle)
	var tile_coords := WorldTiles.get_coords(tile)

	# Set up the sprite region to match the tile
	sprite.region_enabled = true
	sprite.region_rect = Rect2(
		tile_coords.x * Constants.TILE_SIZE,
		tile_coords.y * Constants.TILE_SIZE,
		Constants.TILE_SIZE,
		Constants.TILE_SIZE
	)

	# Position the sprite and add it to the scene
	sprite.position = Vector2(from_pos * Constants.TILE_SIZE)
	add_child(sprite)

	# Create tween for smooth movement
	var tween := create_tween()
	tween.tween_property(sprite, "position", Vector2(to_pos * Constants.TILE_SIZE), 0.15).set_trans(
		Tween.TRANS_SINE
	)

	# Create a signal for the entire sequence
	var sig := tween.finished
	sig.connect(
		func() -> void:
			sprite.queue_free()
			map_renderer.render_obstacles(World.current_map)
	)
	return sig


func flash_hit_effect() -> void:
	hit_effect_rect.visible = true

	var tween := create_tween()
	tween.set_parallel(true)

	var hit_effect_material := hit_effect_rect.material as ShaderMaterial
	hit_effect_material.set_shader_parameter("vignette_opacity", 1.0)

	tween.tween_property(hit_effect_material, "shader_parameter/vignette_opacity", 0.0, 0.3)

	# Hide when done using
	tween.finished.connect(func() -> void: hit_effect_rect.visible = false)


func _update_reticle() -> void:
	if not _should_show_reticle():
		_hide_reticle()
		return

	var mouse_pos := get_local_mouse_position()
	var tile_pos := Vector2i(mouse_pos / Constants.TILE_SIZE)

	if not World.current_map.is_in_bounds(tile_pos):
		_hide_reticle()
		return

	var terrain := World.current_map.get_terrain(tile_pos)
	if terrain.type == Terrain.Type.EMPTY:
		_hide_reticle()
		return

	_update_reticle_display(tile_pos)


func _should_show_reticle() -> bool:
	return not (World.game_over or Modals.has_visible_modals())


func _hide_reticle() -> void:
	reticle.visible = false
	hud.set_hover_info(null)
	_last_mouse_tile_pos = Utils.INVALID_POS


func _update_reticle_display(tile_pos: Vector2i) -> void:
	# Note: You'll need to set the reticle size to 16x16 in the editor
	reticle.visible = true
	reticle.position = Vector2(tile_pos * Constants.TILE_SIZE) + Constants.HALF_TILE_SIZE_VEC2

	var is_tile_visible := World.current_map.is_visible(tile_pos)
	var is_tile_seen := World.current_map.was_seen(tile_pos)
	var hover_info := _get_hover_info(tile_pos, is_tile_visible, is_tile_seen)

	if hover_info:
		reticle.modulate = hover_info.color
		reticle.modulate.a = 1.0
		reticle.pulse = hover_info.pulse
		hud.set_hover_info(hover_info.text)
	else:
		_hide_reticle()

	if _should_draw_path(tile_pos, is_tile_visible):
		_draw_path_preview(tile_pos)
	else:
		_clear_path_preview()

	_last_mouse_tile_pos = tile_pos


func _get_hover_info(tile_pos: Vector2i, p_is_visible: bool, is_seen: bool) -> Dictionary:
	var monster := World.current_map.get_monster(tile_pos)
	var obstacle := World.current_map.get_obstacle(tile_pos)
	var items := World.current_map.get_items(tile_pos)
	var terrain := World.current_map.get_terrain(tile_pos)
	var cell := World.current_map.get_cell(tile_pos)

	if monster == World.player:
		var text := monster.get_hover_info()
		if not cell.area_effects.is_empty():
			text += "\n[color=red]" + _get_area_effects_text(cell.area_effects) + "[/color]"
		return {"color": GameColors.GREEN, "pulse": true, "text": text}
	elif p_is_visible and monster:
		var text := monster.get_hover_info()
		if not cell.area_effects.is_empty():
			text += "\n[color=red]" + _get_area_effects_text(cell.area_effects) + "[/color]"
		return {
			"color": GameColors.RED if monster.is_hostile_to(World.player) else GameColors.GREEN,
			"pulse": true,
			"text": text
		}
	elif p_is_visible and items.size() > 0:
		var text := Item.get_item_summary(items)
		if not cell.area_effects.is_empty():
			text += "\n[color=red]" + _get_area_effects_text(cell.area_effects) + "[/color]"
		return {"color": GameColors.CYAN, "pulse": true, "text": text}
	elif p_is_visible and obstacle:
		var text := obstacle.get_hover_info()
		if not cell.area_effects.is_empty():
			text += "\n[color=red]" + _get_area_effects_text(cell.area_effects) + "[/color]"
		return {"color": GameColors.WHITE, "pulse": false, "text": text}
	elif is_seen:
		var text := terrain.get_hover_info()
		if not cell.area_effects.is_empty():
			text += "\n[color=red]" + _get_area_effects_text(cell.area_effects) + "[/color]"
		return {"color": GameColors.WHITE, "pulse": false, "text": text}

	return {}


func _get_area_effects_text(effects: Array[MapCell.AreaEffect]) -> String:
	var text := ""
	for effect in effects:
		match effect.type:
			Damage.Type.POISON:
				text += "Poison Gas"
			Damage.Type.FIRE:
				text += "Burning"
			Damage.Type.COLD:
				text += "Freezing"
			_:
				text += "Unknown Effect"
		text += " (%d turns)" % effect.turns_remaining
		if effect != effects[-1]:
			text += ", "
	return text


func _should_draw_path(tile_pos: Vector2i, p_is_visible: bool) -> bool:
	if not p_is_visible:
		return false

	var monster := World.current_map.get_monster(tile_pos)
	if monster and monster.is_hostile_to(World.player):
		return true

	return _throw_selection != null


func _clear_path_preview() -> void:
	for child in map_renderer.highlight_layer.get_children():
		child.queue_free()


func _draw_path_preview(tile_pos: Vector2i) -> void:
	_clear_path_preview()

	var player_pos := World.current_map.find_monster_position(World.player)
	var path := Utils.calculate_trajectory(player_pos, tile_pos)

	for pos in path:
		if pos == player_pos:
			continue

		var rect := ColorRect.new()
		rect.size = Vector2(Constants.TILE_SIZE, Constants.TILE_SIZE)
		rect.position = Vector2(pos * Constants.TILE_SIZE)

		if World.current_map.get_monster(pos):
			rect.color = Color(1, 0, 0, 0.4)  # Red
		elif World.current_map.get_obstacle(pos):
			rect.color = Color(1, 1, 0, 0.4)  # Yellow
		else:
			rect.color = Color(1, 1, 1, 0.2)  # White

		map_renderer.highlight_layer.add_child(rect)


func _on_tile_attack_move(tile_pos: Vector2i) -> void:
	# Check if the tile is visible
	var is_tile_visible := World.current_map.is_visible(tile_pos)
	var is_tile_seen := World.current_map.was_seen(tile_pos)
	if not is_tile_visible and not is_tile_seen:
		return

	# Get player's current position
	var player_pos := World.current_map.find_monster_position(World.player)

	# Check for visible hostile monsters
	var visible_monsters := World.current_map.get_visible_monsters()
	var hostile_visible := false
	for visible_monster in visible_monsters:
		if visible_monster != World.player and visible_monster.is_hostile_to(World.player):
			hostile_visible = true
			break

	# Check if clicked on player's position and there are stairs
	if tile_pos == player_pos:
		var obstacle := World.current_map.get_obstacle(tile_pos)
		if obstacle:
			if obstacle.type == Obstacle.Type.STAIRS_UP:
				var action := PlayerMoveUpstairsAction.new()
				waiting_for_player_input = false
				_handle_player_action(action)
				return
			elif obstacle.type == Obstacle.Type.STAIRS_DOWN:
				var action := PlayerMoveDownstairsAction.new()
				waiting_for_player_input = false
				_handle_player_action(action)
				return

		# Uncomment to show inventory when clicking on a tile with items
		# var items := World.current_map.get_items(tile_pos)
		# if not items.is_empty():
		# 	Modals.show_inventory(InventoryModal.Tab.GROUND)
		# 	return
		# Modals.show_inventory(InventoryModal.Tab.EQUIPMENT)
		# return

	# Get path to target
	var path := _find_path_to_target(World.current_map, player_pos, tile_pos)
	if path.is_empty():
		return

	# If there are hostile monsters visible, only move one step
	# Otherwise, execute the full path
	if hostile_visible:
		var next_step := path[0] - player_pos
		var action := PlayerAttackMoveAction.new(next_step)
		waiting_for_player_input = false
		_handle_player_action(action)
	else:
		_execute_movement_path(path)


func _find_path_to_target(map: Map, start: Vector2i, target: Vector2i) -> Array[Vector2i]:
	return Pathfinding.find_path(map, start, target)


func _execute_movement_path(path: Array[Vector2i]) -> void:
	if path.size() < 1:
		return

	hud.updates_enabled = false

	var player_pos := World.current_map.find_monster_position(World.player)
	var next_pos := path[0]
	var move_dir := next_pos - player_pos

	# Check if the next position has a closed door
	var obstacle := World.current_map.get_obstacle(next_pos)
	if obstacle and obstacle.type == Obstacle.Type.DOOR_CLOSED:
		# Try to open the door first
		var open_action := PlayerOpenAction.new(move_dir)
		waiting_for_player_input = false
		_handle_player_action(open_action)
		# Don't continue the path - let the player's next input handle movement
		hud.updates_enabled = true
		return

	var action := PlayerAttackMoveAction.new(move_dir)
	waiting_for_player_input = false
	_handle_player_action(action)

	# Queue up the next movement after a short delay
	if path.size() > 1:
		await get_tree().create_timer(0.1).timeout
		# Check if we should continue (no hostiles appeared)
		var visible_monsters := World.current_map.get_visible_monsters()
		for monster in visible_monsters:
			if monster != World.player and monster.is_hostile_to(World.player):
				hud.updates_enabled = true
				return
		# Remove the first position and continue with the rest
		path.remove_at(0)
		_execute_movement_path(path)
	else:
		hud.updates_enabled = true


func _on_tile_fire_at(tile_pos: Vector2i) -> void:
	# Check if the tile is visible
	var is_tile_visible := World.current_map.is_visible(tile_pos)
	if not is_tile_visible:
		return

	# Create and handle the fire action
	var action := PlayerFireAction.new(tile_pos)
	waiting_for_player_input = false
	_handle_player_action(action)
