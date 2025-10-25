@tool
@icon("res://assets/icons/wrench.svg")
class_name SpriteExplorer
extends Control

@onready var search_field: LineEdit = %SearchField
@onready var result_list: ItemList = %Results
@onready var tabs: TabBar = %Tabs

var _all_sprites: Array[StringName] = []
var _current_tab: int = 0

enum TileType { ITEMS, CHARACTERS, WORLD }


func _ready() -> void:
	# Connect tab changed signal
	tabs.tab_changed.connect(_on_tab_changed)

	# Connect search field signal
	search_field.text_changed.connect(_on_search_changed)
	# Connect item clicked signal
	result_list.item_clicked.connect(_on_item_clicked)

	# Initial load
	_load_sprites_for_tab(_current_tab)

	# Focus the search field
	search_field.grab_focus()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_ready()


func _on_tab_changed(tab: int) -> void:
	_current_tab = tab
	_load_sprites_for_tab(tab)


func _load_sprites_for_tab(tab: int) -> void:
	# Get all sprite names and sort them based on the selected tab
	match tab:
		TileType.ITEMS:
			_all_sprites = ItemTiles.get_all_names()
		TileType.CHARACTERS:
			_all_sprites = CharacterTiles.get_all_names()
		TileType.WORLD:
			_all_sprites = WorldTiles.get_all_names()

	# Sort sprites using natural sort (handles numbers properly, case-insensitive)
	_all_sprites.sort_custom(func(a: StringName, b: StringName) -> bool: return str(a).naturalnocasecmp_to(str(b)) < 0)

	# Repopulate results with current search
	_populate_results(search_field.text.to_lower())


func _on_search_changed(text: String) -> void:
	_populate_results(text.to_lower())


func _populate_results(search_text: String) -> void:
	result_list.clear()

	for sprite_string_name in _all_sprites:
		var sprite_name: String = str(sprite_string_name)

		# Skip if doesn't match search
		if not search_text.is_empty():
			if sprite_name.to_lower().find(search_text) == -1:
				continue

		# Create texture for the sprite based on current tab
		var texture: AtlasTexture
		match _current_tab:
			TileType.ITEMS:
				texture = ItemTiles.get_texture(sprite_name)
			TileType.CHARACTERS:
				texture = CharacterTiles.get_texture(sprite_name)
			TileType.WORLD:
				texture = WorldTiles.get_texture(sprite_name)

		# Add item with icon and name
		result_list.add_item(sprite_name, texture)


func _on_item_clicked(_index: int, _at_position: Vector2, _mouse_button_index: int) -> void:
	var item_name := result_list.get_item_text(_index).to_lower()
	DisplayServer.clipboard_set(item_name)
