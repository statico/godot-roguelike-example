class_name Damage
extends RefCounted

# Most of the logic is in combat.gd

enum Type {
	POISON,
	BLUNT,
	COLD,
	FIRE,
	PIERCE,
	SAW,
	SLASH,
}

# Ammo types - see also item_factory.gd
enum AmmoType {
	NONE,
	ARROW,
	BOLT,
}

static func type_to_string(type: Type) -> String:
	match type:
		Type.POISON:
			return "poison"
		Type.BLUNT:
			return "blunt"
		Type.COLD:
			return "cold"
		Type.FIRE:
			return "fire"
		Type.PIERCE:
			return "pierce"
		Type.SAW:
			return "saw"
		Type.SLASH:
			return "slash"
	Log.e("Invalid damage type: %s" % type)
	return "unknown"


static func ammo_type_to_string(ammo_type: AmmoType) -> String:
	match ammo_type:
		AmmoType.NONE:
			return "none"
		AmmoType.ARROW:
			return "arrow"
		AmmoType.BOLT:
			return "bolt"
	Log.e("Invalid ammo type: %s" % ammo_type)
	return "unknown"
