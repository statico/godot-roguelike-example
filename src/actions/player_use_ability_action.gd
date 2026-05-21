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

	return false


func _to_string() -> String:
	return "PlayerUseAbilityAction(slot: %d)" % slot_index
