class_name MapCell
extends RefCounted

enum Type { NONE, ROOM, CORRIDOR }


## Tracks ongoing area effects with their type, damage, and remaining turns
class AreaEffect:
	var type: Damage.Type
	var damage: Array[int]
	var turns_remaining: int

	func _init(p_type: Damage.Type, p_damage: Array[int], p_turns: int) -> void:
		type = p_type
		damage = p_damage
		turns_remaining = p_turns

	func _to_string() -> String:
		return (
			"AreaEffect(type: %s, damage: %s, turns: %d)"
			% [Damage.Type.keys()[type], damage, turns_remaining]
		)


var terrain: Terrain
var obstacle: Obstacle
var items: Array[Item] = []
var monster: Monster
var decoration_type: int = -1
var area_type: Type = Type.NONE
var room_type: Room.Type = Room.Type.NONE
var room_id: int = -1  # To identify which room this cell belongs to
var area_effects: Array[AreaEffect] = []
var stain_color: Color = Color.TRANSPARENT  # Optional stain color
var stain_frame: int = -1  # Optional stain frame (-1 means no stain)
var stain_lifetime: int = -1  # How many turns the blood stain remains (-1 means no blood)


func _init(
	p_terrain: Terrain = null, p_obstacle: Obstacle = null, p_monster: Monster = null
) -> void:
	terrain = p_terrain
	obstacle = p_obstacle
	monster = p_monster


func _to_string() -> String:
	return (
		"MapCell(terrain: %s, obstacle: %s, monster: %s, decoration: %s, area: %s, room: %s)"
		% [
			terrain,
			obstacle,
			monster,
			decoration_type,
			Type.keys()[area_type],
			Room.Type.keys()[room_type]
		]
	)


func is_walkable() -> bool:
	if not terrain or not terrain.is_walkable():
		return false
	if obstacle and not obstacle.is_walkable():
		return false
	return true


## Decrements turn counters and removes expired effects
func update_effects() -> void:
	var i := area_effects.size() - 1
	while i >= 0:
		var effect := area_effects[i]
		effect.turns_remaining -= 1
		if effect.turns_remaining <= 0:
			area_effects.remove_at(i)
		i -= 1

	# Update blood lifetime
	if stain_lifetime > 0:
		stain_lifetime -= 1
		if stain_lifetime <= 0:
			stain_color = Color.TRANSPARENT
			stain_frame = -1
