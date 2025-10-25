class_name Skills
extends RefCounted

enum Type { NONE, KNIFE, SWORD, HAMMER, SPEAR, FISTS, UTILITY, BOW, THROWING }

enum Level {
	UNSKILLED,  # -20% to hit
	BASIC,  # No modifier
	INTERMEDIATE,  # +10% to hit
	ADVANCED,  # +20% to hit
	EXPERT,  # +30% to hit
	MASTER,  # +40% to hit
}


## Returns the hit bonus percentage for a given skill level
static func get_hit_bonus(level: Level) -> float:
	match level:
		Level.UNSKILLED:
			return -0.2  # -20%
		Level.BASIC:
			return 0.0  # No modifier
		Level.INTERMEDIATE:
			return 0.1  # +10%
		Level.ADVANCED:
			return 0.2  # +20%
		Level.MASTER:
			return 0.3  # +30%
		_:
			return 0.0  # Default to no modifier
