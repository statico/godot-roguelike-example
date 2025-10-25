class_name PlayerUnequipAction
extends ActorAction

var item: Item


func _init(p_item: Item) -> void:
	super(World.player)
	item = p_item


func _execute(map: Map, result: ActionResult) -> bool:
	if not super(map, result):
		return false

	if not actor.has_item(item):
		result.message = "You don't have that item."
		return false

	actor.equipment.unequip_item(item)
	result.message = "You unequip %s." % item.get_name(Item.NameFormat.THE)
	return true
