class_name ProjectileEffect
extends ActionEffect

var source: Monster
var start_pos: Vector2i
var end_pos: Vector2i
var source_item: Item


func _init(
	p_source: Monster,
	p_target: Monster,
	p_start_pos: Vector2i,
	p_end_pos: Vector2i,
	p_source_item: Item
) -> void:
	super(null, p_start_pos)
	source = p_source
	target = p_target
	start_pos = p_start_pos
	end_pos = p_end_pos
	source_item = p_source_item


func involves_player() -> bool:
	return source == World.player or target == World.player


func _to_string() -> String:
	return "ProjectileEffect(%s)" % source_item
