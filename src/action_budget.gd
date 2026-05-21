class_name ActionBudget
extends RefCounted

# =============================================================
# 🎯 [ActionBudget] 유닛당 1라운드 행동 토큰 추적기
# =============================================================
# D&D 5e 행동 경제학:
#   주행동(Action)   — 공격, 주문, 대시, 회피, 아이템 사용 등
#   보조행동(Bonus)  — 클래스 특기, 보조 공격 등
#   반응행동(Reaction)— 기회 공격, 방패 주문 등 (남의 턴에도 가능)
#   이동(Move)       — 남은 이동력 (타일 단위)
# =============================================================

## 각 행동이 어떤 토큰을 소모하는지 선언하는 열거형
## BaseAction.action_cost 에서 사용됨
enum Cost {
	ACTION,    ## 주행동
	BONUS,     ## 보조행동
	REACTION,  ## 반응행동
	MOVE,      ## 이동 (movement_remaining 감소)
	FREE,      ## 무료 행동 (토큰 소모 없음)
}

var action_used:   bool = false
var bonus_used:    bool = false
var reaction_used: bool = false
var movement_remaining: int = 0

## 최대 이동력 (reset 시 채워짐)
var _max_movement: int = 0

## 이 라운드에 실행된 행동 로그 (LLM 학습용)
var action_log: Array[Dictionary] = []


func reset(speed_tiles: int) -> void:
	action_used        = false
	bonus_used         = false
	reaction_used      = false
	movement_remaining = speed_tiles
	_max_movement      = speed_tiles
	action_log.clear()


## 지정한 Cost 타입의 토큰이 남아 있는지 확인
func can_use(cost: Cost) -> bool:
	match cost:
		Cost.ACTION:   return not action_used
		Cost.BONUS:    return not bonus_used
		Cost.REACTION: return not reaction_used
		Cost.MOVE:     return movement_remaining > 0
		Cost.FREE:     return true
	return false


## 토큰 소모. 이동은 tiles 수 만큼 감소.
func spend(cost: Cost, tiles: int = 1) -> void:
	match cost:
		Cost.ACTION:   action_used   = true
		Cost.BONUS:    bonus_used    = true
		Cost.REACTION: reaction_used = true
		Cost.MOVE:     movement_remaining = maxi(0, movement_remaining - tiles)
		Cost.FREE:     pass


## 주행동 + 보조행동이 모두 소모되었으면 자동 턴 종료 가능
func is_turn_exhausted() -> bool:
	return action_used and bonus_used


## 디버그/LLM 용 스냅샷 딕셔너리
func to_dict() -> Dictionary:
	return {
		"action_used":         action_used,
		"bonus_used":          bonus_used,
		"reaction_used":       reaction_used,
		"movement_remaining":  movement_remaining,
		"movement_max":        _max_movement,
	}


## 행동 실행 기록 (BattleLogger → LLM 학습 데이터)
func log_action(
	cost: Cost,
	action_name: String,
	success: bool,
	extra: Dictionary = {}
) -> void:
	var entry := {
		"cost":    Cost.keys()[cost],
		"action":  action_name,
		"success": success,
		"budget":  to_dict(),
	}
	entry.merge(extra)
	action_log.append(entry)


func _to_string() -> String:
	return (
		"Budget[A:%s B:%s R:%s Move:%d/%d]"
		% [
			"✓" if not action_used   else "✗",
			"✓" if not bonus_used    else "✗",
			"✓" if not reaction_used else "✗",
			movement_remaining,
			_max_movement,
		]
	)
