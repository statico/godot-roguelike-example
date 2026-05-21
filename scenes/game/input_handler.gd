class_name InputHandler
extends Node

# =============================================================
# 🎮 [InputHandler] 플레이어 입력 처리 전담 모듈
# =============================================================
# 키보드 / 마우스 입력을 BaseAction 으로 변환해 시그널로 전달.
# 인벤토리, 드랍, 장착 등 UI 시그널도 여기서 구독한다.
#
# game.gd 는 action_requested / path_move_requested 를 수신해
# _handle_player_action / _execute_movement_path 로 위임한다.
# =============================================================

signal action_requested(action: BaseAction)
signal path_move_requested(path: Array[Vector2i])
signal throw_mode_changed(active: bool)
## 플레이어가 턴 종료 키를 눌렀을 때
signal end_turn_requested

## game.gd 가 false 로 설정하면 입력을 무시 (액션 처리 중)
var enabled: bool = false

## game.gd 가 주입하는 마우스→타일 변환 Callable
## func() -> Vector2i
var get_mouse_tile: Callable

var _hud: HUD
var _throw_selection: Variant = null


func setup(p_hud: HUD) -> void:
	_hud = p_hud

	Modals.inventory_opened.connect(func(inventory: InventoryModal) -> void:
		inventory.pickup_requested.connect(func(sel: Variant) -> void:
			action_requested.emit(PlayerPickupAction.new(ItemSelection._from_selections(sel)))
		)
		inventory.drop_requested.connect(func(sel: Variant) -> void:
			action_requested.emit(PlayerDropAction.new(ItemSelection._from_selections(sel)))
		)
		inventory.equip_requested.connect(func(a: PlayerEquipAction) -> void:
			action_requested.emit(a)
		)
		inventory.unequip_requested.connect(func(a: PlayerUnequipAction) -> void:
			action_requested.emit(a)
		)
		inventory.throw_requested.connect(func(sel: Variant) -> void:
			_throw_selection = ItemSelection._from_selections(sel)
			throw_mode_changed.emit(true)
		)
		inventory.use_requested.connect(func(item: Item) -> void:
			action_requested.emit(PlayerUseItemAction.new(item))
		)
		inventory.reparent_requested.connect(func(a: PlayerReparentItemAction) -> void:
			action_requested.emit(a)
		)
		inventory.toggle_container_requested.connect(func(item: Item) -> void:
			action_requested.emit(PlayerToggleContainerAction.new(item))
		)
		inventory.message_logged.connect(func(msg: String) -> void:
			World.message_logged.emit(msg)
		)
	)

	_hud.drop_requested.connect(func(sel: Variant) -> void:
		action_requested.emit(PlayerDropAction.new(ItemSelection._from_selections(sel)))
	)

	_hud.ability_used.connect(func(action: BaseAction) -> void:
		_emit_action(action)
	)


func _unhandled_input(event: InputEvent) -> void:
	if Modals.has_visible_modals():
		if event.is_action_pressed("attack_move_to_location"):
			get_viewport().set_input_as_handled()
			Modals.hide_inventory()
		return

	if World.game_over or not _hud.updates_enabled or not enabled:
		return

	# ── 투척 조준 모드 ───────────────────────────────────────
	if _throw_selection is Array[ItemSelection]:
		if event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			_cancel_throw()
			return

		if (
			event.is_action_pressed("attack_move_to_location")
			or event.is_action_pressed("fire_at_location")
		):
			var tile_pos: Vector2i = get_mouse_tile.call()
			if World.current_map.is_in_bounds(tile_pos):
				var terrain := World.current_map.get_terrain(tile_pos)
				if terrain.type != Terrain.Type.EMPTY:
					get_viewport().set_input_as_handled()
					var throw_action := PlayerThrowAction.new(
						_throw_selection as Array[ItemSelection], tile_pos
					)
					_cancel_throw()
					_emit_action(throw_action)
					return
		return  # 투척 모드 중 다른 입력 무시

	# ── 마우스 클릭 ─────────────────────────────────────────
	if event.is_action_pressed("attack_move_to_location"):
		var tile_pos: Vector2i = get_mouse_tile.call()
		if World.current_map.is_in_bounds(tile_pos):
			var terrain := World.current_map.get_terrain(tile_pos)
			if terrain.type != Terrain.Type.EMPTY:
				get_viewport().set_input_as_handled()
				_on_tile_attack_move(tile_pos)
		return

	if event.is_action_pressed("fire_at_location"):
		var tile_pos: Vector2i = get_mouse_tile.call()
		if World.current_map.is_in_bounds(tile_pos):
			var terrain := World.current_map.get_terrain(tile_pos)
			if terrain.type != Terrain.Type.EMPTY:
				get_viewport().set_input_as_handled()
				_on_tile_fire_at(tile_pos)
		return

	if event.is_action_pressed("toggle_debug"):
		_hud.debug_mode = not _hud.debug_mode
		return

	# ── 키보드 ───────────────────────────────────────────────
	var action := await _check_keyboard()
	if action:
		_emit_action(action)


# =============================================================
# 🔒 내부 — 타일 클릭 처리
# =============================================================

func _on_tile_attack_move(tile_pos: Vector2i) -> void:
	var is_visible := World.current_map.is_visible(tile_pos)
	var was_seen   := World.current_map.was_seen(tile_pos)
	if not is_visible and not was_seen:
		return

	var player_pos := World.current_map.find_monster_position(World.player)

	# 플레이어 타일 클릭 → 계단 확인
	if tile_pos == player_pos:
		var obstacle := World.current_map.get_obstacle(tile_pos)
		if obstacle:
			match obstacle.type:
				Obstacle.Type.STAIRS_UP:
					_emit_action(PlayerMoveUpstairsAction.new())
					return
				Obstacle.Type.STAIRS_DOWN:
					_emit_action(PlayerMoveDownstairsAction.new())
					return

	var hostile_visible := false
	for m in World.current_map.get_visible_monsters():
		if m != World.player and m.is_hostile_to(World.player):
			hostile_visible = true
			break

	var path := Pathfinding.find_path(World.current_map, player_pos, tile_pos)
	if path.is_empty():
		return

	if hostile_visible:
		_emit_action(PlayerAttackMoveAction.new(path[0] - player_pos))
	else:
		enabled = false
		path_move_requested.emit(path)


func _on_tile_fire_at(tile_pos: Vector2i) -> void:
	if World.current_map.is_visible(tile_pos):
		_emit_action(PlayerFireAction.new(tile_pos))


# =============================================================
# 🔒 내부 — 키보드 입력 → 액션 변환
# =============================================================

func _check_keyboard() -> BaseAction:
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

	# 턴 종료 (Tab 키) — 남은 행동 포기하고 몬스터 턴으로 넘김
	if Input.is_action_just_pressed("end_turn"):
		get_viewport().set_input_as_handled()
		end_turn_requested.emit()
		return null

	if Input.is_action_just_pressed("pick_up_item"):
		get_viewport().set_input_as_handled()
		var pos := World.current_map.find_monster_position(World.player)
		var selections: Array[ItemSelection] = []
		for item in World.current_map.get_items(pos):
			selections.append(ItemSelection.new(item, item.quantity))
		return PlayerPickupAction.new(selections)

	# 이동 8방향
	for entry: Array in [
		["move_up",         Vector2i.UP],
		["move_down",       Vector2i.DOWN],
		["move_left",       Vector2i.LEFT],
		["move_right",      Vector2i.RIGHT],
		["move_up_left",    Vector2i.UP   + Vector2i.LEFT],
		["move_up_right",   Vector2i.UP   + Vector2i.RIGHT],
		["move_down_left",  Vector2i.DOWN + Vector2i.LEFT],
		["move_down_right", Vector2i.DOWN + Vector2i.RIGHT],
	]:
		if Input.is_action_just_pressed(entry[0]):
			get_viewport().set_input_as_handled()
			return PlayerAttackMoveAction.new(entry[1] as Vector2i)

	if Input.is_action_just_pressed("move_upstairs"):
		get_viewport().set_input_as_handled()
		return PlayerMoveUpstairsAction.new()

	if Input.is_action_just_pressed("move_downstairs"):
		get_viewport().set_input_as_handled()
		return PlayerMoveDownstairsAction.new()

	if Input.is_action_just_pressed("open"):
		get_viewport().set_input_as_handled()
		var dir := await Modals.prompt_for_direction()
		if dir != Vector3i.ZERO:
			return PlayerOpenAction.new(Vector2i(dir.x, dir.y))

	if Input.is_action_just_pressed("close"):
		get_viewport().set_input_as_handled()
		var dir := await Modals.prompt_for_direction()
		if dir != Vector3i.ZERO:
			return PlayerCloseAction.new(Vector2i(dir.x, dir.y))

	# 클래스 어빌리티 슬롯 (1~4)
	for i in 4:
		if Input.is_action_just_pressed("ability_slot_%d" % (i + 1)):
			get_viewport().set_input_as_handled()
			return PlayerUseAbilityAction.new(i)

	return null


# =============================================================
# 🔒 내부 — 헬퍼
# =============================================================

func _emit_action(action: BaseAction) -> void:
	# 이동/무료 행동은 입력을 잠그지 않음 (연속 이동 가능)
	# 주행동/보조행동은 효과 렌더링 완료까지 잠금
	var locks_input := (
		action.action_cost == ActionBudget.Cost.ACTION
		or action.action_cost == ActionBudget.Cost.BONUS
		or action.action_cost == ActionBudget.Cost.REACTION
	)
	if locks_input:
		enabled = false
	action_requested.emit(action)


func _cancel_throw() -> void:
	_throw_selection = null
	throw_mode_changed.emit(false)
