## A Set data structure implementation using a Dictionary internally.
## Provides standard set operations like add, remove, has, etc.
## Optionally supports type safety by specifying a type during initialization.
class_name Set
extends RefCounted

signal item_added(item: Variant)
signal item_removed(item: Variant)

var _dict: Dictionary = {}
var _type: int = TYPE_NIL


## Initializes the set with an optional array of values and a type.
## If a type is specified, the set will only allow values of that type (checked at runtime).
## If no type is specified, the set will be type-unsafe.
func _init(values: Array[Variant] = [], type: int = TYPE_NIL) -> void:
	_type = type
	for value: Variant in values:
		add(value)


## Adds a value to the set.
## If the value already exists, it will not be added again.
func add(value: Variant) -> void:
	if _type != TYPE_NIL and typeof(value) != _type:
		Log.e(
			"Type mismatch: expected %s, got %s" % [type_string(_type), type_string(typeof(value))]
		)
		return
	_dict[value] = true
	item_added.emit(value)


## Adds all values from another set to this set.
func add_all(other: Set) -> void:
	for value: Variant in other._dict:
		add(value)


## Removes a value from the set.
## If the value doesn't exist, nothing happens.
func remove(value: Variant) -> void:
	if _type != TYPE_NIL and typeof(value) != _type:
		Log.e(
			"Type mismatch: expected %s, got %s" % [type_string(_type), type_string(typeof(value))]
		)
		return
	_dict.erase(value)
	item_removed.emit(value)


## Removes all values from another set from this set.
func remove_all(other: Set) -> void:
	for value: Variant in other._dict:
		remove(value)


## Returns true if the value exists in the set.
func has(value: Variant) -> bool:
	if _type != TYPE_NIL and typeof(value) != _type:
		Log.e(
			"Type mismatch: expected %s, got %s" % [type_string(_type), type_string(typeof(value))]
		)
		return false
	return _dict.has(value)


## Removes all values from the set.
func clear() -> void:
	_dict.clear()


## Returns the number of values in the set.
func size() -> int:
	return _dict.size()


## Returns true if the set contains no values.
func is_empty() -> bool:
	return _dict.is_empty()


## Returns an array containing all values in the set.
func to_array() -> Array:
	return _dict.keys()


## Returns a string representation of the set.
func _to_string() -> String:
	return "Set(%s)" % _dict.keys()


## Returns a new Set containing all values from this set and another set.
func union(other: Set) -> Set:
	var result: Set = Set.new()
	for value: Variant in _dict:
		result.add(value)
	for value: Variant in other._dict:
		result.add(value)
	return result


## Returns a new Set containing values that exist in this set but not in the other set.
func difference(other: Set) -> Set:
	var result: Set = Set.new()
	for value: Variant in _dict:
		if not other.has(value):
			result.add(value)
	return result


## Returns a new Set containing only values that exist in both sets.
func intersection(other: Set) -> Set:
	var result: Set = Set.new()
	for value: Variant in _dict:
		if other.has(value):
			result.add(value)
	return result
