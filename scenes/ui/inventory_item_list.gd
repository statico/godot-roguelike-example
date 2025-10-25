@icon("res://assets/icons/inventory_item_list.svg")
class_name InventoryItemList
extends ScrollContainer

signal selection_changed(selected_items: Array[Item])
signal item_dropped(item: Item)
signal item_double_clicked(item: Item)
signal item_added_to_container(container: Item, added_item: Item)

const InventoryItemScene = preload("res://scenes/ui/inventory_item.tscn")

const Sections := {
	"Weapons":
	[
		Item.Type.KNIFE,
		Item.Type.SWORD,
		Item.Type.SPEAR,
		Item.Type.HAMMER,
		Item.Type.GUN,
		Item.Type.THROWABLE,
		Item.Type.GRENADE,
	],
	"Ammo":
	[
		Item.Type.AMMO,
	],
	"Armor + Clothing":
	[
		Item.Type.HEADWEAR,
		Item.Type.MASK,
		Item.Type.UPPER_ARMOR,
		Item.Type.BASE,
		Item.Type.BELT,
		Item.Type.CLOAK,
		Item.Type.LOWER_ARMOR,
		Item.Type.GLOVES,
		Item.Type.FOOTWEAR,
	],
	"Tools + Supplies":
	[
		Item.Type.TOOL,
		Item.Type.MODULE,
		Item.Type.CONTAINER,
	],
	"Other":
	[
		Item.Type.CONSUMABLE,
		Item.Type.MELEE,
		Item.Type.MISC,
	],
}

@onready var list: VBoxContainer = %List
@onready var outline: ReferenceRect = %Outline

var items: Array[Item] = []


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	# Clear example items from scene
	clear_items()


func _on_mouse_entered() -> void:
	if get_viewport().gui_is_dragging():
		outline.visible = true


func _on_mouse_exited() -> void:
	outline.visible = false


func clear_items() -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	items.clear()
	selection_changed.emit(items)


func add_item(item: Item) -> InventoryItem:
	items.append(item)
	update()
	return _get_inventory_item(item)


func update() -> void:
	# Clear existing items
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()

	# If no items, show "no items" header and return
	if items.is_empty():
		var header := Label.new()
		header.text = "No items"
		header.theme_type_variation = &"SubtleLabel"
		list.add_child(header)
		return

	# Group top-level items by section
	var section_items: Dictionary = {}
	for section_name: String in Sections:
		section_items[section_name] = []

	# Process top-level items only for sections
	for item in items:
		var section_name := ""
		for s_name: String in Sections:
			if item.type in Sections[s_name]:
				section_name = s_name
				break

		if section_name:
			var items_in_section: Array = section_items[section_name]
			items_in_section.append(item)

	# Create sections and add items with their nested contents
	for section_name: String in Sections:
		var items_in_section: Array = section_items[section_name]
		if items_in_section.is_empty():
			continue

		# Add section header
		var header := Label.new()
		header.text = section_name
		header.theme_type_variation = &"SubtleLabel"
		header.custom_minimum_size.y = 14
		header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		list.add_child(header)

		# Sort items in this section by type
		items_in_section.sort_custom(func(a: Item, b: Item) -> bool: return a.type < b.type)

		# Add items with their nested contents
		for item: Item in items_in_section:
			_add_item_with_contents(item, 0)


# Add an item and recursively add its contents if it's an open container
func _add_item_with_contents(item: Item, depth: int) -> void:
	# Add the item itself
	var inventory_item := InventoryItemScene.instantiate() as InventoryItem
	inventory_item.item = item
	inventory_item.nesting_depth = depth
	inventory_item.clicked.connect(_on_item_clicked)
	inventory_item.double_clicked.connect(_on_item_double_clicked)
	inventory_item.item_added_to_container.connect(_on_item_added_to_container)

	list.add_child(inventory_item)

	# If this item has children and is "open", recursively add its contents
	if item.is_open_for_children() and item.children.size() > 0:
		for child_item: Item in item.children.to_array():
			_add_item_with_contents(child_item, depth + 1)


## Gets the InventoryItem for the given item
func _get_inventory_item(item: Item) -> InventoryItem:
	for child in list.get_children():
		if child is InventoryItem:
			var inventory_item: InventoryItem = child as InventoryItem
			if inventory_item.item == item:
				return inventory_item
	return null


## Gets all InventoryItems in the list
func _get_all_inventory_items() -> Array[InventoryItem]:
	var ret: Array[InventoryItem] = []
	for child in list.get_children():
		if child is InventoryItem:
			ret.append(child as InventoryItem)
	return ret


func get_selected_items() -> Array[Item]:
	var ret: Array[Item] = []
	for inventory_item in _get_all_inventory_items():
		if inventory_item.selected:
			ret.append(inventory_item.item)
	return ret


func _on_item_added_to_container(container: Item, added_item: Item) -> void:
	item_added_to_container.emit(container, added_item)


func _on_item_clicked(item: Item, shift_clicked: bool) -> void:
	get_viewport().set_input_as_handled()
	if shift_clicked:
		var inventory_item: InventoryItem = _get_inventory_item(item)
		if inventory_item:
			inventory_item.selected = not inventory_item.selected
	else:
		for inventory_item in _get_all_inventory_items():
			inventory_item.selected = inventory_item.item == item
	selection_changed.emit(items)


func _on_item_double_clicked(item: Item) -> void:
	get_viewport().set_input_as_handled()
	item_double_clicked.emit(item)


func clear_selection() -> void:
	for inventory_item in _get_all_inventory_items():
		inventory_item.selected = false
	items.clear()
	selection_changed.emit(items)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if data is Item:
		return true
	return false


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	outline.visible = false
	if data is Item:
		var item: Item = data
		Log.d(
			"[DragDrop] Item dropped on InventoryItemList: %s" % item.get_name(Item.NameFormat.THE)
		)
		item_dropped.emit(item)
		# Force an update of the list to reflect any container changes
		update()
