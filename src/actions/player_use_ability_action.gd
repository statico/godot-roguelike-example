class_name PlayerUseAbilityAction
extends BaseAction

var slot_index: int


func _init(p_slot_index: int) -> void:
	slot_index = p_slot_index
	# 슬롯의 cost를 미리 읽어 예산 확인 프레임워크에 전달
	if World.player:
		var slots := World.player.class_comp.get_ability_slots()
		if slot_index < slots.size():
			action_cost = (slots[slot_index] as ClassComponent.AbilitySlot).cost


func _execute(_map: Map, result: ActionResult) -> bool:
	var player := World.player
	var slots := player.class_comp.get_ability_slots()
	if slot_index >= slots.size():
		return false

	var slot := slots[slot_index] as ClassComponent.AbilitySlot
	if not slot.available:
		result.message = "%s is not available." % slot.display_name
		result.message_level = LogMessages.Level.BAD
		return false

	match slot.id:
		&"second_wind":
			var healed := player.class_comp.use_second_wind()
			player.hp = mini(player.max_hp, player.hp + healed)
			result.message = "You use Second Wind and recover %d HP!" % healed
			result.message_level = LogMessages.Level.GOOD
			return true
		&"action_surge":
			player.class_comp.use_action_surge(player.budget)
			result.message = "Action Surge! You gain an extra action."
			result.message_level = LogMessages.Level.GOOD
			return true
		&"goodberry":
			var class_comp := player.class_comp
			if class_comp.get_remaining_spell_slots() <= 0:
				result.message = "No spell slots remaining."
				result.message_level = LogMessages.Level.BAD
				return false
			class_comp.ranger_spell_slots_used += 1
			var berry := ItemFactory.create_item(&"goodberry")
			berry.quantity = 10
			player.add_item(berry)
			Log.i("[PlayerUseAbilityAction] Cast Goodberry. Spends 1 slot. Spawns 10 goodberries.")
			result.message = "You cast Goodberry! 10 freshly conjured berries appear in your inventory."
			result.message_level = LogMessages.Level.GOOD
			return true
		&"hunters_mark":
			var class_comp := player.class_comp
			if class_comp.get_remaining_spell_slots() <= 0:
				result.message = "No spell slots remaining."
				result.message_level = LogMessages.Level.BAD
				return false
			var target = class_comp.find_nearest_visible_enemy()
			if not target:
				result.message = "No visible hostiles to mark."
				result.message_level = LogMessages.Level.BAD
				return false
			class_comp.ranger_spell_slots_used += 1
			class_comp.ranger_hunters_mark_target = target
			class_comp.ranger_hunters_mark_turns_remaining = 600
			Log.i("[PlayerUseAbilityAction] Cast Hunter's Mark on %s. Spends 1 slot." % target.name)
			result.message = "You place a Hunter's Mark on %s!" % target.name
			result.message_level = LogMessages.Level.GOOD
			return true
		&"primeval_awareness":
			var class_comp := player.class_comp
			var pa_result := class_comp.use_primeval_awareness()
			if not pa_result.success:
				result.message = pa_result.message
				result.message_level = LogMessages.Level.BAD
				return false
			result.message = pa_result.message
			result.message_level = LogMessages.Level.GOOD
			return true
		&"hide_in_plain_sight":
			var class_comp := player.class_comp
			class_comp.ranger_is_camouflaged = true
			Log.i("[PlayerUseAbilityAction] Cast Hide in Plain Sight. Player is now camouflaged.")
			result.message = "You camouflage yourself with the environment. You are now hidden from enemies."
			result.message_level = LogMessages.Level.GOOD
			return true
		&"barbarian_rage":
			var class_comp := player.class_comp
			var success := class_comp.start_rage(false)
			if not success:
				result.message = "Failed to enter Rage!"
				result.message_level = LogMessages.Level.BAD
				return false
			Log.i("[PlayerUseAbilityAction] Cast Rage. Player enters Rage.")
			result.message = "You enter a battle Rage! You gain physical damage resistance and bonus melee damage."
			result.message_level = LogMessages.Level.GOOD
			return true
		&"barbarian_frenzied_rage":
			var class_comp := player.class_comp
			var success := class_comp.start_rage(true)
			if not success:
				result.message = "Failed to enter Frenzied Rage!"
				result.message_level = LogMessages.Level.BAD
				return false
			Log.i("[PlayerUseAbilityAction] Cast Frenzied Rage. Player enters Frenzied Rage.")
			result.message = "You enter a Frenzied Rage! You can perform a Frenzy Attack as a bonus action, but will suffer exhaustion when Rage ends."
			result.message_level = LogMessages.Level.GOOD
			return true
		&"barbarian_frenzy_attack":
			var class_comp := player.class_comp
			if not class_comp.barbarian_is_raging or not class_comp.barbarian_is_frenzy_active:
				result.message = "Frenzy Attack can only be used during Frenzied Rage."
				result.message_level = LogMessages.Level.BAD
				return false
			if class_comp.barbarian_frenzy_attack_used_this_turn:
				result.message = "You have already used Frenzy Attack this turn."
				result.message_level = LogMessages.Level.BAD
				return false
			
			var current_pos := map.find_monster_position(player)
			if current_pos == Utils.INVALID_POS:
				return false
			
			# Find an adjacent enemy
			var target_monster: Monster = null
			var target_pos := Utils.INVALID_POS
			var target_direction := Vector2i.ZERO
			for dir in Utils.ALL_DIRECTIONS:
				var check_pos := current_pos + dir
				var m := map.get_monster(check_pos)
				if m and not m.is_dead and player.is_hostile_to(m):
					target_monster = m
					target_pos = check_pos
					target_direction = dir
					break
			
			if not target_monster:
				result.message = "No adjacent hostile targets to attack."
				result.message_level = LogMessages.Level.BAD
				return false
			
			class_comp.barbarian_frenzy_attack_used_this_turn = true
			
			Log.i("[PlayerUseAbilityAction] Frenzy Attack used on %s." % target_monster.name)
			
			var combat_result := Combat.resolve_melee_attack(player, target_monster)
			target_monster.hp = max(0, target_monster.hp - combat_result.damage)
			
			EventBus.melee_attack_made.emit(player, target_monster)
			if combat_result.damage > 0:
				EventBus.monster_damaged.emit(player, target_monster, combat_result.damage, combat_result.damage_type)
			
			result.message = "[Frenzy Attack] " + Combat.format_melee_attack_message(player, target_monster, combat_result)
			
			result.add_effect(AttackEffect.new(player, Vector2(target_direction) * -1, target_monster, current_pos))
			result.add_effect(HitEffect.new(
				target_monster, Vector2(target_direction), current_pos, player, combat_result.damage > 0
			))
			
			if combat_result.killed:
				target_monster.is_dead = true
				EventBus.monster_killed.emit(player, target_monster)
				if target_monster != World.player:
					target_monster.drop_everything()
					map.find_and_remove_monster(target_monster)
					result.message_level = LogMessages.Level.GOOD
				result.add_effect(DeathEffect.new(target_monster, target_pos, true))
			
			return true
		&"barbarian_reckless":
			var class_comp := player.class_comp
			if class_comp.barbarian_reckless_active_this_turn:
				result.message = "Reckless Attack is already active this turn."
				result.message_level = LogMessages.Level.BAD
				return false
			class_comp.barbarian_reckless_active_this_turn = true
			class_comp.barbarian_reckless_enemies_have_advantage = true
			Log.i("[PlayerUseAbilityAction] Reckless Attack activated. Player attacks have advantage; enemies have advantage on player.")
			result.message = "You attack recklessly! Your melee attacks this turn will have advantage, but enemies will have advantage on attacks against you."
			result.message_level = LogMessages.Level.GOOD
			return true
		&"barbarian_intimidating_presence":
			var class_comp := player.class_comp
			var target = class_comp.find_nearest_visible_enemy()
			if not target:
				result.message = "No visible hostiles to intimidate."
				result.message_level = LogMessages.Level.BAD
				return false
			
			var my_pos := map.find_monster_position(player)
			var target_pos := map.find_monster_position(target)
			if my_pos == Utils.INVALID_POS or target_pos == Utils.INVALID_POS:
				return false
				
			if my_pos.distance_to(target_pos) > 6.0:
				result.message = "Nearest enemy is too far away (must be within 6 tiles)."
				result.message_level = LogMessages.Level.BAD
				return false
				
			var success := class_comp.use_intimidating_presence(target)
			if success:
				result.message = "You glare fiercely at %s! They are frightened and confused." % target.name
				result.message_level = LogMessages.Level.GOOD
			else:
				result.message = "You try to intimidate %s, but they resist." % target.name
				result.message_level = LogMessages.Level.BAD
			return true

	return false


func _to_string() -> String:
	return "PlayerUseAbilityAction(slot: %d)" % slot_index
