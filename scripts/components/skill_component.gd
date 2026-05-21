class_name SkillComponent
extends RefCounted

# =============================================================
# ⚔️ [스킬 컴포넌트] SKILL COMPONENT
# =============================================================
# 스킬 레벨 저장, 명중 보너스 조회, 경험치 및 스킬 성장을 담당합니다.
# 추후 레벨업 시스템, 스킬 트리와 연결될 확장 지점입니다.

# 스킬별 레벨 저장 (기본값: 모두 UNSKILLED)
var levels: Dictionary = {
	Skills.Type.KNIFE:    Skills.Level.UNSKILLED,
	Skills.Type.SWORD:    Skills.Level.UNSKILLED,
	Skills.Type.HAMMER:   Skills.Level.UNSKILLED,
	Skills.Type.SPEAR:    Skills.Level.UNSKILLED,
	Skills.Type.FISTS:    Skills.Level.UNSKILLED,
	Skills.Type.UTILITY:  Skills.Level.UNSKILLED,
	Skills.Type.THROWING: Skills.Level.UNSKILLED,
	Skills.Type.BOW:      Skills.Level.UNSKILLED,
}

# 스킬별 누적 XP (다음 레벨까지 필요한 XP 대비)
var skill_xp: Dictionary = {}  # Skills.Type -> int


func _init() -> void:
	Log.d("[SkillComponent] Initialized")


# =============================================================
# 🔧 [구역 1] 스킬 조회 (QUERY)
# =============================================================

func get_level(skill_type: Skills.Type) -> Skills.Level:
	return levels.get(skill_type, Skills.Level.UNSKILLED)


func get_hit_bonus(skill_type: Skills.Type) -> float:
	return Skills.get_hit_bonus(get_level(skill_type))


func get_all_trained_skills() -> Dictionary:
	var trained: Dictionary = {}
	for skill_type: Skills.Type in levels:
		if levels[skill_type] > Skills.Level.UNSKILLED:
			trained[skill_type] = levels[skill_type]
	return trained


# =============================================================
# ➕ [구역 2] 스킬 수정 (MUTATION)
# =============================================================

func set_level(skill_type: Skills.Type, level: Skills.Level) -> void:
	levels[skill_type] = level
	Log.d("[SkillComponent] Skill set: %s → %s" % [
		Skills.Type.keys()[skill_type], Skills.Level.keys()[level]
	])


## 스킬 XP를 추가하고, 레벨업이 발생하면 알림 메시지 배열을 반환합니다.
func add_skill_xp(skill_type: Skills.Type, amount: int) -> Array[String]:
	var current: int = levels.get(skill_type, Skills.Level.UNSKILLED)
	if current >= Skills.Level.MASTER:
		return []

	skill_xp[skill_type] = skill_xp.get(skill_type, 0) + amount

	var messages: Array[String] = []
	var threshold := Progression.skill_xp_to_next(current as Skills.Level)
	while threshold > 0 and skill_xp.get(skill_type, 0) >= threshold:
		skill_xp[skill_type] -= threshold
		current += 1
		levels[skill_type] = current
		var skill_name: String = Skills.Type.keys()[skill_type].to_lower().replace("_", " ")
		var level_name: String = Skills.Level.keys()[current].to_lower().replace("_", " ")
		messages.append("Your %s skill improved to %s!" % [skill_name, level_name])
		Log.i("[SkillComponent] %s skill → %s" % [Skills.Type.keys()[skill_type], Skills.Level.keys()[current]])
		if current >= Skills.Level.MASTER:
			break
		threshold = Progression.skill_xp_to_next(current as Skills.Level)

	return messages
