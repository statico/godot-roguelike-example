class_name Monster
extends RefCounted

# =============================================================
# 👾 [Monster] 유닛 컨테이너
# =============================================================
# Monster는 컴포넌트를 보유하는 thin container입니다.
# 실제 로직은 각 컴포넌트에 위임합니다.
#
# 컴포넌트 구조:
#   stats    → StatComponent     (HP, STR, SPD, AC, 운반)
#   status   → StatusComponent   (상태이상 추가/제거/틱)
#   faction  → FactionComponent  (팩션, 적대 판정)
#   skills   → SkillComponent    (스킬 레벨, 명중 보너스)
#   inv      → InventoryComponent(인벤토리 추가/제거/드랍)
#
# 하위 호환을 위해 기존 프로퍼티/메서드명은 위임(delegate)으로 유지합니다.
# =============================================================

enum Behavior {
	PASSIVE,    # Doesn't actively pursue targets
	AGGRESSIVE, # Pursues and attacks targets
	FEARFUL,    # Runs away from threats
	CURIOUS,    # Follows player but doesn't attack
}

enum NameFormat {
	THE,
	AN,
	PLAIN,
	CAPITALIZED,
}

# 속도 상수 (StatComponent의 값을 재노출)
const SPEED_VERY_SLOW := StatComponent.SPEED_VERY_SLOW
const SPEED_SLOW      := StatComponent.SPEED_SLOW
const SPEED_NORMAL    := StatComponent.SPEED_NORMAL
const SPEED_FAST      := StatComponent.SPEED_FAST
const SPEED_VERY_FAST := StatComponent.SPEED_VERY_FAST

# =============================================================
# 📦 [구역 1] 컴포넌트 (COMPONENTS)
# =============================================================

var stats:      StatComponent
var status:     StatusComponent
var faction_comp: FactionComponent
var skills:     SkillComponent
var inv:        InventoryComponent
var level_comp: LevelComponent

# =============================================================
# 📌 [구역 2] 불변 식별 속성 (IDENTITY)
# =============================================================

var slug: StringName
var name: String
var species: Species.Type
var variant: int = 0
var hit_particles_color := Color(1.0, 0.1, 0.1)
var role: Roles.Type = Roles.Type.NONE
var intelligence: int = 5
var xp_reward: int = 0
var instance_id: int = 0
var behavior: Behavior
var sight_radius: int

# Body part properties (장비 슬롯 제한용)
var has_head: bool  = true
var has_torso: bool = true
var has_legs: bool  = true
var has_hands: bool = true

# =============================================================
# 📌 [구역 3] AI / 행동 관련 (AI & BEHAVIOR)
# =============================================================

var behavior_tree: MonsterAI.BTNode
var next_action: ActorAction

# =============================================================
# 📌 [구역 4] 장비 (EQUIPMENT)
# =============================================================

var equipment: Equipment

# =============================================================
# ⬇️ [구역 5] 하위 호환 위임 프로퍼티 (DELEGATE PROPERTIES)
# =============================================================
# 기존 코드에서 monster.hp, monster.faction 등으로 직접 접근하는
# 코드들이 수정 없이 동작하도록 위임 프로퍼티를 유지합니다.

var hp: int:
	get: return stats.hp
	set(v): stats.hp = v

var max_hp: int:
	get: return stats.max_hp
	set(v): stats.max_hp = v

var is_dead: bool = false

var faction: Factions.Type:
	get: return faction_comp.faction
	set(v): faction_comp.faction = v

var hates_player: bool:
	get: return faction_comp.hates_player
	set(v): faction_comp.hates_player = v

## 하위 호환: skill_levels 딕셔너리 직접 접근
var skill_levels: Dictionary:
	get: return skills.levels
	set(v): skills.levels = v

## 하위 호환: status_effects 배열 직접 접근
var status_effects: Array[StatusEffect]:
	get: return status.get_all_effects()

## 하위 호환: inventory Set 직접 접근
var inventory: Set:
	get: return inv.items

## 하위 호환: nutrition (기존 Nutrition 객체 유지)
var nutrition := Nutrition.new()

## 하위 호환: energy
var energy: int = 0

## 레벨 / XP 위임
var level: int:
	get: return level_comp.level
	set(v): level_comp.level = v

var experience: int:
	get: return level_comp.experience
	set(v): level_comp.experience = v

## 하위 호환: _base_strength
var _base_strength: int:
	get: return stats._base_strength
	set(v): stats._base_strength = v

## 하위 호환: _base_speed
var _base_speed: int:
	get: return stats._base_speed
	set(v): stats._base_speed = v

## 하위 호환: _base_hp_regen
var _base_hp_regen: int:
	get: return stats._base_hp_regen
	set(v): stats._base_hp_regen = v

# =============================================================
# 🔧 [구역 6] 초기화 (INIT)
# =============================================================

func _init(constructed_via_factory: bool = false) -> void:
	assert(constructed_via_factory, "Monsters must be created through MonsterFactory")
	stats        = StatComponent.new(self)
	status       = StatusComponent.new(self)
	faction_comp = FactionComponent.new()
	skills       = SkillComponent.new()
	inv          = InventoryComponent.new()
	level_comp   = LevelComponent.new(self)
	equipment    = Equipment.new(self)
	instance_id  = InstanceID.register(self)
	Log.d("[Monster] Components initialized")


func _to_string() -> String:
	return get_name(NameFormat.PLAIN)

# =============================================================
# 🔧 [구역 7] 이름 / 정보 표시 (DISPLAY)
# =============================================================

func get_name(format: NameFormat = NameFormat.THE) -> String:
	if self == World.player:
		match format:
			NameFormat.CAPITALIZED:
				return "You"
			NameFormat.THE:
				return "the player"
			_:
				return "you"

	var n := name
	match format:
		NameFormat.THE:
			return "the " + n
		NameFormat.AN:
			return ("an " if n[0] in ["a", "e", "i", "o", "u"] else "a ") + n
		NameFormat.PLAIN:
			return n
		NameFormat.CAPITALIZED:
			return "The " + n
	return "the " + n


func get_hover_info() -> String:
	var info := ""

	if self == World.player:
		info += get_name(NameFormat.CAPITALIZED) + "\n"
		info += ("a %s %s\n" % [Species.Type.keys()[species], Roles.Type.keys()[role]]).to_lower()
		info += "Level %d — XP: %d / %d\n" % [level, experience, level_comp.xp_for_next_level()]
	else:
		info += get_name(NameFormat.CAPITALIZED) + "\n"

	info += (
		"HP: %d/%d - STR: %d - INT: %d - AC: %d\n"
		% [hp, max_hp, get_strength(), intelligence, get_armor_class()]
	)
	info += "Speed: "
	match get_speed():
		SPEED_VERY_SLOW: info += "Very Slow"
		SPEED_SLOW:      info += "Slow"
		SPEED_NORMAL:    info += "Normal"
		SPEED_FAST:      info += "Fast"
		SPEED_VERY_FAST: info += "Very Fast"
	info += "\n"

	info += "Faction: %s\n" % faction_comp.get_faction_name()
	info += "Behavior: "
	match behavior:
		Behavior.PASSIVE:    info += "Peaceful"
		Behavior.AGGRESSIVE: info += "Hostile"
		Behavior.FEARFUL:    info += "Cowardly"
		Behavior.CURIOUS:    info += "Inquisitive"

	info += "\n\nResistances:"
	var resistances := get_resistances()
	if resistances.is_empty():
		info += "\nNone"
	else:
		for damage_type: Damage.Type in resistances:
			info += "\n• %s: %d" % [Damage.Type.keys()[damage_type], resistances[damage_type]]

	var equipped_items := equipment.get_all_equipped_items()
	if not equipped_items.is_empty():
		info += "\n\nEquipped:"
		for item in equipped_items:
			info += "\n• " + item.get_name()

	var trained := skills.get_all_trained_skills()
	if not trained.is_empty():
		info += "\n\nSkills:"
		for skill_type: Skills.Type in trained:
			info += "\n• %s: %s" % [Skills.Type.keys()[skill_type], Skills.Level.keys()[trained[skill_type]]]

	return info

# =============================================================
# 🔧 [구역 8] 스탯 위임 메서드 (STAT DELEGATES)
# =============================================================

func get_strength() -> int:
	return stats.get_strength()

func get_speed() -> int:
	return stats.get_speed()

func get_hp_regen() -> int:
	return stats.get_hp_regen()

func get_armor_class() -> int:
	return stats.get_armor_class(equipment)

func get_resistances() -> Dictionary:
	var resistances: Dictionary = {}
	var species_resistances := Species.get_resistances()
	assert(species_resistances.has(species), "No resistances defined for species %s" % Species.Type.keys()[species])
	for resistance: Damage.Type in species_resistances[species]:
		if resistance not in resistances:
			resistances[resistance] = 0
		resistances[resistance] += 1
	for item in equipment.get_all_equipped_items():
		for resistance: Damage.Type in item.resistances:
			if resistance not in resistances:
				resistances[resistance] = 0
			resistances[resistance] += 1
			for child: Item in item.children.to_array():
				if child:
					for r: Damage.Type in child.resistances:
						if r not in resistances:
							resistances[r] = 0
						resistances[r] += 1
	return resistances

func get_max_carrying_capacity() -> int:
	return stats.get_max_carrying_capacity(role)

func get_current_load() -> int:
	return stats.get_current_load(inv.items, equipment)

# =============================================================
# 🔧 [구역 9] 스킬 위임 메서드 (SKILL DELEGATES)
# =============================================================

func get_skill_level(skill_type: Skills.Type) -> Skills.Level:
	return skills.get_level(skill_type)

func get_skill_hit_bonus(skill_type: Skills.Type) -> float:
	return skills.get_hit_bonus(skill_type)

# =============================================================
# 🔧 [구역 10] 상태이상 위임 메서드 (STATUS DELEGATES)
# =============================================================

func has_status_effect(type: StatusEffect.Type) -> bool:
	return status.has_effect(type)

func get_status_effect(type: StatusEffect.Type) -> StatusEffect:
	return status.get_effect(type)

func add_status_effect(type: StatusEffect.Type, magnitude: int = 1) -> void:
	status.add_effect(type, magnitude)

func apply_status_effect(type: StatusEffect.Type, turns: int, magnitude: int = 1) -> void:
	status.apply_effect(type, turns, magnitude)

func remove_status_effect(type: StatusEffect.Type) -> StatusEffect:
	return status.remove_effect(type)

func tick_status_effects() -> void:
	status.tick(name)

# =============================================================
# 🔧 [구역 11] 인벤토리 위임 메서드 (INVENTORY DELEGATES)
# =============================================================

func add_item(item: Item) -> void:
	inv.add(item)

func remove_item(item: Item, quantity: int = 1) -> bool:
	var removed := inv.remove(item, quantity)
	if removed:
		equipment.unequip_item(item)
	return removed

func has_item(item: Item) -> bool:
	return inv.has(item)

func drop_everything() -> void:
	var pos := World.current_map.find_monster_position(self)
	inv.drop_all_to_map(equipment, pos, World.current_map)

# =============================================================
# 🔧 [구역 12] 팩션 위임 메서드 (FACTION DELEGATES)
# =============================================================

func is_hostile_to(other: Monster) -> bool:
	return faction_comp.is_hostile_to(
		other.faction,
		other.behavior,
		other == World.player
	)

# =============================================================
# 🔧 [구역 13] AI / 이동 유틸 (AI & PATHFINDING)
# =============================================================

func get_next_action(map: Map) -> ActorAction:
	next_action = null
	Log.i("Get next action for %s" % self)
	behavior_tree.tick(self, map)
	Log.d("  Next action: %s" % next_action)
	return next_action

func is_adjacent_to(pos1: Vector2i, pos2: Vector2i) -> bool:
	return abs(pos1.x - pos2.x) <= 1 and abs(pos1.y - pos2.y) <= 1

func get_safe_move_direction(map: Map, start: Vector2i, preferred_dir: Vector2i) -> Vector2i:
	return Pathfinding.get_safe_move_direction(map, start, preferred_dir)

func get_next_step_towards_player(
	map: Map, start: Vector2i, target: Vector2i, avoid_monsters: bool = false
) -> Vector2i:
	return Pathfinding.get_next_step(map, start, target, avoid_monsters)

# =============================================================
# 🔧 [구역 14] 인카운터 틱 (ENCUMBRANCE TICK)
# =============================================================

func tick_encumbrance() -> void:
	var current_load := get_current_load()
	var max_capacity := get_max_carrying_capacity()

	status.remove_effect(StatusEffect.Type.BURDENED)
	status.remove_effect(StatusEffect.Type.OVERTAXED)

	if current_load >= max_capacity * 2:
		status.add_effect(StatusEffect.Type.OVERTAXED)
	elif current_load >= max_capacity:
		status.add_effect(StatusEffect.Type.BURDENED)
