class_name Species
extends RefCounted

enum Type {
	ARACHNID,
	DOG,
	FELINE,
	HUMAN,
	MOLLUSK,
	REPTILE,
	RODENT,
	UNDEAD,
}


## Returns a string name for the given species type
static func get_name(species_type: Type) -> String:
	match species_type:
		Type.ARACHNID:
			return "arachnid"
		Type.DOG:
			return "dog"
		Type.FELINE:
			return "feline"
		Type.HUMAN:
			return "human"
		Type.MOLLUSK:
			return "mollusk"
		Type.REPTILE:
			return "reptile"
		Type.RODENT:
			return "rodent"
		Type.UNDEAD:
			return "undead"
		_:
			return "unknown creature"


## Returns the species name as an adjective
static func get_adjective(species_type: Type) -> String:
	match species_type:
		Type.ARACHNID:
			return "arachnid"
		Type.DOG:
			return "dog"
		Type.FELINE:
			return "feline"
		Type.HUMAN:
			return "human"
		Type.MOLLUSK:
			return "mollusk"
		Type.REPTILE:
			return "reptile"
		Type.RODENT:
			return "rodent"
		Type.UNDEAD:
			return "undead"
	return get_name(species_type)


## Returns a dictionary mapping each species to its natural resistances
static func get_resistances() -> Dictionary:
	return {
		Type.HUMAN: [],
		Type.ARACHNID:
		[
			Damage.Type.POISON,
		],
		Type.DOG: [],
		Type.FELINE: [],
		Type.MOLLUSK:
		[
			Damage.Type.COLD,  # Cold-blooded
		],
		Type.REPTILE:
		[
			Damage.Type.COLD,  # Cold-blooded
		],
		Type.RODENT:
		[
			Damage.Type.COLD,  # Cold-blooded
		],
		Type.UNDEAD:
		[
			Damage.Type.COLD,  # Undead immune to cold
		],
	}
