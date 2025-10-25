@tool
@icon("res://assets/icons/wrench.svg")
class_name MapGeneratorTool
extends Node2D

@export_group("Map Generation")
@export_range(10, 100, 1) var width: int = 60:
	set(value):
		width = value
		_generate_preview()

@export_range(10, 100, 1) var height: int = 50:
	set(value):
		height = value
		_generate_preview()

@export
var generator_type: MapGeneratorFactory.GeneratorType = MapGeneratorFactory.GeneratorType.DUNGEON:
	set(value):
		generator_type = value
		_generate_preview()

# BSP parameters (for backward compatibility)
@export_range(1, 15, 1) var subdivision_levels: int = 3:
	set(value):
		subdivision_levels = value
		_generate_preview()

@export_range(1, 30, 1) var min_room_size: int = 7:
	set(value):
		min_room_size = value
		_generate_preview()

@export_range(4, 30, 1) var min_split_size: int = 8:
	set(value):
		min_split_size = value
		_generate_preview()

@export_range(0.0, 1.0, 0.1) var horizontal_split_chance: float = 0.4:
	set(value):
		horizontal_split_chance = value
		_generate_preview()

@export_group("Dungeon Generation")
@export_range(3, 20, 1) var dungeon_min_room_size: int = 5:
	set(value):
		dungeon_min_room_size = value
		_generate_preview()

@export_range(5, 30, 1) var max_room_size: int = 15:
	set(value):
		max_room_size = value
		_generate_preview()

@export_range(100, 1000, 50) var room_placement_attempts: int = 500:
	set(value):
		room_placement_attempts = value
		_generate_preview()

@export_range(5, 50, 1) var target_room_count: int = 20:
	set(value):
		target_room_count = value
		_generate_preview()

@export_range(0.0, 1.0, 0.1) var room_expansion_chance: float = 0.5:
	set(value):
		room_expansion_chance = value
		_generate_preview()

@export_range(0.0, 1.0, 0.1) var size_variation: float = 0.7:
	set(value):
		size_variation = value
		_generate_preview()

@export_range(1, 5, 1) var border_buffer: int = 2:
	set(value):
		border_buffer = value
		_generate_preview()

@export_range(1, 10, 1) var max_expansion_attempts: int = 3:
	set(value):
		max_expansion_attempts = value
		_generate_preview()

@export_range(0.0, 1.0, 0.05) var horizontal_expansion_bias: float = 0.5:
	set(value):
		horizontal_expansion_bias = value
		_generate_preview()

@export_group("Decoration")
@export_range(0, 1, 0.05) var floor_variation_chance: float = 0.05:
	set(value):
		floor_variation_chance = value
		_generate_preview()

@export_range(0, 1, 0.05) var cracked_wall_chance: float = 0.15:
	set(value):
		cracked_wall_chance = value
		_generate_preview()

@export_range(0, 1, 0.05) var light_chance: float = 0.10:
	set(value):
		light_chance = value
		_generate_preview()

@export_range(0, 1, 0.05) var wall_window_chance: float = 0.10:
	set(value):
		wall_window_chance = value
		_generate_preview()

@export_group("")  # Reset group
@export_tool_button("Regenerate Map")
var regenerate_action: Callable = func() -> void: _generate_preview()

@export var terrain_mode: bool = false:
	set(value):
		terrain_mode = value
		_render_map()

@export var god_mode: bool = true:
	set(value):
		god_mode = value
		_render_map()

@export var debug_splits: bool = true:
	set(value):
		debug_splits = value
		_update_debug_splits_visibility()

@export var debug_rooms: bool = true:
	set(value):
		debug_rooms = value
		_update_debug_rooms_visibility()

var map: Map
var map_renderer: MapRenderer
var split_rects: Node2D
var room_rects: Node2D  # New node for room debugging

const CELL_SIZE = 16  # Assuming 16x16 tiles


func _ready() -> void:
	if Engine.is_editor_hint():
		# Initialize Dice RNG
		Dice.set_seed()

		# Initialize ItemFactory to ensure items are loaded
		ItemFactory._static_init()

		# Create debug container
		split_rects = Node2D.new()
		split_rects.name = "SplitRects"
		add_child(split_rects)

		room_rects = Node2D.new()
		room_rects.name = "RoomRects"
		add_child(room_rects)

		# Instantiate MapRenderer and add it as a child
		map_renderer = MapRenderer.new()
		add_child(map_renderer)

		# Wait one frame for MapRenderer to initialize its layers
		await get_tree().process_frame
		_generate_preview()


func _generate_preview() -> void:
	if not is_node_ready() or not map_renderer:
		return

	# Clear previous debug elements
	for child in split_rects.get_children():
		child.queue_free()
	for child in room_rects.get_children():
		child.queue_free()

	# Create generator and regenerate map with current parameters
	var generator := MapGeneratorFactory.create_generator(generator_type)
	if not generator:
		Log.e("Failed to create generator for type: %s" % generator_type)
		return

	var params := {
		# BSP parameters
		"subdivision_levels": subdivision_levels,
		"min_room_size":
		(
			dungeon_min_room_size
			if generator_type == MapGeneratorFactory.GeneratorType.DUNGEON
			else min_room_size
		),
		"min_split_size": min_split_size,
		"horizontal_split_chance": horizontal_split_chance,
		# Dungeon generation parameters
		"max_room_size": max_room_size,
		"size_variation": size_variation,
		"room_placement_attempts": room_placement_attempts,
		"target_room_count": target_room_count,
		"border_buffer": border_buffer,
		"room_expansion_chance": room_expansion_chance,
		"max_expansion_attempts": max_expansion_attempts,
		"horizontal_expansion_bias": horizontal_expansion_bias,
		# Decoration parameters
		"floor_variation_chance": floor_variation_chance,
		"light_chance": light_chance,
		"cracked_wall_chance": cracked_wall_chance,
		"wall_window_chance": wall_window_chance
	}

	# Generate the map
	map = generator.generate_map(width, height, params)

	# Check if map generation failed
	if not map:
		Log.e("Map generation failed - generator returned null")
		return

	if debug_splits:
		# Create debug rectangles for splits
		for split in generator.debug_splits:
			var rect := ReferenceRect.new()
			rect.position = Vector2(split.x * CELL_SIZE, split.y * CELL_SIZE)
			rect.size = Vector2(split.width * CELL_SIZE, split.height * CELL_SIZE)
			rect.editor_only = true
			rect.border_color = Color.RED if split.is_horizontal else Color.BLUE
			rect.border_width = 2.0
			rect.z_index = 1000
			rect.modulate = Color(1, 1, 1, 0.75)
			split_rects.add_child(rect)

	if debug_rooms:
		# Create debug visualization for rooms
		for room in map.rooms:
			var rect := ReferenceRect.new()
			rect.position = Vector2(room.x * CELL_SIZE, room.y * CELL_SIZE)
			rect.size = Vector2(room.width * CELL_SIZE, room.height * CELL_SIZE)
			rect.editor_only = true
			rect.border_color = Color.GREEN
			rect.border_width = 2.0
			rect.z_index = 1000
			rect.modulate = Color(1, 1, 1, 0.5)
			room_rects.add_child(rect)

			# Add room type label
			var label := Label.new()
			label.position = rect.position + Vector2(5, 5)
			label.text = Room.Type.keys()[room.type]
			label.z_index = 1000
			label.theme = preload("res://assets/ui/main.tres")
			label.modulate = Color(1, 1, 1, 0.75)
			room_rects.add_child(label)

	_render_map()


func _render_map() -> void:
	# Update parameters and render the map
	map_renderer.initialize_tile_layers()
	map_renderer.god_mode = god_mode
	map_renderer.terrain_mode = terrain_mode
	map_renderer.render_map(map)


func _update_debug_splits_visibility() -> void:
	if split_rects:
		split_rects.visible = debug_splits


func _update_debug_rooms_visibility() -> void:
	if room_rects:
		room_rects.visible = debug_rooms
