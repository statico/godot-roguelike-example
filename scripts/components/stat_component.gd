class_name StatComponent
extends RefCounted

# =============================================================
# 📊 [스탯 컴포넌트] STAT COMPONENT
# =============================================================
# HP, 기본 능력치, AC, 이동속도, HP재생, 운반 용량을 담당합니다.
# 상태이상에 의한 수치 수정은 StatusComponent에서 값을 받아 계산합니다.

# --- 속도 상수 ---
const SPEED_VERY_SLOW := 3
const SPEED_SLOW      := 6
const SPEED_NORMAL    := 12
const SPEED_FAST      := 18
const SPEED_VERY_FAST := 24

# --- 기본 수치 ---
var hp: int = 1
var max_hp: int = 1
var _base_strength: int = 5
var _base_speed: int = SPEED_NORMAL
var _base_hp_regen: int = 1

# --- D&D 능력치 (세이빙 스로우 / 이니셔티브용) ---
var _base_dexterity: int = 10
var _base_constitution: int = 10
var _base_wisdom: int = 10

# --- 부모 Monster 참조 (StatusComponent 접근용) ---
# Object 타입으로 선언해 순환 참조 파싱 오류 방지.
# 실제 Monster 인스턴스가 들어오므로 안전합니다.
var _owner: Object

func _init(owner_monster: Object) -> void:
	_owner = owner_monster
	Log.d("[StatComponent] Initialized")


# =============================================================
# 🔧 [구역 1] 능력치 조회 (STAT GETTERS)
# =============================================================

func get_strength() -> int:
	var strength := _base_strength
	if _owner and _owner.get("status") and _owner.status.has_effect(StatusEffect.Type.STIM):
		var stim: StatusEffect = _owner.status.get_effect(StatusEffect.Type.STIM)
		strength += 3 * stim.magnitude
	return strength


func get_speed() -> int:
	var status_comp = _owner.get("status") if _owner else null
	if status_comp:
		if status_comp.has_effect(StatusEffect.Type.OVERTAXED):
			return SPEED_VERY_SLOW
		elif status_comp.has_effect(StatusEffect.Type.BURDENED):
			return SPEED_SLOW

	var speed := _base_speed
	if status_comp:
		if status_comp.has_effect(StatusEffect.Type.STIM):
			var stim: StatusEffect = status_comp.get_effect(StatusEffect.Type.STIM)
			match stim.magnitude:
				1:
					speed = mini(SPEED_VERY_FAST, speed + 6)
				_:
					speed = SPEED_VERY_FAST
		elif status_comp.has_effect(StatusEffect.Type.STIM_RECOVERY):
			speed = maxi(SPEED_VERY_SLOW, speed - SPEED_SLOW)
	return speed


func get_dexterity() -> int:
	return _base_dexterity


func get_constitution() -> int:
	return _base_constitution


func get_wisdom() -> int:
	return _base_wisdom


func get_hp_regen() -> int:
	var regen := _base_hp_regen
	var status_comp = _owner.get("status") if _owner else null
	if status_comp:
		if status_comp.has_effect(StatusEffect.Type.STIM):
			var stim: StatusEffect = status_comp.get_effect(StatusEffect.Type.STIM)
			regen += stim.magnitude
		elif status_comp.has_effect(StatusEffect.Type.STIM_RECOVERY):
			regen = 0
	return regen


func get_armor_class(equipment: Equipment) -> int:
	var total_ac := 0
	for item: Item in equipment.get_all_equipped_items():
		total_ac += item.armor_class
		for child: Item in item.children.to_array():
			if child:
				total_ac += child.armor_class
	return total_ac


# =============================================================
# 🎒 [구역 2] 운반 용량 (CARRYING CAPACITY)
# =============================================================

func get_max_carrying_capacity(role: Roles.Type) -> int:
	var base_capacity := 25 + (get_strength() * 25)
	if role == Roles.Type.FIGHTER:
		base_capacity += 50
	return base_capacity


func get_current_load(inventory: Set, equipment: Equipment) -> int:
	var total_mass := 0
	for item: Item in inventory.to_array():
		total_mass += int(item.get_mass())
	for item in equipment.get_all_equipped_items():
		total_mass += int(item.get_mass())
	return total_mass
