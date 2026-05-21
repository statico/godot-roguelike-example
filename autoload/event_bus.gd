extends Node

# =============================================================
# 📡 [EVENT BUS] 전역 이벤트 버스
# =============================================================
# 게임 전체에서 발생하는 도메인 이벤트를 중앙에서 broadcast합니다.
# 발송자(Emitter)는 이 버스에 emit하고,
# 수신자(Listener)는 이 버스에 connect합니다.
# 시스템 간 직접 참조(coupling)를 최소화하기 위한 구조입니다.
#
# 사용법:
#   발송: EventBus.monster_killed.emit(killer, victim)
#   수신: EventBus.monster_killed.connect(_on_monster_killed)

# =============================================================
# ⚔️ [구역 1] 전투 이벤트 (COMBAT EVENTS)
# =============================================================

## 몬스터/유닛이 사망했을 때
## killer: 공격자 (null 가능 - 독, 함정 등 환경 피해)
## victim: 사망한 Monster
signal monster_killed(killer: Monster, victim: Monster)

## 데미지가 적중했을 때
## attacker: 공격자
## target: 피해를 입은 Monster
## damage: 최종 데미지 수치
## damage_type: Damage.Type
signal monster_damaged(attacker: Monster, target: Monster, damage: int, damage_type: int)

## 원거리 공격이 발사되었을 때
## shooter: 발사자
## target_pos: 조준 위치
signal ranged_attack_fired(shooter: Monster, target_pos: Vector2i)

## 근접 공격이 발동되었을 때 (명중 여부 무관)
## attacker: 공격자
## target: 피격 Monster
signal melee_attack_made(attacker: Monster, target: Monster)

## 전투 회차가 시작될 때 (턴 단위)
signal combat_turn_started(turn: int)

# =============================================================
# 🛡️ [구역 2] 파티 이벤트 (PARTY EVENTS)
# =============================================================

## 파티원이 합류했을 때
signal ally_joined(follower: Monster)

## 파티원이 사망했을 때
signal ally_died(follower: Monster)

## 파티원이 일정 HP 이하로 부상을 입었을 때 (threshold: 0.0~1.0 비율)
signal ally_injured(follower: Monster, hp_ratio: float)

## 파티원 간 위치 교환이 일어났을 때
signal allies_swapped(actor_a: Monster, actor_b: Monster)

# =============================================================
# 🗺️ [구역 3] 던전/맵 이벤트 (DUNGEON EVENTS)
# =============================================================

## 새 층(floor)에 진입했을 때
signal floor_entered(floor_num: int)

## 계단을 통해 이동했을 때
signal stairs_used(direction: int, floor_num: int)  # direction: +1 down, -1 up

## 방(room)에 처음 진입했을 때
signal room_discovered(room_pos: Vector2i)

# =============================================================
# 🎒 [구역 4] 아이템 이벤트 (ITEM EVENTS)
# =============================================================

## 아이템이 습득되었을 때
signal item_picked_up(actor: Monster, item: Item)

## 아이템이 사용되었을 때
signal item_used(actor: Monster, item: Item)

## 아이템이 장착되었을 때
signal item_equipped(actor: Monster, item: Item)

## 아이템이 해제되었을 때
signal item_unequipped(actor: Monster, item: Item)

# =============================================================
# 📊 [구역 5] 시스템 이벤트 (SYSTEM EVENTS)
# =============================================================

## 게임이 시작되었을 때 (새 게임 or 로드)
signal game_started

## 게임이 종료되었을 때 (사망 or 클리어)
## reason: "death" | "escape" | "victory"
signal game_ended(reason: String)

## 턴이 시작될 때
signal turn_started(turn: int)

## 턴이 종료될 때
signal turn_ended(turn: int)


func _ready() -> void:
	print("[EventBus] 초기화 완료 — 이벤트 버스 준비")
