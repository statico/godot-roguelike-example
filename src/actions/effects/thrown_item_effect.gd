class_name ThrownItemEffect
extends ActionEffect

var source: Monster
var start_pos: Vector2i
var end_pos: Vector2i
var item: Item


func _init(p_source: Monster, p_start_pos: Vector2i, p_end_pos: Vector2i, p_item: Item) -> void:
	super(null, p_start_pos)
	source = p_source
	start_pos = p_start_pos
	end_pos = p_end_pos
	item = p_item


func involves_player() -> bool:
	return source == World.player


func _to_string() -> String:
	return "ThrownItemEffect(%s)" % item
