@icon("res://assets/icons/grid.svg")
class_name ItemGridContainer
extends GridContainer

signal selection_changed(selected_items: Array[Control])

const NORMAL_MODULATE: Color = Color(1.0, 1.0, 1.0, 1.0)
const HOVER_MODULATE: Color = Color(0.3, 0.3, 0.3, 0.0)
const SELECTED_MODULATE: Color = Color(0.0, 0.75, 0.75, 0.0)

var selected_items: Array[Control] = []


func _ready() -> void:
	# Connect to child added signal to handle new items
	child_entered_tree.connect(_on_child_added)

	# Set up existing children
	for child in get_children():
		if child is Control:
			_setup_item(child as Control)


func _on_child_added(node: Node) -> void:
	if node is Control:
		_setup_item(node as Control)


func _setup_item(item: Control) -> void:
	# Make item focusable
	item.focus_mode = Control.FOCUS_CLICK

	# Connect to mouse events
	item.mouse_entered.connect(func() -> void: _on_item_mouse_entered(item))
	item.mouse_exited.connect(func() -> void: _on_item_mouse_exited(item))
	item.gui_input.connect(func(event: InputEvent) -> void: _on_item_gui_input(item, event))

	# TODO: Add focus events for accessibility


func _on_item_mouse_entered(item: Node) -> void:
	if item is Control:
		var control := item as Control
		if selected_items.has(control):
			control.modulate = NORMAL_MODULATE + SELECTED_MODULATE + HOVER_MODULATE
		else:
			control.modulate = NORMAL_MODULATE + HOVER_MODULATE


func _on_item_mouse_exited(item: Node) -> void:
	if item is Control:
		var control := item as Control
		if selected_items.has(control):
			control.modulate = NORMAL_MODULATE + SELECTED_MODULATE
		else:
			control.modulate = NORMAL_MODULATE


func _on_item_gui_input(item: Control, event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		var left_click := mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT
		var right_click := mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_RIGHT
		if left_click:
			if Input.is_key_pressed(KEY_CTRL):
				# Ctrl+Click: Toggle individual selection
				toggle_item_selection(item)
			elif Input.is_key_pressed(KEY_SHIFT) and not selected_items.is_empty():
				# Shift+Click: Select range
				select_range(item)
			else:
				# Normal click: Clear selection and select single item
				if selected_items.has(item) and selected_items.size() == 1:
					deselect_all()
				else:
					select_single_item(item)
		if right_click:
			# Ctrl+Click emulated: Toggle individual selection
			toggle_item_selection(item)


func toggle_item_selection(item: Control) -> void:
	if selected_items.has(item):
		deselect_item(item)
	else:
		select_item(item)


func select_single_item(item: Control) -> void:
	deselect_all()
	select_item(item)


func select_range(end_item: Control) -> void:
	# Find the indices of the start and end items
	var start_idx := get_children().find(selected_items[-1])
	var end_idx := get_children().find(end_item)

	if start_idx == -1 or end_idx == -1:
		return

	# Determine range direction
	var step := 1 if end_idx > start_idx else -1

	# Select all items in the range
	deselect_all()
	for i in range(start_idx, end_idx + step, step):
		var child := get_child(i)
		if child is Control:
			select_item(child as Control)


func select_item(item: Control) -> void:
	if not selected_items.has(item):
		selected_items.append(item)
		item.modulate = NORMAL_MODULATE + SELECTED_MODULATE + HOVER_MODULATE
		item.grab_focus()
		selection_changed.emit(selected_items)


func deselect_item(item: Control) -> void:
	var idx := selected_items.find(item)

	if not is_instance_valid(item):
		if idx != -1:
			selected_items.remove_at(idx)
		return

	if idx != -1:
		selected_items.remove_at(idx)
		item.modulate = NORMAL_MODULATE
		if selected_items.is_empty():
			item.release_focus()
		selection_changed.emit(selected_items)


func deselect_all() -> void:
	# Create a copy of the array since we'll be modifying it while iterating
	var items_to_deselect: Array[Control] = selected_items.duplicate()
	for item: Control in items_to_deselect:
		if is_instance_valid(item):
			deselect_item(item)
		else:
			# If item is no longer valid, just remove it from the array
			var idx := selected_items.find(item)
			if idx != -1:
				selected_items.remove_at(idx)
