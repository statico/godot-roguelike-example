class_name ActionResult
extends RefCounted

var success: bool = false
var effects: Array[ActionEffect] = []
var message: String = ""
var message_level: int = LogMessages.Level.NORMAL
var extra_nutrition_consumed: int = 0


func add_effect(effect: ActionEffect) -> void:
	effects.append(effect)


func add_message(text: String) -> void:
	message = text


func _to_string() -> String:
	return "ActionResult(success: %s, message: %s)" % [success, message]
