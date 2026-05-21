class_name FactionComponent
extends RefCounted

# =============================================================
# 🏴 [팩션 컴포넌트] FACTION COMPONENT
# =============================================================
# 팩션 소속, 플레이어와의 적대 관계 판정, 평판(reputation) 관리를 담당합니다.
# 추후 NPC 거래/대화 조건, 신앙 시스템과도 연결될 확장 지점입니다.

var faction: Factions.Type = Factions.Type.NONE
var hates_player: bool = false

# 추후 확장: 특정 팩션에 대한 개별 평판 수치
# var reputation: Dictionary = {}  # Factions.Type -> int (-100 ~ 100)

func _init() -> void:
	Log.d("[FactionComponent] Initialized")


# =============================================================
# 🔧 [구역 1] 적대 관계 판정 (HOSTILITY)
# =============================================================

## 이 컴포넌트를 가진 Monster가 other에게 적대적인지 판정
func is_hostile_to(other_faction: Factions.Type, other_behavior: int, other_is_player: bool) -> bool:
	if other_is_player:
		if hates_player:
			return true
		# World의 팩션 친밀도 테이블 참조
		if not faction in World.faction_affinities:
			return true
		var affinity: Variant = World.faction_affinities[faction]
		if affinity is int:
			return affinity < 0
		return true

	# PASSIVE 행동 유닛은 절대 적대 관계 없음
	# (Behavior enum은 Monster에 있으므로 int로 받아 비교)
	const BEHAVIOR_PASSIVE = 0  # Monster.Behavior.PASSIVE
	if other_behavior == BEHAVIOR_PASSIVE:
		return false

	return Factions.are_hostile(faction, other_faction)


# =============================================================
# 🔧 [구역 2] 팩션 정보 조회 (INFO)
# =============================================================

func get_faction_name() -> String:
	return Factions.get_faction_name(faction)
