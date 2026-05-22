class_name ClassComponent
extends RefCounted

# =============================================================
# 🎖️ [클래스 컴포넌트] CLASS COMPONENT
# =============================================================
# DnD 5e 클래스 특성을 담당합니다.
# 숙련, 내성 굴림 숙련, 클래스 특성(Second Wind 등)을 처리합니다.
# =============================================================

enum Type { NONE, FIGHTER, ROGUE, CLERIC, RANGER, BARBARIAN }

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
	Type.BARBARIAN: [0, 2], # STR, CON
}

var class_type: Type          = Type.NONE
var fighting_style: FightingStyle = FightingStyle.NONE

# 소모성 능력 (단휴식/장휴식으로 충전)
var second_wind_used:  bool = false
var action_surge_used: bool = false
var indomitable_uses:  int  = 0

# =============================================================
# 🏹 레인저 변수 (RANGER VARIABLES)
# =============================================================
var ranger_spell_slots_used: int = 0
var ranger_hunters_mark_target: Object = null
var ranger_hunters_mark_turns_remaining: int = 0
var ranger_colossus_slayer_used_this_turn: bool = false
var ranger_is_camouflaged: bool = false

# =============================================================
# 🪓 바바리안 변수 (BARBARIAN VARIABLES)
# =============================================================
var barbarian_rages_used: int = 0
var barbarian_is_raging: bool = false
var barbarian_rage_turns_left: int = 0
var barbarian_is_frenzy_active: bool = false
var barbarian_frenzy_attack_used_this_turn: bool = false
var barbarian_attacked_this_turn: bool = false
var barbarian_damaged_this_turn: bool = false
var barbarian_reckless_active_this_turn: bool = false
var barbarian_reckless_enemies_have_advantage: bool = false
var barbarian_relentless_dc: int = 10

var _owner: Object


func _init(owner: Object, p_type: Type) -> void:
	_owner = owner
	class_type = p_type
	if class_type == Type.BARBARIAN:
		EventBus.melee_attack_made.connect(_on_melee_attack_made)
		EventBus.monster_damaged.connect(_on_monster_damaged)


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
		Type.BARBARIAN: return true # 단순 + 마셜
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
	var monster: Monster = _owner as Monster
	if not monster:
		return 1
	if class_type == Type.FIGHTER:
		if   monster.level >= 20: return 4
		elif monster.level >= 11: return 3
		elif monster.level >= 5:  return 2
	elif class_type == Type.RANGER:
		if   monster.level >= 5:  return 2
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
			surge.cost = ActionBudget.Cost.BONUS
			surge.tooltip = "보너스 액션 소모 → 이번 턴 주행동 추가 부여. 장휴식 충전."
			slots.append(surge)
		Type.RANGER:
			var lvl := 1
			var monster: Monster = _owner as Monster
			if monster:
				lvl = monster.level
			
			if lvl >= 2:
				var gb := AbilitySlot.new()
				gb.id = &"goodberry"
				gb.display_name = "Goodberry (굿베리)"
				gb.available = get_remaining_spell_slots() > 0
				gb.cost = ActionBudget.Cost.ACTION
				gb.tooltip = "주문 슬롯 소모: 인벤토리에 굿베리 10개를 소환합니다. 굿베리는 포만감과 1 HP를 회복시킵니다. (슬롯 잔여: %d/%d)" % [get_remaining_spell_slots(), get_max_spell_slots()]
				slots.append(gb)
				
				var hm := AbilitySlot.new()
				hm.id = &"hunters_mark"
				hm.display_name = "Hunter's Mark (사냥꾼의 표식)"
				hm.available = get_remaining_spell_slots() > 0 and find_nearest_visible_enemy() != null
				hm.cost = ActionBudget.Cost.BONUS
				hm.tooltip = "주문 슬롯 소모: 가장 가까운 적을 표식 대상으로 지정하여, 공격 시 1d6 추가 피해를 입힙니다. (슬롯 잔여: %d/%d)" % [get_remaining_spell_slots(), get_max_spell_slots()]
				slots.append(hm)
			
			if lvl >= 3:
				var pa := AbilitySlot.new()
				pa.id = &"primeval_awareness"
				pa.display_name = "Primeval Awareness (원시의 자각)"
				pa.available = get_remaining_spell_slots() > 0
				pa.cost = ActionBudget.Cost.ACTION
				pa.tooltip = "주문 슬롯 소모: 현재 맵 전체에 언데드가 있는지 탐지합니다. (슬롯 잔여: %d/%d)" % [get_remaining_spell_slots(), get_max_spell_slots()]
				slots.append(pa)
			
			if lvl >= 10:
				var hips := AbilitySlot.new()
				hips.id = &"hide_in_plain_sight"
				hips.display_name = "Hide in Plain Sight (자연 위장)"
				hips.available = not ranger_is_camouflaged
				hips.cost = ActionBudget.Cost.BONUS if lvl >= 14 else ActionBudget.Cost.ACTION
				hips.tooltip = "주위 환경을 이용해 위장합니다. 공격이나 다른 행동을 취하기 전까지 투명 상태(은신)가 됩니다."
				slots.append(hips)
		Type.BARBARIAN:
			var lvl := 1
			var monster: Monster = _owner as Monster
			if monster:
				lvl = monster.level
			
			var rem_rages := get_remaining_rages()
			
			# Rage / Frenzied Rage
			if lvl >= 3:
				var fr := AbilitySlot.new()
				fr.id = &"barbarian_frenzied_rage"
				fr.display_name = "Frenzied Rage (광폭화 분노)"
				fr.available = not barbarian_is_raging and rem_rages > 0
				fr.cost = ActionBudget.Cost.BONUS
				fr.tooltip = "보조 행동 소모: 격노 및 광폭화를 시작합니다. 매 턴 보조 행동으로 추가 공격이 가능하지만, 분노가 끝나면 탈진(STIM_RECOVERY) 상태가 됩니다. (남은 분노: %d)" % rem_rages
				slots.append(fr)
			else:
				var rg := AbilitySlot.new()
				rg.id = &"barbarian_rage"
				rg.display_name = "Rage (분노)"
				rg.available = not barbarian_is_raging and rem_rages > 0
				rg.cost = ActionBudget.Cost.BONUS
				rg.tooltip = "보조 행동 소모: 전투 분노 상태에 돌입합니다. 물리 피해 저항 및 추가 공격력 획득. (남은 분노: %d)" % rem_rages
				slots.append(rg)
			
			# Frenzy Attack (광폭화 공격) - only when raging & frenzy active
			if lvl >= 3 and barbarian_is_raging and barbarian_is_frenzy_active:
				var fa := AbilitySlot.new()
				fa.id = &"barbarian_frenzy_attack"
				fa.display_name = "Frenzy Attack (광폭화 공격)"
				fa.available = not barbarian_frenzy_attack_used_this_turn
				fa.cost = ActionBudget.Cost.BONUS
				fa.tooltip = "보조 행동 소모: 인접한 적에게 강력한 추가 근접 공격을 가합니다. (이번 턴 사용 가능)"
				slots.append(fa)
				
			# Reckless Attack (무모한 공격) - Lv2+
			if lvl >= 2:
				var ra := AbilitySlot.new()
				ra.id = &"barbarian_reckless"
				ra.display_name = "Reckless Attack (무모한 공격)"
				ra.available = not barbarian_reckless_active_this_turn
				ra.cost = ActionBudget.Cost.FREE
				ra.tooltip = "비용 없음: 이번 턴 첫 공격 시작 전 활성화. 공격에 이점을 얻지만, 적들 또한 공격 시 이점을 얻습니다."
				slots.append(ra)
				
			# Intimidating Presence (위압적인 존재감) - Lv10+
			if lvl >= 10:
				var ip := AbilitySlot.new()
				ip.id = &"barbarian_intimidating_presence"
				ip.display_name = "Intimidating Presence (위압적인 존재감)"
				ip.available = find_nearest_visible_enemy() != null
				ip.cost = ActionBudget.Cost.ACTION
				ip.tooltip = "주행동 소모: 6타일 이내의 적 하나를 위압하여 지혜 내성 굴림을 강제합니다. 실패 시 혼란(공포) 상태로 만듭니다."
				slots.append(ip)
	return slots


func on_short_rest() -> void:
	second_wind_used  = false
	action_surge_used = false
	if class_type == Type.BARBARIAN:
		end_rage()
		barbarian_relentless_dc = 10
		Log.i("[ClassComponent] Barbarian short rest: active rage ended and Relentless Rage DC reset.")


func on_long_rest() -> void:
	second_wind_used  = false
	action_surge_used = false
	indomitable_uses  = 0
	
	if class_type == Type.RANGER:
		ranger_spell_slots_used = 0
		ranger_hunters_mark_target = null
		ranger_hunters_mark_turns_remaining = 0
		ranger_colossus_slayer_used_this_turn = false
		ranger_is_camouflaged = false
		Log.i("[ClassComponent] Ranger long rest: spell slots and abilities reset.")
	elif class_type == Type.BARBARIAN:
		end_rage()
		barbarian_rages_used = 0
		barbarian_relentless_dc = 10
		Log.i("[ClassComponent] Barbarian long rest: rages restored, active rage ended, Relentless Rage DC reset.")


# =============================================================
# 🏹 [구역 4] 레인저 특성 (RANGER)
# =============================================================
//#region 레인저 특성

func get_max_spell_slots() -> int:
	var monster: Monster = _owner as Monster
	if not monster or class_type != Type.RANGER:
		return 0
	# 2 slots at Lv2, 3 slots at Lv3-4, 4 slots at Lv5+
	if monster.level >= 5:
		return 4
	elif monster.level >= 3:
		return 3
	elif monster.level >= 2:
		return 2
	return 0


func get_remaining_spell_slots() -> int:
	if class_type != Type.RANGER:
		return 0
	return max(0, get_max_spell_slots() - ranger_spell_slots_used)


func get_favored_enemies() -> Array[Species.Type]:
	var monster: Monster = _owner as Monster
	var enemies: Array[Species.Type] = []
	if not monster or class_type != Type.RANGER:
		return enemies
	if monster.level >= 1:
		enemies.append(Species.Type.UNDEAD)
	if monster.level >= 6:
		enemies.append(Species.Type.REPTILE)
	if monster.level >= 14:
		enemies.append(Species.Type.ARACHNID)
	return enemies


func get_favored_enemy_attack_bonus(defender: Object) -> int:
	var monster: Monster = _owner as Monster
	if not monster or class_type != Type.RANGER or not defender:
		return 0
	if monster.level >= 20 and defender.get("species") in get_favored_enemies():
		return floori((monster.stats.get_wisdom() - 10) / 2.0)
	return 0


func get_favored_enemy_damage_bonus(defender: Object) -> int:
	var monster: Monster = _owner as Monster
	if not monster or class_type != Type.RANGER or not defender:
		return 0
	var bonus := 0
	if defender.get("species") in get_favored_enemies():
		if monster.level >= 20:
			bonus += floori((monster.stats.get_wisdom() - 10) / 2.0)
	return bonus


func get_hunters_mark_damage_bonus(defender: Object) -> int:
	if class_type != Type.RANGER or not defender:
		return 0
	if ranger_hunters_mark_target == defender and ranger_hunters_mark_turns_remaining > 0:
		var bonus := Dice.roll(1, 6)
		Log.d("[ClassComponent] Hunter's Mark damage bonus roll: %d" % bonus)
		return bonus
	return 0


func get_colossus_slayer_damage_bonus(defender: Object) -> int:
	var monster: Monster = _owner as Monster
	if not monster or class_type != Type.RANGER or not defender:
		return 0
	if monster.level >= 3 and not ranger_colossus_slayer_used_this_turn:
		if defender.get("hp") < defender.get("max_hp"):
			ranger_colossus_slayer_used_this_turn = true
			var bonus := Dice.roll(1, 8)
			Log.i("[ClassComponent] Colossus Slayer triggered! Added %d damage." % bonus)
			return bonus
	return 0


func get_sight_radius_bonus() -> int:
	var monster: Monster = _owner as Monster
	if not monster or class_type != Type.RANGER:
		return 0
	# Natural Explorer (Level 1): +2 sight
	# Feral Senses (Level 18): +4 sight
	if monster.level >= 18:
		return 4
	elif monster.level >= 1:
		return 2
	return 0


func use_primeval_awareness() -> Dictionary:
	var result := {"success": false, "message": "성공하지 못했습니다.", "enemies_detected": []}
	var monster: Monster = _owner as Monster
	if not monster or class_type != Type.RANGER:
		return result
	if get_remaining_spell_slots() <= 0:
		result.message = "주문 슬롯이 부족합니다."
		return result
	
	ranger_spell_slots_used += 1
	result.success = true
	
	var current_map = World.current_map if "current_map" in World else null
	if current_map:
		var detected: Array[String] = []
		for enemy in current_map.get_monsters():
			if enemy.species == Species.Type.UNDEAD:
				detected.append(enemy.name)
		result.enemies_detected = detected
		if detected.is_empty():
			result.message = "주변에 부정한 기운(언데드)이 느껴지지 않습니다."
		else:
			result.message = "부정한 기운(언데드)이 어딘가에 존재하는 것을 감지했습니다!"
		Log.i("[ClassComponent] Primeval Awareness used. Undead detected: %s" % str(detected))
	return result


func find_nearest_visible_enemy() -> Object:
	var monster: Monster = _owner as Monster
	if not monster:
		return null
	var current_map = World.current_map if "current_map" in World else null
	if not current_map:
		return null
	
	var my_pos := current_map.find_monster_position(monster)
	if my_pos == Utils.INVALID_POS:
		return null
		
	var nearest_enemy: Monster = null
	var min_dist := 99999.0
	
	for enemy in current_map.get_visible_monsters():
		if enemy == monster:
			continue
		if monster.faction_comp.is_hostile_to(enemy):
			var enemy_pos := current_map.find_monster_position(enemy)
			if enemy_pos == Utils.INVALID_POS:
				continue
			var dist := my_pos.distance_to(enemy_pos)
			if dist < min_dist:
				min_dist = dist
				nearest_enemy = enemy
	return nearest_enemy


func on_turn_start() -> void:
	if class_type == Type.RANGER:
		ranger_colossus_slayer_used_this_turn = false
		if ranger_hunters_mark_turns_remaining > 0:
			ranger_hunters_mark_turns_remaining -= 1
			if ranger_hunters_mark_turns_remaining == 0:
				ranger_hunters_mark_target = null
				Log.i("[ClassComponent] Hunter's Mark has expired.")
	elif class_type == Type.BARBARIAN:
		if barbarian_is_raging:
			var is_persistent := _owner.level >= 15
			if not is_persistent and not barbarian_attacked_this_turn and not barbarian_damaged_this_turn:
				Log.i("[ClassComponent] Barbarian %s's Rage ended early: didn't attack or take damage since last turn." % _owner.name)
				end_rage()
			else:
				barbarian_rage_turns_left -= 1
				if barbarian_rage_turns_left <= 0:
					Log.i("[ClassComponent] Barbarian %s's Rage ended: duration reached 10 turns." % _owner.name)
					end_rage()
		
		# Reset turn budget/flags
		barbarian_attacked_this_turn = false
		barbarian_damaged_this_turn = false
		barbarian_reckless_active_this_turn = false
		barbarian_reckless_enemies_have_advantage = false
		barbarian_frenzy_attack_used_this_turn = false


# =============================================================
# 🪓 [구역 5] 바바리안 특성 (BARBARIAN)
# =============================================================
//#region 바바리안 특성

func get_max_rages() -> int:
	var monster: Monster = _owner as Monster
	if not monster or class_type != Type.BARBARIAN:
		return 0
	if monster.level >= 20: return 9999
	elif monster.level >= 17: return 6
	elif monster.level >= 12: return 5
	elif monster.level >= 6: return 4
	elif monster.level >= 3: return 3
	return 2


func get_remaining_rages() -> int:
	if class_type != Type.BARBARIAN:
		return 0
	return max(0, get_max_rages() - barbarian_rages_used)


func is_wearing_any_armor() -> bool:
	var monster: Monster = _owner as Monster
	if not monster:
		return false
	var upper_item: Item = monster.equipment.equipped_items.get(Equipment.Slot.UPPER_ARMOR)
	var lower_item: Item = monster.equipment.equipped_items.get(Equipment.Slot.LOWER_ARMOR)
	return upper_item != null or lower_item != null


func is_wearing_heavy_armor() -> bool:
	var monster: Monster = _owner as Monster
	if not monster:
		return false
	var upper_item: Item = monster.equipment.equipped_items.get(Equipment.Slot.UPPER_ARMOR)
	var lower_item: Item = monster.equipment.equipped_items.get(Equipment.Slot.LOWER_ARMOR)
	
	for item in [upper_item, lower_item]:
		if item:
			var item_name: String = item.name.to_lower()
			var item_slug: String = String(item.slug).to_lower()
			for heavy_keyword in ["heavy", "plate", "chain", "ring_mail", "ringmail"]:
				if heavy_keyword in item_name or heavy_keyword in item_slug:
					return true
	return false


func get_rage_damage_bonus() -> int:
	var monster: Monster = _owner as Monster
	if not monster or class_type != Type.BARBARIAN or not barbarian_is_raging:
		return 0
	if is_wearing_heavy_armor():
		return 0
	if monster.level >= 16: return 4
	elif monster.level >= 9: return 3
	return 2


func start_rage(frenzy: bool = false) -> bool:
	if class_type != Type.BARBARIAN:
		return false
	if barbarian_is_raging:
		Log.i("[Barbarian] Already raging!")
		return false
	if get_remaining_rages() <= 0:
		Log.i("[Barbarian] No rages left!")
		return false
	if is_wearing_heavy_armor():
		Log.i("[Barbarian] Cannot enter Rage while wearing heavy armor!")
		return false

	barbarian_rages_used += 1
	barbarian_is_raging = true
	barbarian_rage_turns_left = 10
	barbarian_is_frenzy_active = frenzy
	barbarian_frenzy_attack_used_this_turn = false
	barbarian_attacked_this_turn = true
	barbarian_damaged_this_turn = false
	
	Log.i("[Barbarian] %s enters %sRage! Remaining rages: %d/%d" % [
		_owner.name, 
		"Frenzied " if frenzy else "", 
		get_remaining_rages(), 
		get_max_rages()
	])
	
	# Mindless Rage (Lv6+): removes Confused effect immediately if any
	if _owner.level >= 6:
		var status_comp = _owner.get("status")
		if status_comp and status_comp.has_method("remove_effect"):
			status_comp.remove_effect(StatusEffect.Type.CONFUSED)
			Log.i("[Barbarian] %s Mindless Rage: CONFUSED status removed." % _owner.name)
			
	return true


func end_rage() -> void:
	if not barbarian_is_raging:
		return
	
	Log.i("[Barbarian] %s's Rage ends." % _owner.name)
	barbarian_is_raging = false
	barbarian_rage_turns_left = 0
	
	if barbarian_is_frenzy_active:
		barbarian_is_frenzy_active = false
		# Apply exhaustion (STIM_RECOVERY for 15 turns)
		var status_comp = _owner.get("status")
		if status_comp and status_comp.has_method("apply_effect"):
			status_comp.apply_effect(StatusEffect.Type.STIM_RECOVERY, 15)
			Log.i("[Barbarian] %s's Frenzied Rage ended: STIM_RECOVERY (exhaustion) applied for 15 turns." % _owner.name)
	
	barbarian_frenzy_attack_used_this_turn = false


func get_charisma_modifier() -> int:
	var monster: Monster = _owner as Monster
	if not monster:
		return 0
	return floori((monster.stats.get_charisma() - 10) / 2.0)


func use_intimidating_presence(target: Monster) -> bool:
	if class_type != Type.BARBARIAN or not target:
		return false
	
	var dc := 8 + get_proficiency_bonus() + get_charisma_modifier()
	Log.i("[Barbarian] %s uses Intimidating Presence on %s (DC %d)" % [_owner.name, target.name, dc])
	
	var passed := Combat.roll_saving_throw(target, Combat.SaveType.WIS, dc)
	if passed:
		Log.i("[Barbarian] %s succeeded Wisdom saving throw against Intimidating Presence." % target.name)
		return false
	else:
		Log.i("[Barbarian] %s failed Wisdom saving throw! Applying CONFUSED status." % target.name)
		var status_comp = target.get("status")
		if status_comp and status_comp.has_method("apply_effect"):
			status_comp.apply_effect(StatusEffect.Type.CONFUSED, 3)
		return true


func _on_melee_attack_made(attacker: Monster, _target: Monster) -> void:
	if class_type != Type.BARBARIAN:
		return
	if attacker == _owner:
		barbarian_attacked_this_turn = true


func _on_monster_damaged(attacker: Monster, target: Monster, damage: int, _damage_type: int) -> void:
	if class_type != Type.BARBARIAN:
		return
	if target == _owner:
		barbarian_damaged_this_turn = true
		
		# Handle Retaliation (Lv14+)
		if barbarian_is_raging and _owner.level >= 14 and _owner.budget.can_use(ActionBudget.Cost.REACTION):
			var current_map = World.current_map if "current_map" in World else null
			if current_map and attacker and not attacker.is_dead:
				var my_pos := current_map.find_monster_position(_owner)
				var enemy_pos := current_map.find_monster_position(attacker)
				if my_pos != Utils.INVALID_POS and enemy_pos != Utils.INVALID_POS:
					var dx := abs(my_pos.x - enemy_pos.x)
					var dy := abs(my_pos.y - enemy_pos.y)
					if dx <= 1 and dy <= 1:
						# Target is adjacent, trigger Retaliation!
						_owner.budget.spend(ActionBudget.Cost.REACTION)
						Log.i("[Retaliation] %s triggers Retaliation reaction attack against %s!" % [_owner.name, attacker.name])
						
						var combat_result := Combat.resolve_melee_attack(_owner, attacker)
						attacker.hp = max(0, attacker.hp - combat_result.damage)
						
						EventBus.melee_attack_made.emit(_owner, attacker)
						if combat_result.damage > 0:
							EventBus.monster_damaged.emit(_owner, attacker, combat_result.damage, combat_result.damage_type)
							
						var msg := Combat.format_melee_attack_message(_owner, attacker, combat_result)
						World.message_logged.emit("[color=orange][Retaliation][/color] " + msg, LogMessages.Level.GOOD)
						
						if combat_result.killed:
							attacker.is_dead = true
							EventBus.monster_killed.emit(_owner, attacker)
							if attacker != World.player:
								attacker.drop_everything()
								current_map.find_and_remove_monster(attacker)

//#endregion
