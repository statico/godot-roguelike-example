extends Resource
class_name CharacterSheet

# =============================================================
# 📋 [구역 1] 기본 정보 (IDENTITY)
# =============================================================

@export var char_name: String = "Unknown"
@export var char_class: String = "Fighter"   ## DnD 5e Class
@export var char_species: String = "Human"   ## DnD 5e Species (2024 기준)
@export var char_level: int = 1
@export var proficiency_bonus: int = 2       ## Proficiency Bonus (레벨 기반)

# =============================================================
# 💪 [구역 2] 6대 능력치 (SIX ABILITY SCORES)
# =============================================================

@export var score_str: int = 10  ## STR (Strength)
@export var score_dex: int = 10  ## DEX (Dexterity)
@export var score_con: int = 10  ## CON (Constitution)
@export var score_int: int = 10  ## INT (Intelligence)
@export var score_wis: int = 10  ## WIS (Wisdom)
@export var score_cha: int = 10  ## CHA (Charisma)

# =============================================================
# ❤️ [구역 3] 전투 스탯 (COMBAT STATS)
# =============================================================

@export var max_hp: int = 10     ## Hit Points (최대)
var current_hp: int = 10         ## Hit Points (현재)
@export var armor_class: int = 10 ## Armor Class (AC)
@export var speed: int = 30       ## 이동 속도 (feet)

# =============================================================
# 🎯 [구역 4] 능력치 수식어 계산 (ABILITY MODIFIERS)
# =============================================================

## DnD 5e 공식: (score - 10) / 2 (내림)
static func get_modifier(score: int) -> int:
	return floori((score - 10) / 2.0)

func get_str_mod() -> int: return get_modifier(score_str)
func get_dex_mod() -> int: return get_modifier(score_dex)
func get_con_mod() -> int: return get_modifier(score_con)
func get_int_mod() -> int: return get_modifier(score_int)
func get_wis_mod() -> int: return get_modifier(score_wis)
func get_cha_mod() -> int: return get_modifier(score_cha)

# =============================================================
# ⚔️ [구역 5] 전투 계산 (COMBAT CALCULATIONS)
# =============================================================

## 이니셔티브 수식어 (DEX modifier)
func get_initiative_mod() -> int:
	return get_dex_mod()

## Proficiency Bonus 계산 (레벨 기반)
static func calc_proficiency_bonus(level: int) -> int:
	return ceili(level / 4.0) + 1

# =============================================================
# 💊 [구역 6] HP 관리 (HP MANAGEMENT)
# =============================================================

func take_damage(amount: int) -> void:
	current_hp = maxi(0, current_hp - amount)
	print("[CharacterSheet] %s HP: %d/%d (-%d)" % [char_name, current_hp, max_hp, amount])

func heal(amount: int) -> void:
	current_hp = mini(max_hp, current_hp + amount)
	print("[CharacterSheet] %s HP: %d/%d (+%d)" % [char_name, current_hp, max_hp, amount])

func is_alive() -> bool:
	return current_hp > 0

func is_bloodied() -> bool:
	return current_hp <= max_hp / 2

# =============================================================
# 🔧 [구역 7] 초기화 (INIT)
# =============================================================

func initialize() -> void:
	current_hp = max_hp
	proficiency_bonus = calc_proficiency_bonus(char_level)
	print("[CharacterSheet] %s (Lv.%d %s) 초기화 — HP:%d AC:%d" % [
		char_name, char_level, char_class, max_hp, armor_class
	])
