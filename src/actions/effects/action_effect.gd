class_name ActionEffect
extends RefCounted

var target: Monster
var location: Vector2i


func _init(p_target: Monster, p_location: Vector2i) -> void:
	target = p_target
	location = p_location


func involves_player() -> bool:
	return target == World.player


func _to_string() -> String:
	return "ActionEffect(target: %s)" % target
