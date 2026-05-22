extends Node2D

# =============================================================
# 🎮 [Game] 메인 씬 오케스트레이터
# =============================================================
# 이 파일은 세 가지만 한다:
#   1. 초기화 및 시그널 연결
#   2. 플레이어 액션 처리 흐름 관리
#   3. 레티클 / 호버 정보 / 액터 렌더링
#
# 이펙트 처리 → EffectRenderer
# 입력 처리   → InputHandler
# =============================================================

var _throw_mode_active: bool = false
var _last_mouse_tile: Vector2i = Utils.INVALID_POS

var _input_handler: InputHandler
var _effect_renderer: EffectRenderer

@onready var map_renderer: MapRenderer = %MapRenderer
@onready var actors: Node2D = %Actors
@onready var hud: HUD = %HUD
@onready var hit_effect_rect: ColorRect = %HitEffect
@onready var reticle: Reticle = %Reticle


func _ready() -> void:
	# ── 자식 모듈 생성 ─────────────────────────────────────
	_effect_renderer = EffectRenderer.new()
	add_child(_effect_renderer)
	_effect_renderer.setup(self, actors, map_renderer, hit_effect_rect)

	_input_handler = InputHandler.new()
	add_child(_input_handler)
	_input_handler.setup(hud)
	_input_handler.get_mouse_tile = func() -> Vector2i:
		return Vector2i(get_local_mouse_position() / Constants.TILE_SIZE)

	# ── 모듈 시그널 연결 ───────────────────────────────────
	_input_handler.action_requested.connect(_handle_player_action)
	_input_handler.path_move_requested.connect(_execute_movement_path)
	_input_handler.end_turn_requested.connect(_on_end_turn_requested)
	_input_handler.throw_mode_changed.connect(func(active: bool) -> void:
		_throw_mode_active = active
	)

	# ── World 시그널 연결 ──────────────────────────────────
	World.map_changed.connect(_on_map_changed)
	World.effect_occurred.connect(_effect_renderer.enqueue)
	World.turn_started.connect(_on_turn_started)
	World.game_ended.connect(_on_game_over)
	World.player_budget_updated.connect(_on_budget_updated)
	World.player_turn_ended.connect(_on_player_turn_ended)

	# ── 게임 초기화 ────────────────────────────────────────
	_initialize()
	_input_handler.enabled = true
	hit_effect_rect.visible = false


func _initialize() -> void:
	_effect_renderer.effects_queue.clear()
	World.initialize()
	_update_actors()


func _process(_delta: float) -> void:
	_update_reticle()
	hud.throw_info.visible = _throw_mode_active


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_tree().change_scene_to_file("res://scenes/ui/quit.tscn")


# =============================================================
# ⚙️ 액션 처리
# =============================================================

func _handle_player_action(action: BaseAction) -> void:
	Log.i("Player action: %s" % action)

	var result := World.apply_player_action(action)
	_effect_renderer.enqueue_status_effects()
	await _effect_renderer.flush()

	map_renderer.render_map(World.current_map)
	_update_actors()

	# 플레이어 턴이 아직 끝나지 않았으면 계속 입력 받음
	# (턴 종료는 World._end_player_turn → player_turn_ended 신호로 처리됨)
	if result != null and World.player_turn_active:
		_input_handler.enabled = true


func _on_end_turn_requested() -> void:
	World.end_player_turn()
	_effect_renderer.enqueue_status_effects()
	await _effect_renderer.flush()
	map_renderer.render_map(World.current_map)
	_update_actors()
	if World.player_turn_active:
		_input_handler.enabled = true


func _on_player_turn_ended() -> void:
	# 몬스터 턴 진행 중 — 입력 잠금 (World._end_player_turn이 끝나면 begin_player_turn → budget_updated → 입력 재개)
	_input_handler.enabled = false


func _on_budget_updated(_budget: ActionBudget) -> void:
	# HUD 토큰 표시 갱신은 hud.gd 가 World.player_budget_updated에 직접 연결
	pass


func _execute_movement_path(path: Array[Vector2i]) -> void:
	if path.size() < 1:
		return

	hud.updates_enabled = false

	var player_pos := World.current_map.find_monster_position(World.player)
	var move_dir   := path[0] - player_pos

	var obstacle := World.current_map.get_obstacle(path[0])
	if obstacle and obstacle.type == Obstacle.Type.DOOR_CLOSED:
		_input_handler.enabled = false
		_handle_player_action(PlayerOpenAction.new(move_dir))
		hud.updates_enabled = true
		return

	_input_handler.enabled = false
	_handle_player_action(PlayerAttackMoveAction.new(move_dir))

	if path.size() > 1:
		await get_tree().create_timer(0.1).timeout
		for monster in World.current_map.get_visible_monsters():
			if monster != World.player and monster.is_hostile_to(World.player):
				hud.updates_enabled = true
				return
		path.remove_at(0)
		_execute_movement_path(path)
	else:
		hud.updates_enabled = true


# =============================================================
# 🖼️ 액터 관리
# =============================================================

func _update_actors() -> void:
	var to_remove: Dictionary = {}
	for actor: Actor in actors.get_children():
		to_remove[actor.monster] = actor

	for monster in World.current_map.get_visible_monsters():
		var actor: Actor = to_remove.get(monster)
		if actor:
			var pos := World.current_map.find_monster_position(monster)
			if actor.grid_pos != pos:
				actor.move_to(pos)
			to_remove.erase(monster)
		else:
			actor = preload("res://scenes/actor/actor.tscn").instantiate()
			actor.monster = monster
			actor.init(World.current_map.find_monster_position(monster))
			actors.add_child(actor)
			if monster == World.player:
				actor.add_to_group("player")
		actor.visible = true

	for actor: Actor in to_remove.values():
		actor.queue_free()

	_last_mouse_tile = Utils.INVALID_POS


# =============================================================
# 📡 World / 씬 이벤트
# =============================================================

func _on_map_changed(map: Map) -> void:
	map_renderer.render_map(map)


func _on_turn_started() -> void:
	var destroyed := false
	for actor: Actor in actors.get_children():
		if actor.popup and is_instance_valid(actor.popup):
			actor.popup.destroy()
			actor.popup = null
			destroyed = true
	if destroyed:
		await get_tree().process_frame


func _on_game_over() -> void:
	map_renderer.render_map(World.current_map)
	_update_actors()
	await get_tree().create_timer(1).timeout
	Modals.show_game_over()


# =============================================================
# 🎯 레티클 / 호버 정보
# =============================================================

func _update_reticle() -> void:
	if World.game_over or Modals.has_visible_modals():
		_hide_reticle()
		return

	var tile_pos := Vector2i(get_local_mouse_position() / Constants.TILE_SIZE)

	if not World.current_map.is_in_bounds(tile_pos):
		_hide_reticle()
		return

	if World.current_map.get_terrain(tile_pos).type == Terrain.Type.EMPTY:
		_hide_reticle()
		return

	reticle.visible = true
	reticle.position = Vector2(tile_pos * Constants.TILE_SIZE) + Constants.HALF_TILE_SIZE_VEC2

	var is_vis  := World.current_map.is_visible(tile_pos)
	var was_seen := World.current_map.was_seen(tile_pos)
	var info := _get_hover_info(tile_pos, is_vis, was_seen)

	if info:
		reticle.modulate   = info.color
		reticle.modulate.a = 1.0
		reticle.pulse      = info.pulse
		hud.set_hover_info(info.text)
	else:
		_hide_reticle()

	if is_vis and _should_draw_path(tile_pos):
		_draw_path_preview(tile_pos)
	else:
		_clear_path_preview()

	_last_mouse_tile = tile_pos


func _hide_reticle() -> void:
	reticle.visible = false
	hud.set_hover_info(null)
	_last_mouse_tile = Utils.INVALID_POS


func _get_hover_info(tile_pos: Vector2i, is_visible: bool, was_seen: bool) -> Dictionary:
	var monster  := World.current_map.get_monster(tile_pos)
	var obstacle := World.current_map.get_obstacle(tile_pos)
	var items    := World.current_map.get_items(tile_pos)
	var terrain  := World.current_map.get_terrain(tile_pos)
	var cell     := World.current_map.get_cell(tile_pos)

	var aoe_text := ""
	if not cell.area_effects.is_empty():
		aoe_text = "\n[color=red]" + _get_area_effects_text(cell.area_effects) + "[/color]"

	if monster == World.player:
		return {"color": GameColors.GREEN, "pulse": true, "text": monster.get_hover_info() + aoe_text}
	elif is_visible and monster:
		var color := GameColors.RED if monster.is_hostile_to(World.player) else GameColors.GREEN
		return {"color": color, "pulse": true, "text": monster.get_hover_info() + aoe_text}
	elif is_visible and items.size() > 0:
		return {"color": GameColors.CYAN, "pulse": true, "text": Item.get_item_summary(items) + aoe_text}
	elif is_visible and obstacle:
		return {"color": GameColors.WHITE, "pulse": false, "text": obstacle.get_hover_info() + aoe_text}
	elif was_seen:
		return {"color": GameColors.WHITE, "pulse": false, "text": terrain.get_hover_info() + aoe_text}
	return {}


func _get_area_effects_text(effects: Array[MapCell.AreaEffect]) -> String:
	var parts: Array[String] = []
	for effect in effects:
		var label: String
		match effect.type:
			Damage.Type.POISON: label = "Poison Gas"
			Damage.Type.FIRE:   label = "Burning"
			Damage.Type.COLD:   label = "Freezing"
			_:                  label = "Unknown Effect"
		parts.append("%s (%d turns)" % [label, effect.turns_remaining])
	return ", ".join(parts)


func _should_draw_path(tile_pos: Vector2i) -> bool:
	var monster := World.current_map.get_monster(tile_pos)
	if monster and monster.is_hostile_to(World.player):
		return true
	return _throw_mode_active


func _clear_path_preview() -> void:
	for child in map_renderer.highlight_layer.get_children():
		child.queue_free()


func _draw_path_preview(tile_pos: Vector2i) -> void:
	_clear_path_preview()
	var player_pos := World.current_map.find_monster_position(World.player)
	for pos in Utils.calculate_trajectory(player_pos, tile_pos):
		if pos == player_pos:
			continue
		var rect := ColorRect.new()
		rect.size     = Vector2(Constants.TILE_SIZE, Constants.TILE_SIZE)
		rect.position = Vector2(pos * Constants.TILE_SIZE)
		if World.current_map.get_monster(pos):
			rect.color = Color(1, 0, 0, 0.4)
		elif World.current_map.get_obstacle(pos):
			rect.color = Color(1, 1, 0, 0.4)
		else:
			rect.color = Color(1, 1, 1, 0.2)
		map_renderer.highlight_layer.add_child(rect)
