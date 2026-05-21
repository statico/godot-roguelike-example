class_name Progression
extends RefCounted

# =============================================================
# 📈 [PROGRESSION] 경험치/레벨/스킬 성장 테이블
# =============================================================
# 레벨업 XP 임계값, 역할별 HP 성장, 스킬 XP 임계값을 중앙 관리합니다.

const MAX_LEVEL := 20

# XP_TABLE[level] = 해당 레벨에 도달하기 위한 누적 XP
# 인덱스 0은 사용하지 않음 (레벨은 1부터 시작)
const XP_TABLE: Array[int] = [
	0,       # 미사용 (index 0)
	0,       # 레벨 1 (시작)
	300,     # 레벨 2
	900,     # 레벨 3
	2700,    # 레벨 4
	6500,    # 레벨 5
	14000,   # 레벨 6
	23000,   # 레벨 7
	34000,   # 레벨 8
	48000,   # 레벨 9
	64000,   # 레벨 10
	85000,   # 레벨 11
	100000,  # 레벨 12
	120000,  # 레벨 13
	140000,  # 레벨 14
	165000,  # 레벨 15
	195000,  # 레벨 16
	225000,  # 레벨 17
	265000,  # 레벨 18
	305000,  # 레벨 19
	355000,  # 레벨 20
]

# 역할(Role)별 레벨당 최대 HP 증가량 (D&D Hit Die 기반)
const HP_PER_LEVEL: Dictionary = {
	Roles.Type.FIGHTER: 10,  # d10
	Roles.Type.RANGER:  6,   # d8
	Roles.Type.CLERIC:  8,   # d8
	Roles.Type.ROGUE:   6,   # d8
	Roles.Type.NONE:    4,   # d6
}

# 이 레벨에서 +1 STR 획득 (4, 8, 12, 16, 20레벨)
const STR_GAIN_LEVELS: Array[int] = [4, 8, 12, 16, 20]

# 스킬 레벨별 다음 단계까지 필요한 XP (현재 레벨 → 다음 레벨)
const SKILL_XP_PER_LEVEL: Dictionary = {
	Skills.Level.UNSKILLED:    100,
	Skills.Level.BASIC:        300,
	Skills.Level.INTERMEDIATE: 700,
	Skills.Level.ADVANCED:     1500,
	Skills.Level.EXPERT:       3000,
	# MASTER는 최대 등급, 다음 레벨 없음
}


## 해당 레벨에 도달하기 위한 누적 XP 반환
static func xp_for_level(level: int) -> int:
	if level < 1 or level >= XP_TABLE.size():
		return 0
	return XP_TABLE[level]


## 현재 레벨/XP에서 다음 레벨까지 남은 XP
static func xp_to_next(current_level: int, current_xp: int) -> int:
	if current_level >= MAX_LEVEL:
		return 0
	return maxi(0, xp_for_level(current_level + 1) - current_xp)


## 역할에 따른 레벨당 HP 증가량
static func hp_gain_for_role(role: Roles.Type) -> int:
	return HP_PER_LEVEL.get(role, HP_PER_LEVEL[Roles.Type.NONE])


## 현재 스킬 레벨에서 다음 단계까지 필요한 XP
static func skill_xp_to_next(current: Skills.Level) -> int:
	return SKILL_XP_PER_LEVEL.get(current, 0)
