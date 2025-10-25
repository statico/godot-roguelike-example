class_name DropEffect
extends ActionEffect

var item: Item


func _init(p_target: Monster, p_item: Item, p_location: Vector2i) -> void:
	super(p_target, p_location)
	item = p_item


func _to_string() -> String:
	return "DropEffect(target: %s, item: %s)" % [target, item]
