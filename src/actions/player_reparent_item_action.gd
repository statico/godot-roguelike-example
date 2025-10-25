class_name PlayerReparentItemAction
extends ReparentItemAction


func _init(p_item: Item, p_new_parent: Item = null) -> void:
	super(World.player, p_item, p_new_parent)
