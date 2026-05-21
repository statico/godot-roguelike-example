class_name PartyManager
extends RefCounted

# ==========================================
# 🛡️ [파티 매니저] PARTY MANAGER
# ==========================================
# 플레이어 파티를 관리합니다.
# - 최대 2명의 AI 파티원 등록
# - 플레이어 이동 경로(breadcrumb trail) 기록
# - 역할(Role)에 따른 PartyAI BT 자동 배정
# - 맵 전환 시 파티원 이동 처리

# ==========================================
# 📌 [구역 1] 설정 상수 (CONFIG)
# ==========================================

## 최대 파티원 수 (플레이어 제외)
const MAX_FOLLOWERS: int = 2

## 기억할 플레이어 이동 경로 최대 길이
const TRAIL_LENGTH: int = 16

## 파티원간 간격 (경로 인덱스 단위)
const FOLLOWER_SPACING: int = 3

## 초기 배치 반경 (플레이어 주변 몇 칸 이내에 소환)
const SPAWN_RADIUS: int = 2

# ==========================================
# 📦 [구역 2] 상태 변수 (STATE)
# ==========================================

## 등록된 파티원 목록 (플레이어 제외)
var party_followers: Array[Monster] = []

## 플레이어가 최근에 밟은 타일 위치 (최신 → 오래된 순)
var _player_trail: Array[Vector2i] = []

# ==========================================
# 🔧 [구역 3] 공개 API (PUBLIC API)
# ==========================================

## 파티원 등록 및 BT 배정
func add_follower(follower: Monster) -> void:
	if party_followers.size() >= MAX_FOLLOWERS:
		Log.w("[PartyManager] add_follower: party is full (max=%d)" % MAX_FOLLOWERS)
		return
	var idx := party_followers.size()
	party_followers.append(follower)
	_assign_party_bt(follower, idx)
	# [EventBus] 파티원 합류 이벤트 발송
	EventBus.ally_joined.emit(follower)
	Log.i("[PartyManager] Follower added: %s  role=%s  index=%d" % [
		follower.name, Roles.Type.keys()[follower.role], idx
	])


## 플레이어가 이동할 때마다 호출 — 경로 기록
func record_player_position(pos: Vector2i) -> void:
	# 같은 자리 중복 기록 방지
	if _player_trail.is_empty() or _player_trail[0] != pos:
		_player_trail.push_front(pos)
		if _player_trail.size() > TRAIL_LENGTH:
			_player_trail.pop_back()


## follower_index 번째 파티원이 따라가야 할 목표 타일 반환
func get_trail_target(follower_index: int) -> Vector2i:
	var step := (follower_index + 1) * FOLLOWER_SPACING
	if _player_trail.size() > step:
		return _player_trail[step]
	elif not _player_trail.is_empty():
		return _player_trail[_player_trail.size() - 1]
	return Utils.INVALID_POS


## 살아있는 파티원만 반환 (사망 감지 포함)
func get_living_followers() -> Array[Monster]:
	var alive: Array[Monster] = []
	for f in party_followers:
		if not f.is_dead:
			alive.append(f)
		else:
			# [EventBus] 파티원 사망 이벤트 발송 (최초 1회만)
			if not f.get_meta("death_event_emitted", false):
				f.set_meta("death_event_emitted", true)
				EventBus.ally_died.emit(f)
				Log.i("[PartyManager] Ally died: %s" % f.name)
	return alive


## 이전 맵에서 파티원들 제거 (레벨 전환 준비용)
func remove_followers_from_map(map: Map) -> void:
	for follower in party_followers:
		if not follower.is_dead:
			var removed := map.find_and_remove_monster(follower)
			if removed:
				Log.d("[PartyManager] Removed %s from old map" % follower.name)


## 맵 전환 시 파티원들도 새 맵에 배치
func on_map_changed(new_map: Map, stairs_type: Obstacle.Type) -> void:
	Log.i("[PartyManager] on_map_changed: placing %d followers" % party_followers.size())
	_player_trail.clear()  # 경로 초기화

	var player_pos := new_map.find_monster_position(World.player)
	if player_pos == Utils.INVALID_POS:
		Log.e("[PartyManager] on_map_changed: player not on new map!")
		return

	for i in party_followers.size():
		var follower := party_followers[i]
		if follower.is_dead:
			continue
		var placed := _place_near(new_map, follower, player_pos)
		if placed:
			Log.i("[PartyManager] Placed %s near stairs" % follower.name)
		else:
			Log.w("[PartyManager] Could not place %s — no free tile found" % follower.name)


## 파티원 전체 제거 (게임 재시작용)
func reset() -> void:
	party_followers.clear()
	_player_trail.clear()
	Log.i("[PartyManager] reset: party cleared")

# ==========================================
# 🤖 [구역 4] AI 배정 (BT ASSIGNMENT)
# ==========================================

func _assign_party_bt(follower: Monster, idx: int) -> void:
	follower.behavior_tree = PartyAI.create_party_bt(follower, self, idx)

# ==========================================
# 🗺️ [구역 5] 내부 유틸 (INTERNAL UTILS)
# ==========================================

## 주어진 위치 주변에 빈 타일을 찾아 monster를 배치
func _place_near(map: Map, monster: Monster, center: Vector2i) -> bool:
	# BFS로 가장 가까운 빈 타일 탐색
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [center]
	visited[center] = true

	while not queue.is_empty():
		var pos: Vector2i = queue.pop_front()
		var cell := map.get_cell(pos)
		if cell.is_walkable() and cell.monster == null and pos != center:
			cell.monster = monster
			Log.d("[PartyManager] _place_near: placed %s at %s" % [monster.name, pos])
			return true

		# 인접 타일 추가
		for dir: Vector2i in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var next: Vector2i = pos + dir
			if map.is_in_bounds(next) and not visited.has(next):
				visited[next] = true
				queue.append(next)

		# 반경이 너무 커지면 중단
		if pos.distance_to(center) > SPAWN_RADIUS + 2:
			break

	return false
