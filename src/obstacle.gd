class_name Obstacle
extends RefCounted

enum Type {
	NONE,
	ICE_BLOCK,
	STAIRS_UP,
	STAIRS_DOWN,
	TABLE,
	SHELVES_WITH_BOOKS,
	SHELVES_EMPTY,
	CHAIR,
	ALTAR,
	COFFIN,
	RUBBLE,
	DOOR_CLOSED,
	DOOR_OPEN
}

enum Direction { NONE, EAST, WEST, BOTH, NORTH, SOUTH }

enum NameFormat { THE, AN, PLAIN, CAPITALIZED }

enum Height { NONE, LOW, MEDIUM, HIGH, FULL }

var type: Type = Type.NONE
var destination_level: String = ""
var direction: Direction = Direction.NONE  # For multi-cell obstacles
var parent_pos: Vector2i  # Position of the leftmost/bottom cell for multi-cell obstacles


## Height can be used to determine if an obstacle is blocking the view of a monster, or change the chances of a projectile hitting it or passing through it.
func get_height() -> Height:
	match type:
		Type.NONE:
			return Height.NONE
		Type.ICE_BLOCK:
			return Height.HIGH
		Type.STAIRS_UP:
			return Height.FULL
		Type.STAIRS_DOWN:
			return Height.NONE
		Type.TABLE:
			return Height.HIGH
		Type.SHELVES_WITH_BOOKS, Type.SHELVES_EMPTY:
			return Height.HIGH
		Type.CHAIR:
			return Height.MEDIUM
		Type.ALTAR:
			return Height.MEDIUM
		Type.COFFIN:
			return Height.LOW
		Type.RUBBLE:
			return Height.HIGH
		Type.DOOR_CLOSED:
			return Height.FULL
		Type.DOOR_OPEN:
			return Height.NONE
	return Height.NONE


func get_name(format: NameFormat = NameFormat.PLAIN) -> String:
	var n: String
	match type:
		Type.NONE:
			n = "nothing"
		Type.ICE_BLOCK:
			n = "ice block"
		Type.STAIRS_UP:
			n = "stairs up"
		Type.STAIRS_DOWN:
			n = "stairs down"
		Type.TABLE:
			n = "table"
		Type.SHELVES_WITH_BOOKS:
			n = "shelves with books"
		Type.SHELVES_EMPTY:
			n = "empty shelves"
		Type.CHAIR:
			n = "chair"
		Type.ALTAR:
			n = "altar"
		Type.COFFIN:
			n = "coffin"
		Type.RUBBLE:
			n = "rubble"
		Type.DOOR_CLOSED:
			n = "closed door"
		Type.DOOR_OPEN:
			n = "open door"
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


func _to_string() -> String:
	return "Obstacle(%s, %s)" % [Type.keys()[type], Direction.keys()[direction]]


func is_walkable() -> bool:
	match type:
		Type.ICE_BLOCK, Type.DOOR_CLOSED:
			return false
		_:
			return true


func is_pushable() -> bool:
	match type:
		Type.ICE_BLOCK:
			return true
		_:
			return false


## For debugging in ASCII mode
func get_char() -> String:
	match type:
		Type.NONE:
			return " "
		Type.ICE_BLOCK:
			return "O"
		Type.STAIRS_UP:
			return "<"
		Type.STAIRS_DOWN:
			return ">"
		Type.TABLE:
			return "="
		Type.SHELVES_WITH_BOOKS, Type.SHELVES_EMPTY:
			return "="
		Type.CHAIR:
			return "`"
		Type.ALTAR:
			return "_"
		Type.COFFIN:
			return "_"
		Type.RUBBLE:
			return " "
		Type.DOOR_CLOSED:
			return "#"
		Type.DOOR_OPEN:
			return "|"
		_:
			return "?"


func is_multi_cell() -> bool:
	return direction != Direction.NONE


func is_vertical_multi_cell() -> bool:
	return direction == Direction.NORTH or direction == Direction.SOUTH
