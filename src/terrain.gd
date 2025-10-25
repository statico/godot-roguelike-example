class_name Terrain
extends RefCounted

enum Type {
	EMPTY,
	DUNGEON_WALL,
	DUNGEON_WALL_VENTED,
	DUNGEON_FLOOR,
	DUNGEON_FLOOR_GRATE,
	DUNGEON_HOLE,
	DUNGEON_DOOR_OPEN,
	DUNGEON_DOOR_CLOSED,
}

enum NameFormat { THE, AN, PLAIN, CAPITALIZED }

var type: Type = Type.EMPTY
var hp: int = 0
var variant: int = 0


func _to_string() -> String:
	return "Terrain(%s)" % [type]


func get_name(format: NameFormat = NameFormat.PLAIN) -> String:
	var n: String
	match type:
		Type.EMPTY:
			n = "empty space"
		Type.DUNGEON_WALL:
			n = "wall"
		Type.DUNGEON_WALL_VENTED:
			n = "vented wall"
		Type.DUNGEON_FLOOR:
			n = "floor"
		Type.DUNGEON_FLOOR_GRATE:
			n = "grated floor"
		Type.DUNGEON_HOLE:
			n = "hole"
		Type.DUNGEON_DOOR_OPEN:
			n = "open door"
		Type.DUNGEON_DOOR_CLOSED:
			n = "closed door"
		_:
			n = str(Type.keys()[type]).to_lower()

	match format:
		NameFormat.THE:
			return "the " + n
		NameFormat.AN:
			return ("an " if n[0] in ["a", "e", "i", "o", "u"] else "a ") + n
		NameFormat.PLAIN:
			return n
		NameFormat.CAPITALIZED:
			return "The " + n

	return "the " + n  # Default fallback


func get_hover_info() -> String:
	return get_name().replace("_", " ").capitalize()


func is_walkable() -> bool:
	return (
		type == Type.DUNGEON_FLOOR
		or type == Type.DUNGEON_FLOOR_GRATE
		or type == Type.DUNGEON_HOLE
		or type == Type.DUNGEON_DOOR_OPEN
	)


func get_char() -> String:
	match type:
		Type.DUNGEON_WALL:
			return "#"
		Type.DUNGEON_WALL_VENTED:
			return "V"
		Type.DUNGEON_FLOOR:
			return "."
		Type.DUNGEON_FLOOR_GRATE:
			return ":"
		Type.DUNGEON_HOLE:
			return "O"
		Type.DUNGEON_DOOR_OPEN:
			return "_"
		_:
			return " "
