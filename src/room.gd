class_name Room
extends RefCounted

enum Type {
	NONE,
	DUNGEON_EMPTY,
	DUNGEON_ALTAR,
	DUNGEON_LIBRARY,
	DUNGEON_UTILITY,
	DUNGEON_ICE_STORAGE,
	DUNGEON_CRYPT
}

var id: int = -1  # -1 indicates not yet assigned to a map
var type: Type = Type.NONE
var x: int
var y: int
var width: int
var height: int


func _init(
	p_x: int, p_y: int, p_width: int, p_height: int, p_type: Type = Type.NONE, p_id: int = -1
) -> void:
	x = p_x
	y = p_y
	width = p_width
	height = p_height
	type = p_type
	id = p_id


func _to_string() -> String:
	if id != -1:
		return (
			"Room(id: %d, type: %s, pos: (%d,%d), size: %dx%d, type: %s)"
			% [id, Type.keys()[type], x, y, width, height, Type.keys()[type]]
		)
	return "Room(pos: (%d,%d), size: %dx%d, type: %s)" % [x, y, width, height, Type.keys()[type]]


# During generation, we can convert a temporary room to a map room
func to_map_room(p_id: int, p_type: Type) -> Room:
	id = p_id
	type = p_type
	return self


func contains(pos: Vector2i) -> bool:
	return pos.x >= x and pos.x < x + width and pos.y >= y and pos.y < y + height
