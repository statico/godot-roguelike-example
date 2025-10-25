@tool
@icon("res://assets/icons/grid2.svg")
class_name EquipmentGridContainer
extends GridContainer

signal selection_changed(has_equipped_item: bool)

const NORMAL_MODULATE: Color = Color(1.0, 1.0, 1.0, 1.0)
const HOVER_MODULATE: Color = Color(1.2, 1.2, 1.2, 1.0)  # Slightly brighter
const SELECTED_MODULATE: Color = Color(0.0, 0.75, 0.75, 1.0)

var slot_controls: Dictionary = {}  # Maps Equipment.Slot to Control nodes
var selected_slot: Equipment.Slot = Equipment.Slot.UPPER_ARMOR
var selected_control: Control = null


func _ready() -> void:
	# Connect to child added signal to handle new slots
	child_entered_tree.connect(_on_child_added)

	# Set up existing children
	_setup_slots()


func _on_child_added(node: Node) -> void:
	if node is Control:
		_setup_slots()


func _setup_slots() -> void:
	slot_controls.clear()

	# Map each child control to an equipment slot
	var slots := Equipment.Slot.values()
	for i in range(min(get_child_count(), slots.size())):
		var child := get_child(i)
		if child is Control:
			var slot: Equipment.Slot = slots[i]
			slot_controls[slot] = child
			_setup_slot(child as Control, slot)


func _setup_slot(control: Control, slot: Equipment.Slot) -> void:
	# Make slot focusable and ensure it captures mouse input
	control.focus_mode = Control.FOCUS_CLICK
	control.mouse_filter = Control.MOUSE_FILTER_STOP

	# Connect to mouse events
	control.mouse_entered.connect(func() -> void: _on_slot_mouse_entered(control))
	control.mouse_exited.connect(func() -> void: _on_slot_mouse_exited(control))
	control.gui_input.connect(
		func(event: InputEvent) -> void: _on_slot_gui_input(control, slot, event)
	)


func _on_slot_mouse_entered(control: Control) -> void:
	if not is_instance_valid(control):
		return

	var slot := _get_slot_for_control(control)
	if World.player.equipment.get_equipped_item(slot):
		if control == selected_control:
			control.modulate = SELECTED_MODULATE
		else:
			control.modulate = HOVER_MODULATE


func _on_slot_mouse_exited(control: Control) -> void:
	if not is_instance_valid(control):
		return

	if control == selected_control:
		control.modulate = SELECTED_MODULATE
	else:
		control.modulate = NORMAL_MODULATE


func _on_slot_gui_input(_control: Control, slot: Equipment.Slot, event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if World.player.equipment.get_equipped_item(slot):
				# First verify the control is still valid
				if is_instance_valid(selected_control):
					selected_control.modulate = NORMAL_MODULATE

				selected_control = _control
				selected_slot = slot

				# Verify control is still valid before modifying
				if is_instance_valid(_control):
					_control.modulate = SELECTED_MODULATE
					selection_changed.emit(true)

		elif mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			# Clear selection
			if is_instance_valid(selected_control):
				selected_control.modulate = NORMAL_MODULATE
			selected_control = null
			selected_slot = Equipment.Slot.UPPER_ARMOR
			selection_changed.emit(false)


func _get_slot_for_control(control: Control) -> Equipment.Slot:
	for slot: Equipment.Slot in slot_controls:
		if slot_controls[slot] == control:
			return slot
	return Equipment.Slot.UPPER_ARMOR  # Default fallback


func get_selected_slot() -> Equipment.Slot:
	return selected_slot


func clear_selection() -> void:
	if is_instance_valid(selected_control):
		selected_control.modulate = NORMAL_MODULATE
	selected_control = null
	selected_slot = Equipment.Slot.UPPER_ARMOR
	selection_changed.emit(false)
