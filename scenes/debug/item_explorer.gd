@tool
@icon("res://assets/icons/wrench.svg")
class_name ItemExplorer
extends Control

@onready var search_field: LineEdit = %SearchField
@onready var result_list: ItemList = %Results

var _all_items: Array[StringName] = []


func _ready() -> void:
	ItemFactory._load_item_data()

	# Get all item IDs and sort them
	_all_items = Utils.array_of_stringnames(ItemFactory.item_data.keys())
	_all_items.sort_custom(func(a: StringName, b: StringName) -> bool: return a < b)

	# Connect search field signal
	search_field.text_changed.connect(_on_search_changed)
	# Connect item clicked signal
	result_list.item_clicked.connect(_on_item_clicked)

	# Initial population
	_populate_results("")

	# Focus the search field
	search_field.grab_focus()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_ready()


func _on_search_changed(text: String) -> void:
	_populate_results(text.to_lower())


func _populate_results(search_text: String) -> void:
	result_list.clear()

	for item_id in _all_items:
		# Skip if doesn't match search
		if not search_text.is_empty():
			if item_id.to_lower().find(search_text) == -1:
				continue

		# Create item to get its sprite
		var item := ItemFactory.create_item(item_id)
		var texture := ItemTiles.get_texture(item.sprite_name)

		# Add item with icon and name
		var index: int = result_list.add_item(item_id, texture)

		# Set tooltip
		result_list.set_item_tooltip(index, item.get_info())


func _on_item_clicked(_index: int, _at_position: Vector2, _mouse_button_index: int) -> void:
	var item_id := result_list.get_item_text(_index).to_lower()
	DisplayServer.clipboard_set(item_id)
