class_name PartyAI
extends RefCounted

# ==========================================
# 🛡️ [파티 AI] PARTY MEMBER BEHAVIOR TREE
# ==========================================
# 클래스별(Fighter/Ranger/Cleric/Rogue) 행동 우선순위를 BT 노드로 구현.
# MonsterAI의 BTNode 클래스를 상속하여 기존 BT 인프라와 호환됩니다.

# ==========================================
# 📌 [구역 1] 공통 체크 노드 (COMMON CHECK NODES)
# ==========================================

## 인접 적 검색: 파티원 시야 내 가장 가까운 적 찾기
class FindNearestEnemy:
	extends MonsterAI.BTNode

	# BT 실행 간 공유되는 정적 변수로 적 위치 저장
	static var enemy_pos: Vector2i = Vector2i(-1, -1)
	static var enemy_ref: Monster = null

	func tick(actor: Monster, map: Map) -> MonsterAI.BTStatus:
		enemy_pos = Vector2i(-1, -1)
		enemy_ref = null
		var actor_pos := map.find_monster_position(actor)
		var best_dist := 9999.0

		for monster in map.get_monsters():
			if monster == actor or monster == World.player:
				continue
			if not actor.is_hostile_to(monster):
				continue
			var mpos := map.find_monster_position(monster)
			if mpos == Utils.INVALID_POS:
				continue
			# [LOS 체크] 시야 내이고, 벽에 가리지 않은 위치만 탐지
			var dist := actor_pos.distance_to(mpos)
			if dist <= actor.sight_radius and map.is_visible(mpos) and dist < best_dist:
				best_dist = dist
				enemy_pos = mpos
				enemy_ref = monster

		if enemy_ref != null:
			Log.d("[PartyAI] FindNearestEnemy: found %s at %s" % [enemy_ref.name, enemy_pos])
			return MonsterAI.BTStatus.SUCCESS
		Log.d("[PartyAI] FindNearestEnemy: no visible enemy")
		return MonsterAI.BTStatus.FAILURE


## 적이 인접해 있는지 확인
class CheckEnemyAdjacent:
	extends MonsterAI.BTNode

	func tick(actor: Monster, map: Map) -> MonsterAI.BTStatus:
		if FindNearestEnemy.enemy_ref == null:
			return MonsterAI.BTStatus.FAILURE
		var actor_pos := map.find_monster_position(actor)
		if actor.is_adjacent_to(actor_pos, FindNearestEnemy.enemy_pos):
			return MonsterAI.BTStatus.SUCCESS
		return MonsterAI.BTStatus.FAILURE


## 근접 공격 (적 방향으로 AttackMoveAction)
class AttackEnemy:
	extends MonsterAI.BTNode

	func tick(actor: Monster, map: Map) -> MonsterAI.BTStatus:
		if FindNearestEnemy.enemy_ref == null:
			return MonsterAI.BTStatus.FAILURE
		var actor_pos := map.find_monster_position(actor)
		if actor.is_adjacent_to(actor_pos, FindNearestEnemy.enemy_pos):
			var dir := FindNearestEnemy.enemy_pos - actor_pos
			actor.next_action = AttackMoveAction.new(actor, dir)
			Log.d("[PartyAI] AttackEnemy: attacking %s" % FindNearestEnemy.enemy_ref.name)
			return MonsterAI.BTStatus.SUCCESS
		return MonsterAI.BTStatus.FAILURE


## 적을 향해 이동
class MoveTowardEnemy:
	extends MonsterAI.BTNode

	func tick(actor: Monster, map: Map) -> MonsterAI.BTStatus:
		if FindNearestEnemy.enemy_ref == null:
			return MonsterAI.BTStatus.FAILURE
		var actor_pos := map.find_monster_position(actor)
		var move_dir := actor.get_next_step_towards_player(map, actor_pos, FindNearestEnemy.enemy_pos, true)
		if move_dir == Vector2i.ZERO:
			move_dir = actor.get_next_step_towards_player(map, actor_pos, FindNearestEnemy.enemy_pos, false)
		if move_dir != Vector2i.ZERO:
			actor.next_action = MoveAction.new(actor, move_dir)
			Log.d("[PartyAI] MoveTowardEnemy: moving %s" % move_dir)
			return MonsterAI.BTStatus.SUCCESS
		return MonsterAI.BTStatus.FAILURE


# ==========================================
# 📌 [구역 2] 팔로우 노드 (FOLLOW NODES)
# ==========================================

## 플레이어 이동 궤적(breadcrumb)을 따라 이동
class FollowPlayerTrail:
	extends MonsterAI.BTNode

	var party_manager: PartyManager
	var follower_index: int

	func _init(p_manager: PartyManager, p_index: int) -> void:
		party_manager = p_manager
		follower_index = p_index

	func tick(actor: Monster, map: Map) -> MonsterAI.BTStatus:
		var target := party_manager.get_trail_target(follower_index)
		if target == Utils.INVALID_POS:
			return MonsterAI.BTStatus.FAILURE
		var actor_pos := map.find_monster_position(actor)
		if actor_pos == target:
			Log.d("[PartyAI] FollowPlayerTrail[%d]: already at target" % follower_index)
			return MonsterAI.BTStatus.SUCCESS  # Already at target, do nothing (success = skip turn)
		var move_dir := actor.get_next_step_towards_player(map, actor_pos, target, true)
		if move_dir == Vector2i.ZERO:
			move_dir = actor.get_next_step_towards_player(map, actor_pos, target, false)
		if move_dir != Vector2i.ZERO:
			actor.next_action = MoveAction.new(actor, move_dir)
			Log.d("[PartyAI] FollowPlayerTrail[%d]: following trail to %s" % [follower_index, target])
			return MonsterAI.BTStatus.SUCCESS
		return MonsterAI.BTStatus.FAILURE


## 플레이어와 거리가 너무 가까운지 확인 (Ranger용)
class CheckTooCloseToEnemy:
	extends MonsterAI.BTNode

	var min_distance: float

	func _init(p_min: float = 3.0) -> void:
		min_distance = p_min

	func tick(actor: Monster, map: Map) -> MonsterAI.BTStatus:
		if FindNearestEnemy.enemy_ref == null:
			return MonsterAI.BTStatus.FAILURE
		var actor_pos := map.find_monster_position(actor)
		var dist := actor_pos.distance_to(FindNearestEnemy.enemy_pos)
		if dist < min_distance:
			Log.d("[PartyAI] CheckTooCloseToEnemy: too close (%.1f < %.1f)" % [dist, min_distance])
			return MonsterAI.BTStatus.SUCCESS
		return MonsterAI.BTStatus.FAILURE


## 원거리 발사 (Ranger)
class FireAtEnemy:
	extends MonsterAI.BTNode

	func tick(actor: Monster, map: Map) -> MonsterAI.BTStatus:
		if FindNearestEnemy.enemy_ref == null:
			return MonsterAI.BTStatus.FAILURE
		var actor_pos := map.find_monster_position(actor)
		var dist := actor_pos.distance_to(FindNearestEnemy.enemy_pos)
		if dist > 8:
			return MonsterAI.BTStatus.FAILURE
		# [LOS 체크] 벽에 가린 적에게는 발사하지 않음
		if not map.is_visible(FindNearestEnemy.enemy_pos):
			Log.d("[PartyAI] FireAtEnemy: enemy not visible (blocked by wall)")
			return MonsterAI.BTStatus.FAILURE
		var weapon := actor.equipment.get_equipped_item(Equipment.Slot.RANGED)
		if not weapon or not weapon.is_ranged_weapon():
			return MonsterAI.BTStatus.FAILURE
		actor.next_action = FireAction.new(actor, FindNearestEnemy.enemy_pos)
		Log.d("[PartyAI] FireAtEnemy: firing at %s" % FindNearestEnemy.enemy_pos)
		return MonsterAI.BTStatus.SUCCESS


## 적에게서 멀어지기 (Ranger 카이팅)
class FleeFromEnemy:
	extends MonsterAI.BTNode

	func tick(actor: Monster, map: Map) -> MonsterAI.BTStatus:
		if FindNearestEnemy.enemy_ref == null:
			return MonsterAI.BTStatus.FAILURE
		var actor_pos := map.find_monster_position(actor)
		var away_dir := Vector2(actor_pos - FindNearestEnemy.enemy_pos).normalized()
		var move_dir := actor.get_safe_move_direction(map, actor_pos, away_dir)
		if move_dir != Vector2i.ZERO:
			actor.next_action = AttackMoveAction.new(actor, move_dir)
			Log.d("[PartyAI] FleeFromEnemy: kiting away %s" % move_dir)
			return MonsterAI.BTStatus.SUCCESS
		return MonsterAI.BTStatus.FAILURE


# ==========================================
# 📌 [구역 3] 클레릭 전용 노드 (CLERIC NODES)
# ==========================================

## 가장 HP가 낮은 파티원 검색
class FindWoundedAlly:
	extends MonsterAI.BTNode

	var party_manager: PartyManager
	static var wounded_ally: Monster = null

	func _init(p_manager: PartyManager) -> void:
		party_manager = p_manager

	func tick(actor: Monster, map: Map) -> MonsterAI.BTStatus:
		wounded_ally = null
		var lowest_pct := 0.75  # 75% HP 미만일 때만 힐 우선순위

		# 플레이어 먼저 확인
		var player_pct := float(World.player.hp) / float(World.player.max_hp)
		if player_pct < lowest_pct and not World.player.is_dead:
			var player_pos := map.find_monster_position(World.player)
			var actor_pos := map.find_monster_position(actor)
			if actor_pos.distance_to(player_pos) <= actor.sight_radius:
				wounded_ally = World.player
				lowest_pct = player_pct

		# 파티원 확인
		for follower in party_manager.get_living_followers():
			if follower == actor:
				continue
			var pct := float(follower.hp) / float(follower.max_hp)
			if pct < lowest_pct:
				var fpos := map.find_monster_position(follower)
				var apos := map.find_monster_position(actor)
				if apos.distance_to(fpos) <= actor.sight_radius:
					wounded_ally = follower
					lowest_pct = pct

		if wounded_ally != null:
			Log.d("[PartyAI] FindWoundedAlly: found %s (%.0f%% HP)" % [wounded_ally.name, lowest_pct * 100])
			return MonsterAI.BTStatus.SUCCESS
		return MonsterAI.BTStatus.FAILURE


## 힐 포션 사용 (HP 60% 미만 시 자신에게 사용)
## NOTE: UseItemAction은 자기 자신만 대상으로 합니다.
## 부상 파티원 힐은 MoveToWoundedAlly로 인접 후 추후 확장 예정.
class UseHealPotion:
	extends MonsterAI.BTNode

	func tick(actor: Monster, map: Map) -> MonsterAI.BTStatus:
		# 인벤토리에서 힐 포션 찾기
		var potion: Item = null
		for item in actor.inventory.to_array():
			if item.slug == &"health_potion":
				potion = item
				break
		if not potion:
			Log.d("[PartyAI] UseHealPotion: no health potion in inventory")
			return MonsterAI.BTStatus.FAILURE

		# 자신의 HP가 60% 미만이면 자신에게 사용
		var self_pct := float(actor.hp) / float(actor.max_hp)
		if self_pct < 0.6:
			actor.next_action = UseItemAction.new(actor, potion)
			Log.d("[PartyAI] UseHealPotion: using on self (HP=%.0f%%)" % (self_pct * 100))
			return MonsterAI.BTStatus.SUCCESS

		return MonsterAI.BTStatus.FAILURE


## 부상 파티원에게 이동
class MoveToWoundedAlly:
	extends MonsterAI.BTNode

	func tick(actor: Monster, map: Map) -> MonsterAI.BTStatus:
		if FindWoundedAlly.wounded_ally == null:
			return MonsterAI.BTStatus.FAILURE
		var actor_pos := map.find_monster_position(actor)
		var target_pos := map.find_monster_position(FindWoundedAlly.wounded_ally)
		if target_pos == Utils.INVALID_POS:
			return MonsterAI.BTStatus.FAILURE
		var move_dir := actor.get_next_step_towards_player(map, actor_pos, target_pos, true)
		if move_dir != Vector2i.ZERO:
			actor.next_action = MoveAction.new(actor, move_dir)
			Log.d("[PartyAI] MoveToWoundedAlly: moving toward %s" % FindWoundedAlly.wounded_ally.name)
			return MonsterAI.BTStatus.SUCCESS
		return MonsterAI.BTStatus.FAILURE


# ==========================================
# 📌 [구역 4] 로그 전용 노드 (ROGUE NODES)
# ==========================================

## 적 배후 위치 계산 및 이동 (flanking)
class FlankEnemy:
	extends MonsterAI.BTNode

	func tick(actor: Monster, map: Map) -> MonsterAI.BTStatus:
		if FindNearestEnemy.enemy_ref == null:
			return MonsterAI.BTStatus.FAILURE
		var actor_pos := map.find_monster_position(actor)
		var enemy := FindNearestEnemy.enemy_pos
		# 플레이어 위치를 기준으로 적 반대편 계산
		var player_pos := map.find_monster_position(World.player)
		var flank_dir := Vector2i(
			signi(enemy.x - player_pos.x),
			signi(enemy.y - player_pos.y)
		)
		# 배후 목표점 = 적 + 적-플레이어 방향
		var flank_target := enemy + flank_dir
		if map.is_in_bounds(flank_target) and map.get_cell(flank_target).is_walkable():
			var move_dir := actor.get_next_step_towards_player(map, actor_pos, flank_target, true)
			if move_dir != Vector2i.ZERO:
				actor.next_action = MoveAction.new(actor, move_dir)
				Log.d("[PartyAI] FlankEnemy: flanking to %s" % flank_target)
				return MonsterAI.BTStatus.SUCCESS
		# 배후 불가 시 정면 공격으로 폴백
		return MonsterAI.BTStatus.FAILURE


# ==========================================
# 📌 [구역 5] 팩토리 함수 (BT FACTORY)
# ==========================================

## 역할(Role)에 따라 파티원 전용 BT 생성
static func create_party_bt(
	monster: Monster, manager: PartyManager, follower_index: int
) -> MonsterAI.BTNode:
	Log.i("[PartyAI] Creating party BT for %s (role=%s, index=%d)" % [
		monster.name, Roles.Type.keys()[monster.role], follower_index
	])
	match monster.role:
		Roles.Type.FIGHTER:
			return _build_fighter_bt(manager, follower_index)
		Roles.Type.RANGER:
			return _build_ranger_bt(manager, follower_index)
		Roles.Type.CLERIC:
			return _build_cleric_bt(manager, follower_index)
		Roles.Type.ROGUE:
			return _build_rogue_bt(manager, follower_index)
		_:
			Log.w("[PartyAI] No specific BT for role, using default follow")
			return _build_default_bt(manager, follower_index)


## ⚔️ FIGHTER: 최전방 근접 탱커
## 우선순위: 적 발견 → 공격/돌진 > 플레이어 따라가기
static func _build_fighter_bt(manager: PartyManager, idx: int) -> MonsterAI.BTNode:
	return MonsterAI.selector(
		# 우선 1: 적이 있으면 공격 or 돌진
		MonsterAI.sequence(
			FindNearestEnemy.new(),
			MonsterAI.selector(
				AttackEnemy.new(),
				MoveTowardEnemy.new()
			)
		),
		# 우선 2: 적이 없으면 플레이어 따라가기
		FollowPlayerTrail.new(manager, idx),
		MonsterAI.DoNothing.new()
	)


## 🏹 RANGER: 원거리 카이팅 딜러
## 우선순위: 적 발견 → (너무 가까우면 도망) → 원거리 공격 > 따라가기
static func _build_ranger_bt(manager: PartyManager, idx: int) -> MonsterAI.BTNode:
	return MonsterAI.selector(
		# 우선 1: 적이 있을 때 원거리 전술
		MonsterAI.sequence(
			FindNearestEnemy.new(),
			MonsterAI.selector(
				# 1-a: 너무 가까우면 먼저 도망
				MonsterAI.sequence(
					CheckTooCloseToEnemy.new(3.0),
					FleeFromEnemy.new()
				),
				# 1-b: 사거리 안이면 발사
				FireAtEnemy.new(),
				# 1-c: 사거리 밖이면 접근
				MoveTowardEnemy.new()
			)
		),
		# 우선 2: 적 없으면 따라가기
		FollowPlayerTrail.new(manager, idx),
		MonsterAI.DoNothing.new()
	)


## 🙏 CLERIC: 후방 서포터 힐러
## 우선순위: 부상 파티원 힐 > 적 공격 > 따라가기
static func _build_cleric_bt(manager: PartyManager, idx: int) -> MonsterAI.BTNode:
	return MonsterAI.selector(
		# 우선 1: 부상 파티원 힐
		MonsterAI.sequence(
			FindWoundedAlly.new(manager),
			MonsterAI.selector(
				UseHealPotion.new(),
				MoveToWoundedAlly.new()
			)
		),
		# 우선 2: 인접 적 공격 (방어적)
		MonsterAI.sequence(
			FindNearestEnemy.new(),
			CheckEnemyAdjacent.new(),
			AttackEnemy.new()
		),
		# 우선 3: 따라가기
		FollowPlayerTrail.new(manager, idx),
		MonsterAI.DoNothing.new()
	)


## 🗡️ ROGUE: 히트앤런 배후 기습
## 우선순위: 적 측면 기동 → 인접 시 공격 → 후퇴 → 따라가기
static func _build_rogue_bt(manager: PartyManager, idx: int) -> MonsterAI.BTNode:
	return MonsterAI.selector(
		# 우선 1: 적이 있으면 측면 기동 후 공격
		MonsterAI.sequence(
			FindNearestEnemy.new(),
			MonsterAI.selector(
				# 인접하면 바로 공격
				MonsterAI.sequence(
					CheckEnemyAdjacent.new(),
					AttackEnemy.new()
				),
				# 아니면 측면 기동 시도
				FlankEnemy.new(),
				# 측면 불가 시 정면 접근
				MoveTowardEnemy.new()
			)
		),
		# 우선 2: 따라가기
		FollowPlayerTrail.new(manager, idx),
		MonsterAI.DoNothing.new()
	)


## 기본 BT (역할 없는 파티원)
static func _build_default_bt(manager: PartyManager, idx: int) -> MonsterAI.BTNode:
	return MonsterAI.selector(
		MonsterAI.sequence(
			FindNearestEnemy.new(),
			MonsterAI.selector(AttackEnemy.new(), MoveTowardEnemy.new())
		),
		FollowPlayerTrail.new(manager, idx),
		MonsterAI.DoNothing.new()
	)
