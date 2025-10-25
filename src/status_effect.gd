class_name StatusEffect
extends RefCounted

enum Type {
	BLIND,  # Reduces sight radius
	BLEEDING,  # Deals damage over time
	STIM,  # Increases speed + strength + HP regen based on magnitude
	STIM_RECOVERY,  # Disables HP regen and reduces speed after stim wears off
	CONFUSED,  # Random movement
	PARALYZED,  # Cannot move
	POISONED,  # Deals damage over time and reduces stats
	BURDENED,  # Carrying too much weight
	OVERTAXED,  # Carrying way too much weight
}

var type: Type
var turns_remaining: int
var magnitude: int = 1  # How strong the effect is, default 1
var original_turns: int = 0  # How many turns the effect was applied for


func _init(p_type: Type, p_turns: int, p_magnitude: int = 1) -> void:
	type = p_type
	turns_remaining = p_turns
	magnitude = p_magnitude
	original_turns = p_turns


func _to_string() -> String:
	return (
		"StatusEffect(%s, turns=%d, magnitude=%d)" % [Type.keys()[type], turns_remaining, magnitude]
	)


## Returns the name of the status effect that can be used as "Your ___ wore off."
func get_name() -> String:
	match type:
		Type.BLIND:
			return "blindness"
		Type.BLEEDING:
			return "bleeding"
		Type.STIM:
			return "stim"
		Type.STIM_RECOVERY:
			return "withdrawal"
		Type.CONFUSED:
			return "confusion"
		Type.PARALYZED:
			return "paralysis"
		Type.POISONED:
			return "poison"
		Type.BURDENED:
			return "burden"
		Type.OVERTAXED:
			return "overtaxed"
		_:
			return "unknown effect"


func get_adjective() -> String:
	match type:
		Type.BLIND:
			return "blind"
		Type.BLEEDING:
			return "bleeding"
		Type.STIM:
			match magnitude:
				1:
					return "stimulated"
				2:
					return "highly stimulated"
				_:
					return "extremely stimulated"
		Type.STIM_RECOVERY:
			return "suffering from withdrawal"
		Type.CONFUSED:
			return "confused"
		Type.PARALYZED:
			return "paralyzed"
		Type.POISONED:
			return "poisoned"
		Type.BURDENED:
			return "burdened"
		Type.OVERTAXED:
			return "overtaxed"
		_:
			return "unknown effect"
