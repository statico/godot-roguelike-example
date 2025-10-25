@icon("res://assets/icons/equipment_socket_module.svg")
class_name EquipmentSocketModule
extends PanelContainer

signal item_selected(item: Item, module_index: int)
signal item_dropped(item: Item, module_index: int)
signal item_drop_failed(reason: String)
signal equip_requested(action: PlayerEquipAction)
signal unequip_requested(action: PlayerUnequipAction)

const NORMAL_VARIANT = &"EquipmentSocketSlot"
const SELECTED_VARIANT = &"EquipmentSocketSlotSelected"

@onready var icon: TextureRect = $Icon

var _item: Item = null
var _selected: bool = false
var _hovered: bool = false
var _popup_items: Array[Item] = []
var equipment_slot: Equipment.Slot = Equipment.Slot.MELEE
var index: int = -1


func _ready() -> void:
	# Connect hover signals
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	# Connect click signal
	gui_input.connect(_on_clicked)


func _to_string() -> String:
	return "EquipmentSocketModule(%s)" % index


func _process(_delta: float) -> void:
	if _selected or (_hovered and get_viewport().gui_is_dragging()):
		theme_type_variation = SELECTED_VARIANT
	else:
		theme_type_variation = NORMAL_VARIANT


func _on_clicked(event: InputEvent) -> void:
	if event is not InputEventMouseButton:
		return

	var mouse_event := event as InputEventMouseButton

	# Only handle mouse down events
	if mouse_event.pressed:
		return

	if mouse_event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		_selected = not _selected
		if _selected:
			if not _item:
				_selected = false
			item_selected.emit(_item, index)
		else:
			item_selected.emit(null, index)

	elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		var popup := PopupMenu.new()
		add_child(popup)

		# Show popup at mouse position
		popup.position = get_global_mouse_position()
		popup.popup()

		# Add actions - note that popup IDs start at 0
		popup.add_icon_item(preload("res://assets/ui/cancel_icon.tres"), "Unequip")
		if not _item:
			popup.set_item_disabled(0, true)
		popup.add_separator()

		# Add inventory items
		_popup_items.clear()
		for item: Item in World.player.inventory.to_array():
			if item.type == Item.Type.MODULE:
				_popup_items.append(item)
				popup.add_icon_item(ItemTiles.get_texture(item.sprite_name), item.get_name())

		# Connect to handle selection
		popup.id_pressed.connect(_on_popup_item_clicked)
		popup.close_requested.connect(_on_popup_closed)


func _on_popup_item_clicked(id: int) -> void:
	if id == 0:
		unequip_requested.emit(PlayerUnequipAction.new(_item))
	else:
		var object: Variant = _popup_items[id - 2]
		if object is Item:
			var item: Item = object as Item
			equip_requested.emit(PlayerEquipAction.new(item, equipment_slot, index))


func _on_popup_closed() -> void:
	_popup_items.clear()


func _on_mouse_entered() -> void:
	if _item:
		modulate = Color(1.2, 1.2, 1.2, 1.0)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_hovered = true


func _on_mouse_exited() -> void:
	if _item:
		modulate = Color.WHITE
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	_hovered = false


func set_item(p_item: Item) -> void:
	_item = p_item
	if _item:
		icon.texture = ItemTiles.get_texture(_item.sprite_name)
		tooltip_text = _item.get_info()
	else:
		icon.texture = null
		tooltip_text = ""


func get_item() -> Item:
	return _item


func unselect() -> void:
	_selected = false


func is_selected() -> bool:
	return _selected


func _get_drag_data(_at_position: Vector2) -> Variant:
	if not _item:
		return null
	set_drag_preview(ItemTiles.get_preview(_item.sprite_name))
	unselect()
	return _item


func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return data is Item


func _drop_data(_position: Vector2, data: Variant) -> void:
	if data is Item:
		var item: Item = data as Item
		var check := World.player.equipment.can_equip(item, equipment_slot, index)
		if check.can_equip:
			item_dropped.emit(item, index)
		else:
			item_drop_failed.emit(check.reason)
