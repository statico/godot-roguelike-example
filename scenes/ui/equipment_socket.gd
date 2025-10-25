@icon("res://assets/icons/equipment_socket.svg")
class_name EquipmentSocket
extends Control

signal item_selected(item: Item, equipment_slot: Equipment.Slot, module_index: int)
signal item_dropped(item: Item, equipment_slot: Equipment.Slot, module_index: int)  # -1 if no module
signal item_drop_failed(reason: String)
signal equip_requested(action: PlayerEquipAction)
signal unequip_requested(action: PlayerUnequipAction)

const NORMAL_VARIANT = &"EquipmentSocket"
const SELECTED_VARIANT = &"EquipmentSocketSelected"

@onready var panel: Panel = %Panel
@onready var icon: TextureRect = %MainIcon
@onready var modules_container: HBoxContainer = %Modules
@onready var module1: EquipmentSocketModule = %Module1
@onready var module2: EquipmentSocketModule = %Module2
@onready var module3: EquipmentSocketModule = %Module3

var item: Item = null
var selected: bool = false
var _equipment_slot: Equipment.Slot = Equipment.Slot.MELEE
var _hovered: bool = false
var _popup_items: Array[Item] = []

var equipment_slot: Equipment.Slot:
	get:
		return _equipment_slot
	set(value):
		_equipment_slot = value
		module1.equipment_slot = value
		module2.equipment_slot = value
		module3.equipment_slot = value


# Initialize the slot
func _ready() -> void:
	update()

	# Connect hover signals
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	# Connect click signal
	gui_input.connect(_on_clicked)

	# Connect module signals and initialize slots
	var modules: Array[EquipmentSocketModule] = [module1, module2, module3]
	for i in range(3):
		var module := modules[i]
		module.item_selected.connect(_on_module_item_selected)
		module.item_dropped.connect(_on_module_item_dropped)
		module.equip_requested.connect(_on_equip_requested)
		module.unequip_requested.connect(_on_unequip_requested)
		module.item_drop_failed.connect(_on_item_drop_failed)
		module.index = i
		module.equipment_slot = equipment_slot


func _to_string() -> String:
	return "EquipmentSocket(%s)" % Equipment.Slot.keys()[equipment_slot]


func _process(_delta: float) -> void:
	if selected or (_hovered and get_viewport().gui_is_dragging()):
		panel.theme_type_variation = SELECTED_VARIANT
	else:
		panel.theme_type_variation = NORMAL_VARIANT


func _on_clicked(event: InputEvent) -> void:
	if event is not InputEventMouseButton:
		return

	var mouse_event := event as InputEventMouseButton
	if mouse_event.pressed:
		return

	if mouse_event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		selected = not selected
		module1.unselect()
		module2.unselect()
		module3.unselect()
		if selected:
			if not item:
				selected = false
			item_selected.emit(item, equipment_slot, -1)
		else:
			item_selected.emit(null, equipment_slot, -1)

	elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		var popup := PopupMenu.new()
		add_child(popup)

		# Show popup at mouse position
		popup.position = get_global_mouse_position()
		popup.popup()

		# Add actions - note that popup IDs start at 0
		popup.add_icon_item(preload("res://assets/ui/cancel_icon.tres"), "Unequip")
		if not item:
			popup.set_item_disabled(0, true)
		popup.add_separator()

		# Add inventory items
		_popup_items.clear()
		for _item: Item in World.player.inventory.to_array():
			if _item.type in Equipment.valid_slot_item_types[equipment_slot]:
				_popup_items.append(_item)
				popup.add_icon_item(ItemTiles.get_texture(_item.sprite_name), _item.get_name())

		# Connect to handle selection
		popup.id_pressed.connect(_on_popup_item_clicked)
		popup.close_requested.connect(_on_popup_closed)


func _on_popup_item_clicked(id: int) -> void:
	if id == 0:
		unequip_requested.emit(PlayerUnequipAction.new(item))
	else:
		var object: Variant = _popup_items[id - 2]
		if object is Item:
			var _item: Item = object as Item
			equip_requested.emit(PlayerEquipAction.new(_item, equipment_slot))


func _on_popup_closed() -> void:
	_popup_items.clear()


func _on_module_item_selected(p_item: Item, p_index: int) -> void:
	selected = false
	item_selected.emit(p_item, equipment_slot, p_index)


func _on_module_item_dropped(p_item: Item, p_index: int) -> void:
	item_dropped.emit(p_item, equipment_slot, p_index)


func _on_equip_requested(action: PlayerEquipAction) -> void:
	equip_requested.emit(action)


func _on_unequip_requested(action: PlayerUnequipAction) -> void:
	unequip_requested.emit(action)


func _on_item_drop_failed(reason: String) -> void:
	item_drop_failed.emit(reason)


func _on_mouse_entered() -> void:
	modulate = GameColors.HIGHLIGHT_MODULATION_ADDITIVE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_hovered = true


func _on_mouse_exited() -> void:
	modulate = Color.WHITE
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	_hovered = false


# Update the slot display based on equipped item
func update() -> void:
	if item:
		icon.texture = ItemTiles.get_texture(item.sprite_name)
		icon.modulate = Color.WHITE
		tooltip_text = item.get_info()
		_update_module_slots()
	else:
		icon.texture = null
		icon.modulate = Color(1, 1, 1, 0.3)
		tooltip_text = ""
		modules_container.hide()


func _get_modules() -> Array[Item]:
	if not item:
		return []
	var ret: Array[Item] = []
	for child: Item in item.children.to_array():
		if child:
			ret.append(child)
	return ret


# Update module slots visibility and content
func _update_module_slots() -> void:
	if item and item.max_children > 0 and not item.is_container():
		modules_container.show()
		var modules := _get_modules()

		# Configure slot 1
		module1.visible = item.max_children >= 1
		if modules.size() >= 1:
			module1.set_item(modules[0])
		else:
			module1.set_item(null)

		# Configure slot 2
		module2.visible = item.max_children >= 2
		if modules.size() >= 2:
			module2.set_item(modules[1])
		else:
			module2.set_item(null)

		# Configure slot 3
		module3.visible = item.max_children >= 3
		if modules.size() >= 3:
			module3.set_item(modules[2])
		else:
			module3.set_item(null)
	else:
		modules_container.hide()


# Set the equipped item and update display
func set_equipped_item(p_item: Item) -> void:
	item = p_item
	update()


# Clear the equipped item
func clear_equipped_item() -> void:
	item = null
	update()


# Get the currently equipped item
func get_equipped_item() -> Item:
	return item


# Unselect all slots
func unselect_all() -> void:
	selected = false
	module1.unselect()
	module2.unselect()
	module3.unselect()


func _get_drag_data(_at_position: Vector2) -> Variant:
	if not item:
		return null
	set_drag_preview(ItemTiles.get_preview(item.sprite_name))
	unselect_all()
	return item


func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return data is Item


func _drop_data(_position: Vector2, data: Variant) -> void:
	if data is Item:
		var _item: Item = data as Item
		var check := World.player.equipment.can_equip(_item, equipment_slot)
		if check.can_equip:
			item_dropped.emit(_item, equipment_slot, -1)
		else:
			item_drop_failed.emit(check.reason)
