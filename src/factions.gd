class_name Factions
extends RefCounted

enum Type {
	NONE,
	CRITTERS,
	MONSTERS,
	HUMAN,
	UNDEAD,
}


## Returns a string name for the given faction type
static func get_name(faction_type: Type) -> String:
	match faction_type:
		Type.NONE:
			return "None"
		Type.CRITTERS:
			return "Critters"
		Type.MONSTERS:
			return "Monsters"
		Type.HUMAN:
			return "Humans"
		Type.UNDEAD:
			return "Undead"
		_:
			return "Unknown Faction"


## Returns a description for the given faction type
static func get_description(faction_type: Type) -> String:
	match faction_type:
		Type.NONE:
			return "No faction affiliation."
		Type.CRITTERS:
			return "Creatures that wander the dungeon and caves of the world usually looking for food."
		Type.MONSTERS:
			return "Monsters are creatures that are hostile to humans and other creatures."
		Type.HUMAN:
			return "Humans are the human species capable of reason and language."
		Type.UNDEAD:
			return "Undead are creatures that are not human. They are the undead."
		_:
			return "Unknown Faction"


## Returns true if the two factions are naturally hostile to each other
static func are_hostile(faction1: Type, faction2: Type) -> bool:
	# Pretty basic for now but can be customized. Nobody likes humans except other humans.
	if faction1 == Type.HUMAN and faction2 != Type.HUMAN:
		return true
	if faction1 != Type.HUMAN and faction2 == Type.HUMAN:
		return true
	return false
