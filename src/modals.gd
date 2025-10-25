extends Control

signal inventory_opened(inventory: InventoryModal)
signal inventory_closed

var modal_stack: Array[Modal] = []


# Use this to block input when modals are visible or to check for input
func are_any_modals_visible() -> bool:
	return not modal_stack.is_empty()


func _add_modal(modal: Modal) -> void:
	# Add the modal to the UI
	var root := get_node_or_null("/root/Game/UI")
	if not root:
		Log.e("Could not find UI CanvasLayer")
		root = get_tree().root
	root.add_child(modal)

	# Start with 0 opacity and fade in
	modal.modulate.a = 0
	var fade_in_tween := create_tween()
	fade_in_tween.tween_property(modal, "modulate:a", 1.0, 0.1)

	# Add the modal to the stack
	modal_stack.push_front(modal)

	# Remove the modal from the stack when it is closed
	modal.modal_closed.connect(
		func(child: Modal) -> void:
			var idx := modal_stack.find(child)
			if idx != -1:
				modal_stack.remove_at(idx)
			# Fade out and then free
			var fade_out_tween := create_tween()
			fade_out_tween.tween_property(child, "modulate:a", 0.0, 0.1)
			await fade_out_tween.finished
			if is_instance_valid(child):
				child.queue_free()
	)


func confirm(title: String, message: String) -> Variant:
	var modal: ConfirmationModal = preload("res://scenes/ui/confirmation_modal.tscn").instantiate()
	modal.title = title
	modal.message = message
	_add_modal(modal)
	return await modal.confirmed


func prompt_for_direction() -> Vector3i:
	var modal: DirectionModal = preload("res://scenes/ui/direction_modal.tscn").instantiate()
	_add_modal(modal)
	return await modal.direction_selected


func show_inventory(tab: InventoryModal.Tab = InventoryModal.Tab.INVENTORY) -> InventoryModal:
	# Check if an inventory modal already exists
	for modal in modal_stack:
		if modal is InventoryModal:
			(modal as InventoryModal).tabs.current_tab = tab
			return modal

	var modal: InventoryModal = preload("res://scenes/ui/inventory_modal.tscn").instantiate()
	_add_modal(modal)
	modal.tabs.current_tab = tab

	# Let Game hook into signals
	inventory_opened.emit(modal)

	# Send inventory_closed signal when modal is closed
	modal.modal_closed.connect(func(_child: Modal) -> void: inventory_closed.emit())

	# Caller will want to hook up signals
	return modal


func toggle_inventory(tab: InventoryModal.Tab = InventoryModal.Tab.INVENTORY) -> void:
	for modal in modal_stack:
		if modal is InventoryModal:
			modal._close_modal()
			return
	show_inventory(tab)


func hide_inventory() -> void:
	for modal in modal_stack:
		if modal is InventoryModal:
			modal._close_modal()


func show_game_over() -> void:
	var modal: GameOverModal = preload("res://scenes/ui/game_over_modal.tscn").instantiate()
	_add_modal(modal)


func has_visible_modals() -> bool:
	return not modal_stack.is_empty()


func close_all_modals() -> void:
	for modal in modal_stack:
		modal._close_modal()
