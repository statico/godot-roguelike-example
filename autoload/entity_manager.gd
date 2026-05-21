extends Node

# =============================================================
# 🗂️ [EntityManager] 엔티티 타입별 분류 관리자
# =============================================================
# World.current_map.get_monsters()는 플레이어/아군/적군을 모두 섞어서 반환한다.
# EntityManager는 그 위에서 타입별 조회를 제공하는 얇은 레이어다.
#
# 적군/중립군은 현재 맵에서 실시간으로 읽는다 (중복 저장 없음).
# 아군만 별도 목록으로 추적한다 (EventBus.ally_joined/ally_died 기반).
# =============================================================

var _allies: Array[Monster] = []


func _ready() -> void:
	EventBus.ally_joined.connect(_on_ally_joined)
	EventBus.ally_died.connect(_on_ally_died)
	World.world_initialized.connect(reset)


## 게임 재시작 시 상태 초기화
func reset() -> void:
	_allies.clear()
	Log.d("[EntityManager] reset")


# =============================================================
# 📋 쿼리 API
# =============================================================

func get_player() -> Monster:
	return World.player


func get_allies() -> Array[Monster]:
	return _allies.filter(func(m: Monster) -> bool: return not m.is_dead)


func get_enemies() -> Array[Monster]:
	if not World.current_map:
		return []
	return World.current_map.get_monsters().filter(func(m: Monster) -> bool:
		return m != World.player and not _allies.has(m) and m.is_hostile_to(World.player)
	)


func get_neutrals() -> Array[Monster]:
	if not World.current_map:
		return []
	return World.current_map.get_monsters().filter(func(m: Monster) -> bool:
		return m != World.player and not _allies.has(m) and not m.is_hostile_to(World.player)
	)


func get_all() -> Array[Monster]:
	if not World.current_map:
		return []
	return World.current_map.get_monsters()


func get_type(monster: Monster) -> EntityType.Type:
	if monster == World.player:
		return EntityType.Type.PLAYER
	if _allies.has(monster):
		return EntityType.Type.ALLY
	if monster.is_hostile_to(World.player):
		return EntityType.Type.ENEMY
	return EntityType.Type.NEUTRAL


func is_ally(monster: Monster) -> bool:
	return _allies.has(monster)


func is_enemy(monster: Monster) -> bool:
	return monster != World.player and not _allies.has(monster) and monster.is_hostile_to(World.player)


# =============================================================
# 🔌 내부 이벤트 핸들러
# =============================================================

func _on_ally_joined(follower: Monster) -> void:
	if not _allies.has(follower):
		_allies.append(follower)
		Log.d("[EntityManager] Ally registered: %s" % follower.name)


func _on_ally_died(follower: Monster) -> void:
	_allies.erase(follower)
	Log.d("[EntityManager] Ally removed: %s" % follower.name)
