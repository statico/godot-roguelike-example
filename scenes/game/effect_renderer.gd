class_name EffectRenderer
extends Node

# =============================================================
# 🎬 [EffectRenderer] 액션 이펙트 큐 처리 및 시각 효과 출력
# =============================================================
# game.gd 에서 분리된 이펙트 전담 모듈.
# game.gd 는 effect_occurred 시그널을 enqueue() 로 전달하고,
# 플레이어 액션 처리 후 flush() 를 await 한다.
# =============================================================

var effects_queue: Array[ActionEffect] = []
var fast_mode: bool = true

var _scene_root: Node2D    # Game Node2D — add_child / VisualEffects 에 필요
var _actors: Node2D        # %Actors 컨테이너
var _map_renderer: MapRenderer
var _hit_effect_rect: ColorRect


func setup(
	p_scene_root: Node2D,
	p_actors: Node2D,
	p_map_renderer: MapRenderer,
	p_hit_rect: ColorRect
) -> void:
	_scene_root   = p_scene_root
	_actors       = p_actors
	_map_renderer = p_map_renderer
	_hit_effect_rect = p_hit_rect


func enqueue(effect: ActionEffect) -> void:
	effects_queue.append(effect)


# 독성 상태이상 팝업을 큐에 추가 (턴 시작 전 호출)
func enqueue_status_effects() -> void:
	for actor: Actor in _actors.get_children():
		if actor.monster.has_status_effect(StatusEffect.Type.POISONED):
			var pos := World.current_map.find_monster_position(actor.monster)
			effects_queue.append(
				StatusPopupEffect.new(actor.monster, pos, "Poisoned", GameColors.GREEN)
			)


func flush() -> void:
	effects_queue.sort_custom(func(a: ActionEffect, b: ActionEffect) -> bool:
		return _get_priority(a) < _get_priority(b)
	)

	# ── 1. 플레이어 이동 (동반자 교환은 병렬) ──────────────────
	var handled_swaps: Array[MoveEffect] = []
	for effect in effects_queue:
		if not _is_visible(effect):
			continue
		if effect is MoveEffect and effect.target == World.player:
			var swap: MoveEffect = null
			for other in effects_queue:
				if other is MoveEffect and other != effect and other.target != World.player:
					if other.from == effect.to and other.to == effect.from:
						swap = other
						break
			var fn := _get_callable(effect)
			if swap:
				Log.i("[EffectRenderer] Swap: player ↔ %s" % swap.target.name)
				await Async.await_all([fn, _get_callable(swap)])
				handled_swaps.append(swap)
			else:
				await fn.call()

	# ── 2. 투사체 (병렬) ───────────────────────────────────────
	var projectiles: Array[Callable] = []
	for effect in effects_queue:
		if _is_visible(effect) and effect is ProjectileEffect:
			projectiles.append(_get_callable(effect))
	if not projectiles.is_empty():
		await Async.await_all(projectiles)

	# ── 3. 나머지 (대상별로 직렬, 대상끼리는 병렬) ────────────
	var by_target: Dictionary = {}
	for effect in effects_queue:
		if not _is_visible(effect) or effect is ProjectileEffect:
			continue
		if effect is MoveEffect and (effect.target == World.player or effect in handled_swaps):
			continue
		var fn := _get_callable(effect)
		if effect.involves_player() and not World.player.is_dead and not fast_mode:
			await fn.call()
		else:
			var key: Variant = effect.target if effect.target != null else effect
			if not by_target.has(key):
				by_target[key] = []
			by_target[key].append(fn)

	var parallel: Array[Callable] = []
	for key in by_target:
		var seq: Array = by_target[key]
		parallel.append(func() -> void:
			for fn in seq:
				await fn.call()
		)
	if not parallel.is_empty():
		await Async.await_all(parallel)

	effects_queue.clear()


func flash_hit_effect() -> void:
	_hit_effect_rect.visible = true
	var tween := _scene_root.create_tween()
	tween.set_parallel(true)
	var mat := _hit_effect_rect.material as ShaderMaterial
	mat.set_shader_parameter("vignette_opacity", 1.0)
	tween.tween_property(mat, "shader_parameter/vignette_opacity", 0.0, 0.3)
	tween.finished.connect(func() -> void: _hit_effect_rect.visible = false)


func find_actor(monster: Monster) -> Actor:
	for actor: Actor in _actors.get_children():
		if actor.monster == monster:
			return actor
	return null


# =============================================================
# 🔒 내부 유틸
# =============================================================

func _get_priority(effect: ActionEffect) -> int:
	if effect is MoveEffect:                  return 0
	elif effect is ProjectileEffect:          return 1
	elif effect is ThrownItemEffect:          return 2
	elif effect is AttackEffect:              return 3
	elif effect is HitEffect:                 return 4
	elif effect is PushActorEffect:           return 5
	elif effect is PushObstacleEffect:        return 6
	elif effect is AreaOfEffectDamageEffect:  return 7
	elif effect is DeathEffect:               return 8
	elif effect is StatusPopupEffect:         return 9
	return 100


func _is_visible(effect: ActionEffect) -> bool:
	if effect is PushObstacleEffect:
		var e := effect as PushObstacleEffect
		return World.current_map.is_visible(e.from) or World.current_map.is_visible(e.to)
	elif effect is ProjectileEffect:
		var e := effect as ProjectileEffect
		return World.current_map.is_visible(e.start_pos) or World.current_map.is_visible(e.end_pos)
	elif effect is ThrownItemEffect:
		var e := effect as ThrownItemEffect
		return World.current_map.is_visible(e.start_pos) or World.current_map.is_visible(e.end_pos)
	elif effect.location != Utils.INVALID_POS:
		return World.current_map.is_visible(effect.location)
	return false


func _get_callable(effect: ActionEffect) -> Callable:
	return func() -> void:
		if effect is AttackEffect:
			await _handle_attack(effect as AttackEffect)
		elif effect is HitEffect:
			await _handle_hit(effect as HitEffect)
		elif effect is MoveEffect:
			await _handle_move(effect as MoveEffect)
		elif effect is DeathEffect:
			await _handle_death(effect as DeathEffect)
		elif effect is PushActorEffect:
			await _handle_push_actor(effect as PushActorEffect)
		elif effect is PushObstacleEffect:
			await _handle_push_obstacle(effect as PushObstacleEffect)
		elif effect is StatusPopupEffect:
			_handle_status_popup(effect as StatusPopupEffect)
		elif effect is ProjectileEffect:
			await _handle_projectile(effect as ProjectileEffect)
		elif effect is ThrownItemEffect:
			await _handle_thrown_item(effect as ThrownItemEffect)
		elif effect is AreaOfEffectDamageEffect:
			await _handle_aoe(effect as AreaOfEffectDamageEffect)
		else:
			Log.e("[EffectRenderer] Unknown effect type: %s" % effect)


func _handle_attack(effect: AttackEffect) -> void:
	var actor := find_actor(effect.target)
	if actor:
		await actor.trigger_attack_effect(effect.direction * -1)


func _handle_hit(effect: HitEffect) -> void:
	if effect.target == World.player:
		flash_hit_effect()
	var actor := find_actor(effect.target)
	if actor:
		await actor.trigger_hit_effect(effect.direction)
		if effect.took_damage and randf() < 0.75:
			var pos := World.current_map.find_monster_position(effect.target)
			var cell := World.current_map.get_cell(pos)
			cell.stain_color = effect.target.hit_particles_color
			cell.stain_frame = randi() % 6
			cell.stain_lifetime = Dice.roll(1, 20) + 90


func _handle_move(effect: MoveEffect) -> void:
	var actor := find_actor(effect.target)
	if actor:
		await actor.move_to(effect.to)


func _handle_death(effect: DeathEffect) -> void:
	var actor := find_actor(effect.target)
	if actor:
		await actor.trigger_death_effect()
		if effect.target != World.player:
			World.current_map.find_and_remove_monster(effect.target)


func _handle_push_actor(effect: PushActorEffect) -> void:
	var actor := find_actor(effect.target)
	if actor:
		actor.set_facing_direction(effect.direction)
		await actor.trigger_attack_effect(effect.direction)


func _handle_push_obstacle(effect: PushObstacleEffect) -> void:
	await _animate_obstacle_push(effect.from, effect.to)


func _handle_status_popup(effect: StatusPopupEffect) -> void:
	var actor := find_actor(effect.target)
	if not actor:
		return
	if actor.popup and is_instance_valid(actor.popup):
		actor.popup.append(effect.text, effect.color)
	else:
		actor.popup = preload("res://scenes/fx/status_popup.tscn").instantiate()
		actor.popup.position = Vector2(Constants.TILE_SIZE / 2.0, 0)
		actor.add_child(actor.popup)
		actor.popup.show_popup(effect.text, effect.color)


func _handle_projectile(effect: ProjectileEffect) -> void:
	await VisualEffects.animate_projectile(
		_scene_root, effect.start_pos, effect.end_pos, effect.source_item
	)
	await VisualEffects.create_explosion(_scene_root, effect.end_pos, false, effect.source_item)


func _handle_thrown_item(effect: ThrownItemEffect) -> void:
	await VisualEffects.animate_projectile(
		_scene_root, effect.start_pos, effect.end_pos, effect.item, true
	)
	var result := Combat.resolve_thrown_item(
		World.current_map, effect.source, effect.end_pos, effect.item
	)
	if (
		result.aoe_type != null
		and not (effect.item.type == Item.Type.GRENADE and effect.item.turns_to_activate > 0)
	):
		await VisualEffects.create_explosion(_scene_root, effect.end_pos, true)
		World.current_map.apply_aoe(
			effect.end_pos, result.aoe_radius, result.aoe_type, result.aoe_damage, result.aoe_turns
		)


func _handle_aoe(effect: AreaOfEffectDamageEffect) -> void:
	if effect.target == World.player:
		flash_hit_effect()
	var actor := find_actor(effect.target)
	if actor:
		await actor.trigger_hit_effect(Vector2.from_angle(randf() * PI * 2))


func _animate_obstacle_push(from_pos: Vector2i, to_pos: Vector2i) -> Signal:
	_map_renderer.obstacle_layer.erase_cell(from_pos)

	var sprite := Sprite2D.new()
	sprite.texture = WorldTiles.TEXTURE
	sprite.centered = false

	var obstacle := World.current_map.get_obstacle(from_pos)
	if not obstacle:
		obstacle = World.current_map.get_obstacle(to_pos)
	if not obstacle:
		Log.e("[EffectRenderer] No obstacle found for push animation")
		return _scene_root.get_tree().create_timer(0.0).timeout

	var tile := _map_renderer.get_obstacle_tile(obstacle)
	var coords := WorldTiles.get_coords(tile)
	sprite.region_enabled = true
	sprite.region_rect = Rect2(
		coords.x * Constants.TILE_SIZE,
		coords.y * Constants.TILE_SIZE,
		Constants.TILE_SIZE,
		Constants.TILE_SIZE
	)
	sprite.position = Vector2(from_pos * Constants.TILE_SIZE)
	_scene_root.add_child(sprite)

	var tween := _scene_root.create_tween()
	tween.tween_property(
		sprite, "position", Vector2(to_pos * Constants.TILE_SIZE), 0.15
	).set_trans(Tween.TRANS_SINE)

	var sig := tween.finished
	sig.connect(func() -> void:
		sprite.queue_free()
		_map_renderer.render_obstacles(World.current_map)
	)
	return sig
