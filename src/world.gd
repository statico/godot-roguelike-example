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

## 플레이어 행동 예산이 바뀔 때마다 발송 (HUD 토큰 표시용)
signal player_budget_updated(budget: ActionBudget)

## 플레이어 턴이 완전히 종료되고 몬스터 턴이 시작될 때
signal player_turn_ended

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

# ==========================================
# 🛡️ [파티 시스템] PARTY SYSTEM
# ==========================================
## 파티 매니저 인스턴스 (플레이어 + AI 파티원 관리)
var party_manager: PartyManager

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

	# Reset instance ID registry on new game
	InstanceID.reset()

	# Wire progression hooks
	if not EventBus.monster_killed.is_connected(_on_monster_killed):
		EventBus.monster_killed.connect(_on_monster_killed)
	if not EventBus.melee_attack_made.is_connected(_on_melee_attack_made):
		EventBus.melee_attack_made.connect(_on_melee_attack_made)

	# Create a new world world_plan
	world_plan = WorldPlan.new(WorldPlan.WorldType.NORMAL)
	Log.i("World world_plan created: %s" % world_plan)

	# Create the player with starting equipment
	# TODO: Choose role based at main menu
	player = MonsterFactory.create_monster(&"fighter", Roles.Type.FIGHTER)
	Roles.equip_monster(player, Roles.Type.FIGHTER)
	Log.i("Player created: %s" % player)

	# ── 파티 매니저 초기화 ──────────────────────────
	party_manager = PartyManager.new()
	Log.i("[PartyManager] Initialized")

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

	# ── 파티원 소환 (플레이어 인근) ──────────────────
	_spawn_party_followers(map)

	# Compute FOV before the first turn
	update_vision()

	# Signal that the world is ready
	map_changed.emit(current_map)
	world_initialized.emit()

	# 첫 플레이어 턴 시작
	begin_player_turn()


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


# ==========================================
# 🛡️ [파티] 파티원 소환 (_spawn_party_followers)
# ==========================================
func _spawn_party_followers(map: Map) -> void:
	# 파티 구성: Ranger + Cleric (RL 데이터 다양성을 위해 역할 조합 가능)
	var party_config: Array[Dictionary] = [
		{"slug": &"ranger",  "role": Roles.Type.RANGER},
		{"slug": &"cleric",  "role": Roles.Type.CLERIC},
	]

	var player_pos := map.find_monster_position(player)

	for cfg in party_config:
		var follower := MonsterFactory.create_monster(cfg["slug"], cfg["role"])
		Roles.equip_monster(follower, cfg["role"])
		# PartyManager가 빈 타일을 찾아 배치
		var placed := party_manager._place_near(map, follower, player_pos)
		if placed:
			party_manager.add_follower(follower)
			Log.i("[World] Spawned party follower: %s at role=%s" % [
				follower.name, Roles.Type.keys()[follower.role]
			])
		else:
			Log.w("[World] Could not place party follower: %s" % follower.name)


# =============================================================
# ⚔️ [3-ACTION TURN SYSTEM] 3행동 턴 시스템
# =============================================================
# 플레이어는 한 라운드에 여러 서브행동을 순서대로 취한다.
# 예산이 모두 소진되거나 플레이어가 명시적으로 턴을 종료하면
# 몬스터 턴이 진행된다.

## 현재 플레이어 턴이 진행 중인지 여부
var player_turn_active: bool = false

## 이번 플레이어 턴의 누적 결과 목록 (서브행동마다 추가됨)
var _pending_results: Array[ActionResult] = []


## 플레이어 턴 시작. initialize() 직후와 몬스터 턴 종료 후 호출.
func begin_player_turn() -> void:
	player.budget.reset(player.get_speed())
	player_turn_active = true
	_pending_results.clear()
	Log.i("[color=lime]======== TURN %d — 플레이어 턴 ========[/color]" % current_turn)
	turn_started.emit()
	player_budget_updated.emit(player.budget)


## 플레이어 서브행동 하나를 처리한다.
## 행동 예산이 없거나 행동 실패 시 null 반환.
## 행동 성공 시 result 반환, 예산 소진 시 자동으로 몬스터 턴 진행.
func apply_player_action(action: BaseAction) -> ActionResult:
	if not player_turn_active:
		Log.w("[World] apply_player_action called outside player turn")
		return null

	var cost: ActionBudget.Cost = action.action_cost

	# 예산 확인
	if not player.budget.can_use(cost):
		var cost_name: String = ActionBudget.Cost.keys()[cost]
		Log.d("[World] 예산 없음: %s (required: %s)" % [action, cost_name])
		if cost == ActionBudget.Cost.ACTION:
			message_logged.emit("You have already used your action this turn.", LogMessages.Level.BAD)
		elif cost == ActionBudget.Cost.BONUS:
			message_logged.emit("You have already used your bonus action this turn.", LogMessages.Level.BAD)
		elif cost == ActionBudget.Cost.MOVE:
			message_logged.emit("You cannot move any further this turn.", LogMessages.Level.BAD)
		return null

	Log.i("[color=aqua]  SUB-ACTION: %s[/color]" % action)

	# 행동 실행
	var result := action.apply(current_map)
	if not result:
		return null

	if not result.success:
		if result.message:
			# 실패 메시지는 즉시 표시 (효과 큐 밖)
			message_logged.emit(result.message, result.message_level)
		return result

	# 예산 소모
	var tiles_moved := 1 if cost == ActionBudget.Cost.MOVE else 0
	player.budget.spend(cost, tiles_moved)

	# 추적 로그 (LLM 학습 데이터)
	player.budget.log_action(cost, action.get_script().get_global_name(), true)
	EventBus.action_executed.emit(
		player,
		cost,
		action.get_script().get_global_name(),
		true,
		player.budget.to_dict()
	)

	# 플레이어 경로 기록 (파티원 팔로우용)
	var player_pos_now := current_map.find_monster_position(player)
	if player_pos_now != Utils.INVALID_POS:
		party_manager.record_player_position(player_pos_now)

	_pending_results.append(result)

	Log.d("[World] 예산 상태: %s" % player.budget)
	player_budget_updated.emit(player.budget)

	# 주행동 + 보조행동 모두 소진 시 자동 턴 종료
	if player.budget.is_turn_exhausted():
		Log.d("[World] 예산 소진 — 자동 턴 종료")
		_end_player_turn()

	return result


## 플레이어가 명시적으로 턴을 종료할 때 (엔드 턴 키)
func end_player_turn() -> void:
	if not player_turn_active:
		return
	Log.i("[color=aqua]  플레이어 턴 수동 종료[/color]")
	_end_player_turn()


## 내부: 플레이어 턴을 마무리하고 몬스터 턴을 진행한다.
func _end_player_turn() -> void:
	player_turn_active = false
	player_turn_ended.emit()

	# 상태이상 틱 + 인캄브런스
	for monster in current_map.get_monsters():
		monster.tick_status_effects()
		monster.tick_encumbrance()

	# 영양 처리 (턴당 1회)
	var nutrition_cost := 1
	for res in _pending_results:
		nutrition_cost += res.extra_nutrition_consumed
	var nutrition_result := player.nutrition.decrease(nutrition_cost)
	if nutrition_result.message:
		message_logged.emit(nutrition_result.message, LogMessages.Level.BAD)
	if nutrition_result.died:
		player.is_dead = true
		effect_occurred.emit(
			DeathEffect.new(player, current_map.find_monster_position(player), true)
		)
		_finish_turn()
		return

	# 자연 회복 (3턴마다)
	if player.nutrition.value >= Nutrition.THRESHOLD_STARVING and player.hp < player.max_hp:
		if current_turn % 3 == 0:
			var heal_amount := 1
			if player.nutrition.value >= Nutrition.THRESHOLD_SATIATED:
				heal_amount += 1
			player.hp = mini(player.hp + heal_amount, player.max_hp)

	# 몬스터 에너지 누적 및 행동
	for monster in current_map.get_monsters():
		monster.energy += monster.get_speed()

	var monsters := current_map.get_monsters()
	Log.d("[World] 몬스터 턴 — %d 유닛 확인" % monsters.size())
	for monster in monsters:
		if monster == player:
			continue
		if monster.energy >= Monster.SPEED_NORMAL:
			# 몬스터도 예산 리셋
			monster.budget.reset(monster.get_speed())

			var monster_action := monster.get_next_action(current_map)
			if monster_action:
				var monster_result := monster_action.apply(current_map)
				# 몬스터 행동도 EventBus에 기록 (LLM 학습용)
				EventBus.action_executed.emit(
					monster,
					monster_action.action_cost,
					monster_action.get_script().get_global_name(),
					monster_result.success if monster_result else false,
					monster.budget.to_dict()
				)
				if monster_result:
					_pending_results.append(monster_result)

			monster.energy -= Monster.SPEED_NORMAL
			energy_updated.emit(monster)

	# 구역 효과 업데이트
	update_area_effects()
	update_vision()

	_finish_turn()


## 결과 방출 및 턴 카운터 증가
func _finish_turn() -> void:
	for res in _pending_results:
		for effect in res.effects:
			effect_occurred.emit(effect)
		if res.message:
			message_logged.emit(res.message, res.message_level)
	_pending_results.clear()

	Log.i("[color=lime]-------- TURN %d 종료 --------[/color]" % current_turn)
	turn_ended.emit()
	current_turn += 1

	if player.is_dead:
		game_over = true
		game_ended.emit()
		return

	# 다음 플레이어 턴 시작
	begin_player_turn()


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

	# [Transition Patch] Remove party followers from the old map before switching
	party_manager.remove_followers_from_map(current_map)
	Log.i("[Transition Patch] Cleared party followers from old map: %s" % current_map.id)

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

	# ── 파티원도 새 맵에 배치 ─────────────────────────
	party_manager.on_map_changed(current_map, target_stairs_type)

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


# =============================================================
# 🌟 [경험치 / 스킬 성장] PROGRESSION HOOKS
# =============================================================

func _on_monster_killed(killer: Monster, victim: Monster) -> void:
	if killer != player or victim.xp_reward <= 0:
		return

	# XP 지급
	var xp := victim.xp_reward
	var level_msgs := player.level_comp.add_experience(xp)
	message_logged.emit("You gain %d XP." % xp, LogMessages.Level.GOOD)

	# 레벨업 메시지 출력
	for msg in level_msgs:
		message_logged.emit("[color=gold]%s[/color]" % msg, LogMessages.Level.GREAT)

	# 마지막 공격 무기 스킬 XP (킬 보너스)
	var weapon := player.equipment.get_equipped_item(Equipment.Slot.MELEE)
	var skill_type := weapon.skill_type if weapon else Skills.Type.FISTS
	var skill_msgs := player.skills.add_skill_xp(skill_type, 20)
	for msg in skill_msgs:
		message_logged.emit("[color=cyan]%s[/color]" % msg, LogMessages.Level.GREAT)


func _on_melee_attack_made(attacker: Monster, _target: Monster) -> void:
	if attacker != player:
		return

	# 무기 명중 시 스킬 XP
	var weapon := player.equipment.get_equipped_item(Equipment.Slot.MELEE)
	var skill_type := weapon.skill_type if weapon else Skills.Type.FISTS
	var skill_msgs := player.skills.add_skill_xp(skill_type, 5)
	for msg in skill_msgs:
		message_logged.emit("[color=cyan]%s[/color]" % msg, LogMessages.Level.GREAT)
