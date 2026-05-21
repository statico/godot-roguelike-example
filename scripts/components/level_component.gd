class_name LevelComponent
extends RefCounted

# =============================================================
# 🌟 [레벨 컴포넌트] LEVEL COMPONENT
# =============================================================
# 캐릭터의 레벨, 누적 경험치, 레벨업 처리를 담당합니다.
# Progression 테이블을 참조하여 임계값을 계산합니다.

var level: int = 1
var experience: int = 0

# 부모 Monster 참조 (Object 타입으로 순환 참조 방지)
var _owner: Object


func _init(owner_monster: Object) -> void:
	_owner = owner_monster
	Log.d("[LevelComponent] Initialized")


# =============================================================
# 🔧 [구역 1] 조회 (QUERY)
# =============================================================

func xp_to_next() -> int:
	return Progression.xp_to_next(level, experience)


func xp_for_next_level() -> int:
	return Progression.xp_for_level(level + 1)


# =============================================================
# ➕ [구역 2] 경험치 추가 / 레벨업 (ADD EXPERIENCE)
# =============================================================

## 경험치를 추가하고, 레벨업이 발생하면 메시지 배열을 반환합니다.
func add_experience(amount: int) -> Array[String]:
	if level >= Progression.MAX_LEVEL:
		return []
	experience += amount
	var messages: Array[String] = []
	while level < Progression.MAX_LEVEL and experience >= Progression.xp_for_level(level + 1):
		level += 1
		var msg := _apply_level_up()
		messages.append(msg)
		Log.i("[LevelComponent] Leveled up to %d" % level)
	return messages


func _apply_level_up() -> String:
	var role: Roles.Type = Roles.Type.NONE
	var role_val = _owner.get("role") if _owner else null
	if role_val != null:
		role = role_val as Roles.Type

	var stats_comp: StatComponent = null
	var stats_val = _owner.get("stats") if _owner else null
	if stats_val is StatComponent:
		stats_comp = stats_val

	var hp_gain := Progression.hp_gain_for_role(role)
	if stats_comp:
		stats_comp.max_hp += hp_gain
		stats_comp.hp = mini(stats_comp.hp + hp_gain, stats_comp.max_hp)

	var msg := "Reached level %d! (+%d max HP)" % [level, hp_gain]

	if level in Progression.STR_GAIN_LEVELS and stats_comp:
		stats_comp._base_strength += 1
		msg += " (+1 STR)"

	return msg
