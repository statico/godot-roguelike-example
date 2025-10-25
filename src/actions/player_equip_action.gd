class_name PlayerEquipAction
extends EquipAction


func _init(p_item: Item, p_slot: Equipment.Slot, p_module_index: int = -1) -> void:
	super(World.player, p_item, p_slot, p_module_index)
