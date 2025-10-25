class_name ItemSelection
extends RefCounted

var item: Item
var quantity: int


func _init(p_item: Item, p_quantity: int = 0) -> void:
	item = p_item
	quantity = p_quantity if p_quantity > 0 else p_item.quantity


func _to_string() -> String:
	if quantity > 1:
		return "ItemSelection(%s x%d)" % [item.get_name(), quantity]
	return "ItemSelection(%s)" % item


static func _from_items(items: Variant) -> Array[ItemSelection]:
	if not items is Array:
		Log.w("ItemSelection._from_items: %s is not an Array" % items)
		return []

	var ret: Array[ItemSelection] = []
	for variant: Variant in items:
		if variant is Item:
			var _item := variant as Item
			ret.append(ItemSelection.new(_item, _item.quantity))
		else:
			Log.w("ItemSelection._from_items: %s is not an Item" % variant)
	return ret


# Seems silly, but this ensures the type is correct
static func _from_selections(item_selections: Variant) -> Array[ItemSelection]:
	if not item_selections is Array:
		Log.w("ItemSelection._from_selections: %s is not an Array" % item_selections)
		return []

	var ret: Array[ItemSelection] = []
	for variant: Variant in item_selections:
		if variant is ItemSelection:
			ret.append(variant as ItemSelection)
		else:
			Log.w("ItemSelection._from_selections: %s is not an ItemSelection" % variant)
	return ret
