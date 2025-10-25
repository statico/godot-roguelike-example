class_name InventoryModal
extends Modal

const InventoryItemScene = preload("res://scenes/ui/inventory_item.tscn")

enum Tab {
	GROUND = 0,
	INVENTORY = 1,
	EQUIPMENT = 2,
}

signal pickup_requested(selections: Array[ItemSelection])
signal drop_requested(selections: Array[ItemSelection])
signal equip_requested(action: PlayerEquipAction)
signal unequip_requested(action: PlayerUnequipAction)
signal throw_requested(selections: Array[ItemSelection])
signal message_logged(message: String)
signal use_requested(item: Item)
signal reparent_requested(action: PlayerReparentItemAction)
signal toggle_container_requested(item: Item)

@onready var close_button: Button = %CloseButton
@onready var tabs: DraggableTabBar = %Tabs
@onready var ground_container: Container = %GroundContainer
@onready var inventory_container: Container = %InventoryContainer
@onready var equipment_container: Container = %EquipmentContainer
@onready var ground_list: InventoryItemList = %GroundList
@onready var inventory_list: InventoryItemList = %InventoryList
@onready var pickup_button: Button = %PickupButton
@onready var drop_button: Button = %DropButton
@onready var equip_button: Button = %EquipButton
@onready var use_button: Button = %UseButton
@onready var throw_button: Button = %ThrowButton
@onready var unequip_button: Button = %UnequipButton

var equipment_sockets: Dictionary = {}
var _previous_tab: int = Tab.INVENTORY


func _ready() -> void:
	super._ready()

	# Connect to World signals
	World.world_initialized.connect(_on_world_initialized)
	World.turn_ended.connect(_on_turn_ended)

	# Assign equipment slots
	equipment_sockets[Equipment.Slot.HEADWEAR] = %Hat
	equipment_sockets[Equipment.Slot.MASK] = %Mask
	equipment_sockets[Equipment.Slot.MELEE] = %Melee
	equipment_sockets[Equipment.Slot.RANGED] = %Ranged
	equipment_sockets[Equipment.Slot.UPPER_ARMOR] = %UpperArmor
	equipment_sockets[Equipment.Slot.BASE] = %BaseLayer
	equipment_sockets[Equipment.Slot.BELT] = %Belt
	equipment_sockets[Equipment.Slot.CLOAK] = %Cloak
	equipment_sockets[Equipment.Slot.GLOVES] = %Gloves
	equipment_sockets[Equipment.Slot.LOWER_ARMOR] = %LowerArmor
	equipment_sockets[Equipment.Slot.FOOTWEAR] = %Footwear

	# Connect main window signals
	close_button.button_up.connect(_close_modal)
	tabs.tab_changed.connect(_on_tab_changed)

	# Tabs need to be initialized manually
	_on_tab_changed(tabs.current_tab)

	# Connect button signals
	pickup_button.button_up.connect(_on_pickup_button_pressed)
	drop_button.button_up.connect(_on_drop_button_pressed)
	equip_button.button_up.connect(_on_equip_button_pressed)
	use_button.button_up.connect(_on_use_button_pressed)
	throw_button.button_up.connect(_on_throw_button_pressed)
	unequip_button.button_up.connect(_on_unequip_button_pressed)

	# Connect selection changed signals
	ground_list.selection_changed.connect(func(_selection: Array[Item]) -> void: _update_buttons())
	ground_list.item_double_clicked.connect(_on_ground_item_double_clicked)

	inventory_list.selection_changed.connect(
		func(_selection: Array[Item]) -> void: _update_buttons()
	)
	inventory_list.item_double_clicked.connect(_on_inventory_item_double_clicked)
	inventory_list.item_added_to_container.connect(_on_item_added_to_container)

	for slot: Equipment.Slot in Equipment.Slot.values():
		var socket := equipment_sockets[slot] as EquipmentSocket
		socket.equipment_slot = slot
		socket.item_selected.connect(_on_equipment_item_selected)
		socket.item_dropped.connect(_on_equipment_item_dropped)
		socket.equip_requested.connect(_on_equip_requested)
		socket.unequip_requested.connect(_on_unequip_requested)
		socket.item_drop_failed.connect(_on_item_drop_failed)

	tabs.item_dropped.connect(_on_tab_item_dropped)
	ground_list.item_dropped.connect(_on_ground_item_dropped)
	inventory_list.item_dropped.connect(_on_inventory_item_dropped)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		for _slot: Equipment.Slot in equipment_sockets.keys():
			var socket: EquipmentSocket = equipment_sockets[_slot]
			socket.unselect_all()


func _on_tab_changed(tab: int) -> void:
	# Hide all containers first
	ground_container.hide()
	inventory_container.hide()
	equipment_container.hide()

	# Show the appropriate container based on tab
	match tab:
		Tab.GROUND:
			ground_container.show()
		Tab.INVENTORY:
			inventory_container.show()
		Tab.EQUIPMENT:
			equipment_container.show()

	update()


func _unhandled_input(event: InputEvent) -> void:
	super._unhandled_input(event)

	if event.is_action_pressed("toggle_inventory"):
		get_viewport().set_input_as_handled()
		if tabs.current_tab == Tab.INVENTORY:
			_close_modal()
		else:
			_previous_tab = tabs.current_tab
			tabs.current_tab = Tab.INVENTORY
			_on_tab_changed(tabs.current_tab)
	elif event.is_action_pressed("toggle_equipment"):
		get_viewport().set_input_as_handled()
		if tabs.current_tab == Tab.EQUIPMENT:
			_close_modal()
		else:
			_previous_tab = tabs.current_tab
			tabs.current_tab = Tab.EQUIPMENT
			_on_tab_changed(tabs.current_tab)
	elif event.is_action_pressed("pick_up_item"):
		get_viewport().set_input_as_handled()
		_on_pickup_button_pressed()
	elif event.is_action_pressed("drop_item"):
		get_viewport().set_input_as_handled()
		_on_drop_button_pressed()
	elif event.is_action_pressed("equip"):
		get_viewport().set_input_as_handled()
		_on_equip_button_pressed()
	elif event.is_action_pressed("unequip"):
		get_viewport().set_input_as_handled()
		_on_unequip_button_pressed()
	elif event.is_action_pressed("use"):
		get_viewport().set_input_as_handled()
		_on_use_button_pressed()
	elif event.is_action_pressed("throw"):
		get_viewport().set_input_as_handled()
		_on_throw_button_pressed()


func _on_world_initialized() -> void:
	update()


func _on_turn_ended() -> void:
	update()


func _on_pickup_button_pressed() -> void:
	var items := ground_list.get_selected_items()
	if items.size() > 0:
		pickup_requested.emit(ItemSelection._from_items(items))
	else:
		message_logged.emit("No item selected to pickup.")


func _on_drop_button_pressed() -> void:
	var items := inventory_list.get_selected_items()
	if items.size() > 0:
		drop_requested.emit(ItemSelection._from_items(items))
	else:
		message_logged.emit("No item selected to drop.")


func _on_equip_button_pressed() -> void:
	var items := inventory_list.get_selected_items()
	var selected_item: Item = items[0]
	if items.size() > 0:
		selected_item = items[0]
	if not selected_item:
		message_logged.emit("No item selected to unequip.")
		return
	var slot: Variant = World.player.equipment.get_best_slot_for_item(selected_item)
	if slot is Equipment.Slot:
		equip_requested.emit(PlayerEquipAction.new(items[0], slot as Equipment.Slot))


func _on_use_button_pressed() -> void:
	var items := inventory_list.get_selected_items()
	if items.size() != 1:
		message_logged.emit("Select one item to use.")
		return

	var selected_item := items[0]

	# Check if item is a container or has children
	if selected_item.is_container() or selected_item.children.size() > 0:
		toggle_container_requested.emit(selected_item)
		return

	# Check if item is consumable
	if not UseItemAction.can_use_item(selected_item):
		message_logged.emit("That item cannot be used.")
		return

	use_requested.emit(selected_item)

	# Close the modal if it wasn't a container
	if not selected_item.is_container():
		_close_modal()


func _on_throw_button_pressed() -> void:
	var items := inventory_list.get_selected_items()
	if items.size() != 1:
		message_logged.emit("Select one item to throw.")
		return

	# Hide the inventory and emit throw signal
	throw_requested.emit(ItemSelection._from_items(items))
	_close_modal()


func _on_unequip_button_pressed() -> void:
	# Find the first selected equipment socket
	for slot: Equipment.Slot in equipment_sockets:
		var socket: EquipmentSocket = equipment_sockets[slot]
		if socket.item:
			Log.d("Checking socket: %s" % socket)
			# Check if any modules are selected
			for module: EquipmentSocketModule in [socket.module1, socket.module2, socket.module3]:
				Log.d("Checking module: %s" % module)
				if module.is_selected() and module.get_item():
					Log.d("Unequipping item: %s" % module.get_item())
					unequip_requested.emit(PlayerUnequipAction.new(module.get_item()))
					module.unselect()
					return

			# If no modules selected but socket is selected, unequip the main item
			if socket.selected:
				Log.d("Socket is selected: %s" % socket.item)
				unequip_requested.emit(PlayerUnequipAction.new(socket.item))
				socket.unselect_all()
				return


func _on_equipment_item_selected(_item: Item, slot: Equipment.Slot, _module_index: int) -> void:
	# Deselect all other equipment slots
	for other_slot: Equipment.Slot in equipment_sockets.keys():
		if other_slot != slot:
			var socket: EquipmentSocket = equipment_sockets[other_slot]
			socket.unselect_all()

	_update_buttons()


func _on_equipment_item_dropped(item: Item, slot: Equipment.Slot, module_index: int) -> void:
	Log.d(
		(
			"[DragDrop] Equipment item dropped: %s in slot %s at module index %s"
			% [item.get_name(Item.NameFormat.THE), Equipment.Slot.keys()[slot], module_index]
		)
	)

	if not World.player.has_item(item):
		# Shouldn't happen, but just in case, say something.
		message_logged.emit("Can't equip what isn't in your inventory")
		return

	equip_requested.emit(PlayerEquipAction.new(item, slot, module_index))


func _on_equip_requested(action: PlayerEquipAction) -> void:
	equip_requested.emit(action)


func _on_unequip_requested(action: PlayerUnequipAction) -> void:
	unequip_requested.emit(action)


func _on_item_drop_failed(reason: String) -> void:
	message_logged.emit(reason)


func _on_tab_item_dropped(item: Item, tab_idx: int) -> void:
	Log.d("[DragDrop] Tab item dropped: %s on tab %s" % [item, tab_idx])

	match tab_idx:
		Tab.GROUND:
			_on_ground_item_dropped(item)
		Tab.INVENTORY:
			_on_inventory_item_dropped(item)


func _on_inventory_item_dropped(item: Item) -> void:
	Log.d("[DragDrop] Inventory item dropped: %s" % item)

	if World.player.has_item(item):
		Log.d("[DragDrop] Player has item in inventory: %s" % item)
		reparent_requested.emit(PlayerReparentItemAction.new(item, null))
	else:
		Log.d("[DragDrop] Picking up item from ground: %s" % item)
		pickup_requested.emit([ItemSelection.new(item, item.quantity)])


func _on_ground_item_double_clicked(item: Item) -> void:
	pickup_requested.emit([ItemSelection.new(item, item.quantity)])


func _on_ground_item_dropped(item: Item) -> void:
	Log.d("[DragDrop] Ground item dropped: %s" % item)

	var player_pos := World.current_map.find_monster_position(World.player)
	if player_pos == Utils.INVALID_POS:
		Log.e("Player not found on map")
		return

	if World.player.has_item(item):
		Log.d("[DragDrop] Dropping item from inventory to ground: %s" % item)
		drop_requested.emit([ItemSelection.new(item, 1)])
	else:
		# Shouldn't happen, but just in case, say something.
		Log.d("[DragDrop] Cannot drop item that isn't in inventory: %s" % item)
		message_logged.emit("Can't drop what isn't in your inventory")


func _on_inventory_item_double_clicked(item: Item) -> void:
	if item.is_container() or item.children.size() > 0:
		toggle_container_requested.emit(item)
	else:
		_on_use_button_pressed()


func _on_item_added_to_container(container: Item, added_item: Item) -> void:
	Log.d(
		(
			"[DragDrop] Item added to container: %s -> %s"
			% [added_item.get_name(Item.NameFormat.THE), container.get_name(Item.NameFormat.THE)]
		)
	)

	# Use ReparentItemAction to move the item into the container
	reparent_requested.emit(PlayerReparentItemAction.new(added_item, container))


func update() -> void:
	_update_ground_items()
	_update_inventory_items()
	_update_equipment_items()
	_update_buttons()
	_update_tabs()
	Log.d("Updated")


func _update_ground_items() -> void:
	ground_list.clear_items()

	# Get player position
	var player_pos := World.current_map.find_monster_position(World.player)
	if player_pos == Utils.INVALID_POS:
		Log.e("Player not found on map")
		return

	# Get items at player position
	var items := World.current_map.get_items(player_pos)

	# Create inventory items for each item
	for item in items:
		ground_list.add_item(item)


func _update_inventory_items() -> void:
	inventory_list.clear_items()

	# Get player inventory
	var inventory := World.player.inventory
	if inventory == null:
		Log.e("Player has no inventory")
		return

	# Add only top-level items to the inventory list
	for item: Item in inventory.to_array():
		# Only add items that don't have a parent (top-level items)
		if item.parent == null:
			inventory_list.add_item(item)


func _update_equipment_items() -> void:
	# Update each equipment slot with its equipped item
	for slot: Equipment.Slot in Equipment.Slot.values():
		var socket: EquipmentSocket = equipment_sockets[slot]
		var item := World.player.equipment.get_equipped_item(slot)
		if item:
			socket.set_equipped_item(item)
		else:
			socket.clear_equipped_item()


func _update_buttons() -> void:
	# Disable all buttons
	pickup_button.disabled = true
	drop_button.disabled = true
	equip_button.disabled = true
	use_button.disabled = true
	throw_button.disabled = true
	unequip_button.disabled = true

	match tabs.current_tab:
		Tab.GROUND:
			var selection := ground_list.get_selected_items()
			if selection.size() > 0:
				pickup_button.disabled = false

		Tab.INVENTORY:
			var selection := inventory_list.get_selected_items()
			if selection.size() > 0:
				drop_button.disabled = false
				if selection.size() == 1:
					var selected_item := selection[0]
					throw_button.disabled = false

					# Update use button text and state for different item types
					if selected_item.type == Item.Type.CONSUMABLE and selected_item.nutrition > 0:
						use_button.text = "Eat"
					elif selected_item.is_container():
						use_button.text = "Open" if not selected_item.is_open else "Close"
						use_button.disabled = false
					else:
						use_button.text = "Use"

					use_button.disabled = (
						not UseItemAction.can_use_item(selected_item)
						and not selected_item.is_container()
						and selected_item.children.size() == 0
					)

					if (
						World.player.equipment.get_slot_where_item_is_equipped(selected_item)
						== null
					):
						equip_button.disabled = false

		Tab.EQUIPMENT:
			var has_selected_items := false
			for socket: EquipmentSocket in equipment_sockets.values():
				# Check main socket
				if socket.selected and socket.item:
					has_selected_items = true
					break

				# Check module sockets
				for module: EquipmentSocketModule in [
					socket.module1, socket.module2, socket.module3
				]:
					if module.is_selected() and module.get_item():
						has_selected_items = true
						break

			unequip_button.disabled = not has_selected_items


func _update_tabs() -> void:
	# Update tab names with item counts
	var ground_items: int = ground_list.items.size()
	var inventory_items: int = inventory_list.items.size()

	tabs.set_tab_title(Tab.GROUND, "Ground" if ground_items == 0 else "Ground (%d)" % ground_items)
	tabs.set_tab_title(
		Tab.INVENTORY, "Inventory" if inventory_items == 0 else "Inventory (%d)" % inventory_items
	)
	tabs.set_tab_title(Tab.EQUIPMENT, "Equipment")
