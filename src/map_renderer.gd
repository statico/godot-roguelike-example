@tool
@icon("res://assets/icons/map.svg")
class_name MapRenderer
extends Node2D

const HINTS_LAYER_MODULATE := Color(0.0, 0.0, 0.0, 0.2)
const VISION_LAYER_MODULATE := Color(0.0, 0.0, 0.0, 0.4)

@export var terrain_mode: bool = false
@export var god_mode: bool = false

var obstacle_layer: TileMapLayer
var hints_layer: TileMapLayer
var terrain_layer: TileMapLayer
var decoration_layer: TileMapLayer
var stains_layer: Node2D
var highlight_layer: Node  # Use by outside code to path highlights and things
var item_layer: TileMapLayer
var vision_layer: TileMapLayer
var item_stack_layer1: TileMapLayer
var item_stack_layer2: TileMapLayer
var alerts_layer: Node2D
var dust_motes: Array[DustMotes] = []
var current_map_id: String = ""
var effects: Dictionary = {}  # pos -> ColorRect

const DecType = DungeonDecorationType.Type

# Stain texture, 144x16px with 6 frames
var stain_texture := preload("res://assets/textures/fx/blood.png")


func _ready() -> void:
	# Initialize tile layers
	initialize_tile_layers()


func initialize_tile_layers() -> void:
	# Create our tile layers
	var world_tileset: TileSet = preload("res://assets/generated/world_tiles.tres")
	world_tileset.tile_size = Vector2i(16, 16)
	var item_tileset: TileSet = preload("res://assets/generated/item_sprites.tres")
	item_tileset.tile_size = Vector2i(16, 16)

	# Remove existing layers if they exist
	if hints_layer:
		remove_child(hints_layer)
	if terrain_layer:
		remove_child(terrain_layer)
	if decoration_layer:
		remove_child(decoration_layer)
	if stains_layer:
		remove_child(stains_layer)
	if highlight_layer:
		remove_child(highlight_layer)
	if obstacle_layer:
		remove_child(obstacle_layer)
	if item_layer:
		remove_child(item_layer)
	if item_stack_layer1:
		remove_child(item_stack_layer1)
	if item_stack_layer2:
		remove_child(item_stack_layer2)
	if vision_layer:
		remove_child(vision_layer)
	if alerts_layer:
		remove_child(alerts_layer)

	# Initialize new layers in order from bottom to top
	var hints := TileMapLayer.new()
	hints.name = "Hints"
	hints.tile_set = world_tileset
	add_child(hints)
	hints_layer = hints
	hints_layer.modulate = HINTS_LAYER_MODULATE

	var terrain := TileMapLayer.new()
	terrain.name = "Terrain"
	terrain.tile_set = world_tileset
	add_child(terrain)
	terrain_layer = terrain

	var decoration := TileMapLayer.new()
	decoration.name = "Decoration"
	decoration.tile_set = world_tileset
	add_child(decoration)
	decoration_layer = decoration

	var stains := Node2D.new()
	stains.name = "Stains"
	add_child(stains)
	stains_layer = stains

	var highlight := Node2D.new()
	highlight.name = "Highlight"
	add_child(highlight)
	highlight_layer = highlight

	var obstacle := TileMapLayer.new()
	obstacle.name = "Obstacles"
	obstacle.tile_set = world_tileset
	add_child(obstacle)
	obstacle_layer = obstacle

	var item := TileMapLayer.new()
	item.name = "Items"
	item.tile_set = item_tileset
	add_child(item)
	item_layer = item

	var item_stack1 := TileMapLayer.new()
	item_stack1.name = "ItemStack1"
	item_stack1.tile_set = item_tileset
	item_stack1.position = Vector2(2, 2)
	add_child(item_stack1)
	item_stack_layer1 = item_stack1

	var item_stack2 := TileMapLayer.new()
	item_stack2.name = "ItemStack2"
	item_stack2.tile_set = item_tileset
	item_stack2.position = Vector2(-2, -2)
	add_child(item_stack2)
	item_stack_layer2 = item_stack2

	var alerts := Node2D.new()
	alerts.name = "Alerts"
	add_child(alerts)
	alerts_layer = alerts

	var vision := TileMapLayer.new()
	vision.name = "Vision"
	vision.tile_set = world_tileset
	add_child(vision)
	vision_layer = vision
	vision_layer.modulate = VISION_LAYER_MODULATE


func render_map(map: Map) -> void:
	clear_layers()
	render_ground(map)
	render_decorations(map)
	render_obstacles(map)
	render_items(map)
	render_vision(map)
	render_area_effects(map)
	render_stains(map)

	# Only respawn dust motes if the map has changed
	var map_changed := current_map_id != map.id
	current_map_id = map.id
	if map_changed:
		spawn_dust_motes(map)

	# Update dust mote visibility
	for mote in dust_motes:
		var center_pos := Vector2i(mote.position / 16)  # Convert pixel position back to grid coordinates
		mote.set_dust_visible(map.is_visible(center_pos))


func clear_layers() -> void:
	hints_layer.clear()
	terrain_layer.clear()
	decoration_layer.clear()
	obstacle_layer.clear()
	item_layer.clear()
	item_stack_layer1.clear()
	item_stack_layer2.clear()
	vision_layer.clear()
	for node: Node in effects.values():
		node.queue_free()
	effects.clear()
	for node: Node in stains_layer.get_children():
		node.queue_free()


func render_ground(map: Map) -> void:
	for x in range(map.width):
		for y in range(map.height):
			var pos := Vector2i(x, y)
			var cell: MapCell = map.cells[x][y]
			var terrain := cell.terrain

			if terrain.type != Terrain.Type.EMPTY:
				# Add hint tiles for surrounding tiles up to 4 spaces away
				for dx in range(-4, 5):  # from -4 to 4
					for dy in range(-4, 5):  # from -4 to 4
						if abs(dx) + abs(dy) <= 3:  # Check if within 3 spaces
							var hint_pos := Vector2i(x + dx, y + dy)
							if map.is_in_bounds(hint_pos):
								hints_layer.set_cell(
									hint_pos, 0, WorldTiles.get_coords(&"floor-7-nsew")
								)

			if not god_mode and not map.was_seen(pos):
				continue

			var tile: StringName

			match terrain.type:
				Terrain.Type.DUNGEON_FLOOR:
					if terrain_mode:
						match cell.area_type:
							MapCell.Type.ROOM:
								tile = &"floor-7-nsew"
							MapCell.Type.CORRIDOR:
								tile = &"floor-7-nsew"
							_:  # NONE or unknown
								tile = &"floor-7-nsew"
					else:
						# Other tilesets used to have lots of variations of floor tiles,
						# but now we just have one.
						match cell.decoration_type:
							DecType.FLOOR_VARIATION_1:
								tile = &"floor-7-nsew"
							DecType.FLOOR_VARIATION_2:
								tile = &"floor-7-nsew"
							DecType.FLOOR_VARIATION_3:
								tile = &"floor-7-nsew"
							DecType.FLOOR_VARIATION_4:
								tile = &"floor-7-nsew"
							_:  # normal floor
								tile = &"floor-7-nsew"
				Terrain.Type.DUNGEON_WALL:
					if terrain_mode:
						tile = &"wall-5-lone"
					else:
						tile = get_wall_tile(pos, map)

			if tile:
				terrain_layer.set_cell(pos, 0, WorldTiles.get_coords(tile))

	# New directional hint placement outside the main loop
	for x in range(map.width):
		for y in range(map.height):
			var cell: TileData = hints_layer.get_cell_tile_data(Vector2i(x, y))
			if cell == null:
				continue

			# Use the debug tile, which is just a square and gets modulated to black
			var tile := &"debug"
			hints_layer.set_cell(Vector2i(x, y), 0, WorldTiles.get_coords(tile))


func render_decorations(map: Map) -> void:
	if terrain_mode:
		return

	for x in range(map.width):
		for y in range(map.height):
			var pos := Vector2i(x, y)
			# Skip if cell has never been seen
			if not god_mode and not map.was_seen(pos):
				continue

			var cell: MapCell = map.cells[x][y]
			var tile: StringName
			match cell.decoration_type:
				DecType.NORTH_LIGHT:
					# Add light decoration to any wall above
					if y > 0:
						var wall_pos := Vector2i(x, y - 1)
						var wall_data := terrain_layer.get_cell_tile_data(wall_pos)
						if wall_data:  # If there's any wall tile above
							decoration_layer.set_cell(
								wall_pos, 0, WorldTiles.get_coords(&"decor-32")
							)
				DecType.SOUTH_LIGHT:
					# Only place south lights under horizontal walls
					if y > 0:
						var wall_pos := Vector2i(x, y - 1)
						var wall_data := terrain_layer.get_cell_tile_data(wall_pos)
						if (
							wall_data
							and (
								WorldTiles.get_name_from_coords(
									terrain_layer.get_cell_atlas_coords(wall_pos)
								)
								== &"grey-wall-ew"
							)
						):
							tile = &"grey-light-yellow-south"
				DecType.WINDOW_1:
					tile = &"grey-wall-window1"
				DecType.WINDOW_2:
					tile = &"grey-wall-window2"
				DecType.WINDOW_3:
					tile = &"grey-wall-window3"
			if tile:
				decoration_layer.set_cell(pos, 0, WorldTiles.get_coords(tile))


func is_corner_wall(pos: Vector2i, map: Map) -> bool:
	# Count walls in cardinal directions (N, S, E, W)
	var n: bool = (
		pos.y > 0 and map.get_terrain(Vector2i(pos.x, pos.y - 1)).type == Terrain.Type.DUNGEON_WALL
	)
	var s: bool = (
		pos.y < map.height - 1
		and map.get_terrain(Vector2i(pos.x, pos.y + 1)).type == Terrain.Type.DUNGEON_WALL
	)
	var e: bool = (
		pos.x < map.width - 1
		and map.get_terrain(Vector2i(pos.x + 1, pos.y)).type == Terrain.Type.DUNGEON_WALL
	)
	var w: bool = (
		pos.x > 0 and map.get_terrain(Vector2i(pos.x - 1, pos.y)).type == Terrain.Type.DUNGEON_WALL
	)

	# A corner wall should have exactly two adjacent walls at right angles
	return (n and e) or (n and w) or (s and e) or (s and w)


func is_vertical_wall(x: int, y: int, map: Map) -> bool:
	var vertical_walls: int = 0
	for dy: int in [-1, 1]:
		var check_y: int = y + dy
		if check_y >= 0 and check_y < map.height:
			if map.get_terrain(Vector2i(x, check_y)).type == Terrain.Type.DUNGEON_WALL:
				vertical_walls += 1
	return vertical_walls > 0


func get_wall_tile(pos: Vector2i, map: Map) -> StringName:
	# Count walls in cardinal directions (N, S, E, W)
	var n: bool = pos.y > 0 and is_wall_like(map.get_terrain(Vector2i(pos.x, pos.y - 1)))
	var s: bool = (
		pos.y < map.height - 1 and is_wall_like(map.get_terrain(Vector2i(pos.x, pos.y + 1)))
	)
	var e: bool = (
		pos.x < map.width - 1 and is_wall_like(map.get_terrain(Vector2i(pos.x + 1, pos.y)))
	)
	var w: bool = pos.x > 0 and is_wall_like(map.get_terrain(Vector2i(pos.x - 1, pos.y)))

	var ret := &"wall-5-lone"

	# All four directions
	if n and s and e and w:
		ret = &"wall-5-nsew"
	# Three directions
	elif n and s and e and !w:
		ret = &"wall-5-nse"
	elif n and s and !e and w:
		ret = &"wall-5-nsw"
	elif n and !s and e and w:
		ret = &"wall-5-new"
	elif !n and s and e and w:
		ret = &"wall-5-sew"
	# Two directions
	elif n and s and !e and !w:
		ret = &"wall-5-ns"
	elif !n and !s and e and w:
		ret = &"wall-5-ew"
	elif n and e and !s and !w:
		ret = &"wall-5-ne"
	elif n and w and !s and !e:
		ret = &"wall-5-nw"
	elif s and e and !n and !w:
		ret = &"wall-5-se"
	elif s and w and !n and !e:
		ret = &"wall-5-sw"
	# One direction (other tilesets do this a little clearer)
	elif !n and !s and !w and e:
		ret = &"wall-5-ew"
	elif !n and !s and w and !e:
		ret = &"wall-5-ew"
	elif n and !s and !e and !w:
		ret = &"wall-5-n"
	elif !n and s and !e and !w:
		ret = &"wall-5-ns"

	return ret


func is_wall_like(terrain: Terrain) -> bool:
	return terrain.type == Terrain.Type.DUNGEON_WALL


func get_obstacle_tile(obstacle: Obstacle) -> StringName:
	match obstacle.type:
		Obstacle.Type.STAIRS_UP:
			return &"tile-28"
		Obstacle.Type.STAIRS_DOWN:
			return &"tile-31"
		Obstacle.Type.DOOR_OPEN:
			return &"doors1-0"
		Obstacle.Type.DOOR_CLOSED:
			return &"doors0-0"
		Obstacle.Type.ICE_BLOCK:
			return &"tile-3"
		Obstacle.Type.COFFIN:
			return &"decor-54"
		Obstacle.Type.ALTAR:
			match obstacle.direction:
				Obstacle.Direction.NONE:
					Log.w("ALTAR direction NONE is not supported")
					return &"debug"
				Obstacle.Direction.EAST:
					return &"decor-48"
				Obstacle.Direction.BOTH:
					return &"decor-49"
				Obstacle.Direction.WEST:
					return &"decor-50"
		Obstacle.Type.SHELVES_WITH_BOOKS:
			return &"decor-5"
		Obstacle.Type.SHELVES_EMPTY:
			return &"decor-0"
		Obstacle.Type.CHAIR:
			return &"decor-24"
		Obstacle.Type.TABLE:
			return &"decor-25"

	Log.w("Unknown obstacle type: %s" % Obstacle.Type.keys()[obstacle.type])
	return &"debug"  # Debug tile


func render_obstacles(map: Map) -> void:
	if terrain_mode:
		return

	for x: int in range(map.width):
		for y: int in range(map.height):
			var pos := Vector2i(x, y)
			# Skip if cell has never been seen
			if not god_mode and not map.was_seen(pos):
				continue

			var obstacle: Obstacle = map.get_obstacle(pos)
			if obstacle:
				# Only render the bottom part of vertical multi-cell obstacles
				# or single-cell obstacles
				if (
					not obstacle.is_vertical_multi_cell()
					or obstacle.direction == Obstacle.Direction.SOUTH
				):
					var tile := get_obstacle_tile(obstacle)
					if tile:
						obstacle_layer.set_cell(pos, 0, WorldTiles.get_coords(tile))

						# If this is the bottom part of a vertical multi-cell obstacle,
						# also render the top part
						if obstacle.direction == Obstacle.Direction.SOUTH:
							var top_pos := Vector2i(x, y - 1)
							var top_obstacle := map.get_obstacle(top_pos)
							if top_obstacle and top_obstacle.direction == Obstacle.Direction.NORTH:
								var top_tile := get_obstacle_tile(top_obstacle)
								if top_tile:
									obstacle_layer.set_cell(
										top_pos, 0, WorldTiles.get_coords(top_tile)
									)


func render_items(map: Map) -> void:
	# Clear existing layers
	item_layer.clear()
	item_stack_layer1.clear()
	item_stack_layer2.clear()
	for child in alerts_layer.get_children():
		child.queue_free()

	# Don't render items in terrain mode
	if terrain_mode:
		return

	for x in range(map.width):
		for y in range(map.height):
			var pos := Vector2i(x, y)
			# Skip if cell has never been seen
			if not god_mode and not map.was_seen(pos):
				continue

			var cell: MapCell = map.cells[x][y]
			var items := cell.items
			if not items.is_empty():
				var item: Item = items[0]  # Show only the top item for now
				var atlas_coords := ItemTiles.get_coords(item.sprite_name)

				if item.quantity <= 1:
					item_layer.set_cell(pos, 0, atlas_coords)
				else:
					# Render stacked items
					item_stack_layer1.set_cell(pos, 0, atlas_coords)
					item_stack_layer2.set_cell(pos, 0, atlas_coords)

				# Add alert for armed items
				if item.is_armed:
					# Maybe use an AnimatedSprite2D instead with a sprite frames asset
					var alert: Node2D = preload("res://scenes/ui/alert.tscn").instantiate()
					alert.position = (
						Vector2(pos * Constants.TILE_SIZE) + Constants.HALF_TILE_SIZE_VEC2
					)
					alerts_layer.add_child(alert)


func render_vision(map: Map) -> void:
	vision_layer.clear()

	if god_mode:
		return

	# First pass: place vision blockers
	for x in range(map.width):
		for y in range(map.height):
			var pos := Vector2i(x, y)
			# Only place vision tiles on non-empty, previously seen terrain
			if (
				not map.is_visible(pos)
				and map.was_seen(pos)
				and map.get_terrain(pos).type != Terrain.Type.EMPTY
			):
				vision_layer.set_cell(pos, 0, WorldTiles.get_coords(&"debug"))

	# Second pass: update tiles based on neighbors
	for x in range(map.width):
		for y in range(map.height):
			var pos := Vector2i(x, y)
			var cell: TileData = vision_layer.get_cell_tile_data(pos)
			if cell == null:
				continue

			var n: bool = vision_layer.get_cell_tile_data(Vector2i(x, y - 1)) != null
			var s: bool = vision_layer.get_cell_tile_data(Vector2i(x, y + 1)) != null
			var e: bool = vision_layer.get_cell_tile_data(Vector2i(x + 1, y)) != null
			var w: bool = vision_layer.get_cell_tile_data(Vector2i(x - 1, y)) != null

			var tile: Vector2i = WorldTiles.get_coords(&"debug")
			if n and s and e and w:
				tile = WorldTiles.get_coords(&"debug")
			elif n and e and w:
				tile = WorldTiles.get_coords(&"debug")
			elif n and s and e:
				tile = WorldTiles.get_coords(&"debug")
			elif n and s and w:
				tile = WorldTiles.get_coords(&"debug")
			elif s and e and w:
				tile = WorldTiles.get_coords(&"debug")
			elif s and e:
				tile = WorldTiles.get_coords(&"debug")
			elif s and w:
				tile = WorldTiles.get_coords(&"debug")
			elif n and e:
				tile = WorldTiles.get_coords(&"debug")
			elif n and w:
				tile = WorldTiles.get_coords(&"debug")
			elif n and s:
				tile = WorldTiles.get_coords(&"debug")
			elif e and w:
				tile = WorldTiles.get_coords(&"debug")
			elif n:
				tile = WorldTiles.get_coords(&"debug")
			elif s:
				tile = WorldTiles.get_coords(&"debug")
			elif e:
				tile = WorldTiles.get_coords(&"debug")
			elif w:
				tile = WorldTiles.get_coords(&"debug")
			else:
				tile = WorldTiles.get_coords(&"debug")

			vision_layer.set_cell(pos, 0, tile)


func spawn_dust_motes(map: Map) -> void:
	if Engine.is_editor_hint():
		return

	# Clear existing dust motes
	for mote in dust_motes:
		mote.queue_free()
	dust_motes.clear()

	# Create new dust motes for each room
	for room in map.rooms:
		# Calculate room center
		var center_x := int(room.x + (room.width / 2.0))
		var center_y := int(room.y + (room.height / 2.0))

		# Create dust motes at room center
		var dust_scene := preload("res://scenes/fx/dust_motes.tscn")
		var dust_instance: DustMotes = dust_scene.instantiate()
		dust_instance.position = Vector2(center_x * 16, center_y * 16)  # Multiply by tile size

		# Calculate the room's interior rectangle in local coordinates
		# Convert from tile coordinates to pixels and center around the dust mote position
		var half_width := (room.width * 16) / 2.0
		var half_height := (room.height * 16) / 2.0
		var rect := Rect2(-half_width, -half_height, room.width * 16, room.height * 16)

		# Set the clipping rect on the dust mote instance
		dust_instance.set_rect(rect)

		add_child(dust_instance)
		dust_motes.append(dust_instance)


func render_area_effects(map: Map) -> void:
	# Clear old effects
	for node: Node in effects.values():
		node.queue_free()
	effects.clear()

	# Create new effect visuals
	for x in range(map.width):
		for y in range(map.height):
			var cell := map.get_cell(Vector2i(x, y))
			if not cell.area_effects.is_empty():
				match cell.area_effects[0].type:
					Damage.Type.POISON:
						var node: Node2D = (
							preload("res://scenes/fx/splatter_green.tscn").instantiate()
						)
						(node.get_node("%Splatter") as AnimatedSprite2D).frame = randi_range(0, 8)
						add_child(node)
						(node.get_node("%Bubbles") as GPUParticles2D).preprocess = randf()
						node.position = (
							Vector2(x, y) * Constants.TILE_SIZE + Constants.HALF_TILE_SIZE_VEC2
						)
						add_child(node)
						effects[Vector2i(x, y)] = node
					_:
						# Placeholder white squares
						var rect := ColorRect.new()
						rect.size = Vector2(Constants.TILE_SIZE, Constants.TILE_SIZE)
						rect.position = Vector2(x, y) * Constants.TILE_SIZE
						rect.color.a = 0.5
						add_child(rect)
						effects[Vector2i(x, y)] = rect


func render_stains(map: Map) -> void:
	for x in range(map.width):
		for y in range(map.height):
			var pos := Vector2i(x, y)
			# Skip if cell has never been seen
			if not god_mode and not map.was_seen(pos):
				continue

			var cell := map.get_cell(pos)
			if cell.stain_frame >= 0:
				var sprite := Sprite2D.new()
				sprite.texture = stain_texture
				sprite.region_enabled = true
				sprite.region_rect = Rect2(cell.stain_frame * 16, 0, 16, 16)
				sprite.modulate = Color(cell.stain_color, 0.66)
				sprite.position = (
					Vector2(pos * Constants.TILE_SIZE) + Constants.HALF_TILE_SIZE_VEC2
				)
				stains_layer.add_child(sprite)
