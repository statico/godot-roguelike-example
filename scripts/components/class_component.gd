class_name ClassComponent
extends RefCounted

# =============================================================
# 🎖️ [클래스 컴포넌트] CLASS COMPONENT
# =============================================================
# DnD 5e 클래스 특성을 담당합니다.
# 숙련, 내성 굴림 숙련, 클래스 특성(Second Wind 등)을 처리합니다.
# =============================================================

enum Type { NONE, FIGHTER, ROGUE, CLERIC, RANGER }

enum FightingStyle { NONE, ARCHERY, DEFENSE, DUELING, GREAT_WEAPON, PROTECTION, TWO_WEAPON }


## HUD 어빌리티 바에 표시되는 클래스 특성 슬롯 정보
class AbilitySlot:
	extends RefCounted
	var id: StringName = &""
	var display_name: String = ""
	var available: bool = false
	var cost: ActionBudget.Cost = ActionBudget.Cost.FREE
	var tooltip: String = ""

# 클래스별 내성 굴림 숙련 (인덱스: STR=0 DEX=1 CON=2 INT=3 WIS=4 CHA=5)
const CLASS_SAVE_PROFS: Dictionary = {
	Type.FIGHTER: [0, 2],  # STR, CON
	Type.ROGUE:   [1, 3],  # DEX, INT
	Type.CLERIC:  [4, 5],  # WIS, CHA
	Type.RANGER:  [0, 1],  # STR, DEX
}

var class_type: Type          = Type.NONE
var fighting_style: FightingStyle = FightingStyle.NONE

# 소모성 능력 (단휴식/장휴식으로 충전)
var second_wind_used:  bool = false
var action_surge_used: bool = false
var indomitable_uses:  int  = 0

var _owner: Object


func _init(owner: Object, p_type: Type) -> void:
	_owner = owner
	class_type = p_type


# =============================================================
# 🎯 [구역 1] 숙련 보너스
# =============================================================

func get_proficiency_bonus() -> int:
	var monster: Monster = _owner as Monster
	if not monster:
		return 2
	return CharacterSheet.calc_proficiency_bonus(monster.level)


## save_type_idx: STR=0 DEX=1 CON=2 INT=3 WIS=4 CHA=5
func is_save_proficient(save_type_idx: int) -> bool:
	if not CLASS_SAVE_PROFS.has(class_type):
		return false
	return save_type_idx in (CLASS_SAVE_PROFS[class_type] as Array)


func is_weapon_proficient(_item: Item) -> bool:
	match class_type:
		Type.FIGHTER: return true  # 모든 무기
		Type.ROGUE:   return true  # 단순 + 일부 마셜 (간소화)
		Type.RANGER:  return true  # 단순 + 마셜
		_:            return false


# =============================================================
# ⚔️ [구역 2] 전투 스타일 보너스
# =============================================================

## 방어 스타일: 방어구 착용 시 AC +1
func get_ac_bonus() -> int:
	if fighting_style != FightingStyle.DEFENSE:
		return 0
	var monster: Monster = _owner as Monster
	if not monster:
		return 0
	return 1 if not monster.equipment.get_all_equipped_items().is_empty() else 0


## 결투 스타일: 한손 근접무기 데미지 +2
func get_melee_damage_bonus(item: Item) -> int:
	if fighting_style != FightingStyle.DUELING or not item:
		return 0
	return 2


## 궁술 스타일: 원거리 공격 굴림 +2
func get_ranged_attack_bonus() -> int:
	return 2 if fighting_style == FightingStyle.ARCHERY else 0


# =============================================================
# 💨 [구역 3] 클래스 특성 사용
# =============================================================

## Second Wind: 보너스 액션으로 1d10 + 레벨 HP 회복.
## 반환값: 회복량 (이미 사용됐으면 -1)
func use_second_wind() -> int:
	if second_wind_used:
		return -1
	var monster: Monster = _owner as Monster
	if not monster:
		return -1
	second_wind_used = true
	var healed := Dice.roll(1, 10) + monster.level
	Log.i("[ClassComponent] Second Wind → +%d HP" % healed)
	return healed


## Action Surge: 이번 턴 액션 토큰 반환. 2레벨부터.
## budget.action_used 를 false 로 되돌려 액션을 하나 더 허용한다.
func use_action_surge(budget: ActionBudget) -> bool:
	if action_surge_used:
		return false
	var monster: Monster = _owner as Monster
	if not monster or monster.level < 2:
		return false
	action_surge_used  = true
	budget.action_used = false
	Log.i("[ClassComponent] Action Surge — 액션 추가 부여")
	return true


## Extra Attack: 레벨에 따른 1회 ACTION으로 때릴 수 있는 횟수.
func get_extra_attacks() -> int:
	if class_type != Type.FIGHTER:
		return 1
	var monster: Monster = _owner as Monster
	if not monster:
		return 1
	if   monster.level >= 20: return 4
	elif monster.level >= 11: return 3
	elif monster.level >= 5:  return 2
	return 1


## Indomitable: 실패한 내성 굴림 재굴림. 9레벨부터.
func _indomitable_max() -> int:
	var monster: Monster = _owner as Monster
	if not monster or class_type != Type.FIGHTER:
		return 0
	if   monster.level >= 17: return 3
	elif monster.level >= 13: return 2
	elif monster.level >= 9:  return 1
	return 0


func can_use_indomitable() -> bool:
	return indomitable_uses < _indomitable_max()


func use_indomitable() -> bool:
	if not can_use_indomitable():
		return false
	indomitable_uses += 1
	Log.i("[ClassComponent] Indomitable 사용 (%d/%d)" % [indomitable_uses, _indomitable_max()])
	return true


## 현재 사용 가능한 어빌리티 슬롯 목록 (HUD 렌더링용)
func get_ability_slots() -> Array[AbilitySlot]:
	var slots: Array[AbilitySlot] = []
	match class_type:
		Type.FIGHTER:
			var sw := AbilitySlot.new()
			sw.id = &"second_wind"
			sw.display_name = "Second Wind"
			sw.available = not second_wind_used
			sw.cost = ActionBudget.Cost.BONUS
			sw.tooltip = "1d10 + Lv HP 회복. 단휴식 충전."
			slots.append(sw)

			var surge := AbilitySlot.new()
			surge.id = &"action_surge"
			surge.display_name = "Action Surge"
			surge.available = not action_surge_used
			surge.cost = ActionBudget.Cost.FREE
			surge.tooltip = "이번 턴 주행동 추가 부여. 장휴식 충전."
			slots.append(surge)
	return slots


func on_short_rest() -> void:
	second_wind_used  = false
	action_surge_used = false


func on_long_rest() -> void:
	second_wind_used  = false
	action_surge_used = false
	indomitable_uses  = 0
