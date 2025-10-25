class_name DungeonGenerator
extends BaseMapGenerator

const DecType = DungeonDecorationType.Type
const TerrainType = Terrain.Type

# Room generation constants
const ROOM_START_OFFSET := 4
const ROOM_PADDING := 8
const DEFAULT_SUBDIVISION_LEVELS := 3
const DEFAULT_MIN_ROOM_SIZE := 7
const DEFAULT_MIN_SPLIT_SIZE := 6
const DEFAULT_HORIZONTAL_SPLIT_CHANCE := 0.4

# Decoration chances
const DEFAULT_DECORATION_CHANCES := {
	"floor_variation": 0.05,
	"light": 0.17,
	"cracked_wall": 0.15,
	"window": 0.10,
}


# Represents the configuration of an obstacle type
class ObstacleConfig:
	var type: Obstacle.Type
	var width := 1
	var height := 1
	var needs_wall := false  # For obstacles that need to be against walls
	var is_vertical := false  # For multi-cell obstacles, specifies if they're vertical
	var spawn_chance := 1.0  # Probability of this obstacle being chosen (0.0 to 1.0)
	var density := 0.125  # Density factor for calculating number of obstacles (default: 1/8)
	var min_obstacles := 4  # Minimum number of obstacles to place
	var max_obstacles := 8  # Maximum number of obstacles to place

	func is_multi_cell() -> bool:
		return width > 1 or height > 1

	func _to_string() -> String:
		return (
			"ObstacleConfig(type: %s, width: %d, height: %d, needs_wall: %s, is_vertical: %s, spawn_chance: %f, density: %f, min_obstacles: %d, max_obstacles: %d)"
			% [
				Obstacle.Type.keys()[type],
				width,
				height,
				needs_wall,
				is_vertical,
				spawn_chance,
				density,
				min_obstacles,
				max_obstacles
			]
		)


var _rng: RandomNumberGenerator


# Add this as a helper class at the top of the file, after the constants
class RoomConnection:
	var room1_id: int
	var room2_id: int
	var distance: float

	func _init(p_room1_id: int, p_room2_id: int, p_distance: float) -> void:
		room1_id = p_room1_id
		room2_id = p_room2_id
		distance = p_distance


# Add this as a helper class for the union-find data structure
class DisjointSet:
	var parent: Array[int]

	func _init(size: int) -> void:
		parent = []
		for i in range(size):
			parent.append(i)

	func find(x: int) -> int:
		if parent[x] != x:
			parent[x] = find(parent[x])  # Path compression
		return parent[x]

	func union(x: int, y: int) -> void:
		var root_x := find(x)
		var root_y := find(y)
		if root_x != root_y:
			parent[root_y] = root_x


func _pick_room_type() -> Room.Type:
	var table := Dice.WeightedTable.new()
	table.add_entry(Room.Type.DUNGEON_EMPTY, 20)
	table.add_entry(Room.Type.DUNGEON_ALTAR, 15)
	table.add_entry(Room.Type.DUNGEON_LIBRARY, 15)
	table.add_entry(Room.Type.DUNGEON_ICE_STORAGE, 10)
	table.add_entry(Room.Type.DUNGEON_CRYPT, 10)
	return table.roll()


func _get_obstacle_configs_for_room(room_type: Room.Type) -> Array[ObstacleConfig]:
	var configs: Array[ObstacleConfig] = []

	match room_type:
		Room.Type.DUNGEON_EMPTY:
			pass

		Room.Type.DUNGEON_ALTAR:
			var altar := ObstacleConfig.new()
			altar.type = Obstacle.Type.ALTAR
			altar.width = _rng.randi_range(2, 4)
			altar.spawn_chance = 0.7 / 3.0
			altar.min_obstacles = 1
			altar.max_obstacles = 1
			configs.append(altar)

		Room.Type.DUNGEON_LIBRARY:
			var shelves := ObstacleConfig.new()
			shelves.type = Obstacle.Type.SHELVES_WITH_BOOKS
			shelves.needs_wall = true
			shelves.spawn_chance = 0.8
			shelves.density = 0.7
			configs.append(shelves)

			var chair := ObstacleConfig.new()
			chair.type = Obstacle.Type.CHAIR
			chair.spawn_chance = 0.4
			chair.density = 0.3
			configs.append(chair)

		Room.Type.DUNGEON_UTILITY:
			var desk := ObstacleConfig.new()
			desk.type = Obstacle.Type.TABLE
			desk.spawn_chance = 0.6
			desk.density = 0.4
			configs.append(desk)

			var chair := ObstacleConfig.new()
			chair.type = Obstacle.Type.CHAIR
			chair.spawn_chance = 0.4
			chair.density = 0.4
			configs.append(chair)

		Room.Type.DUNGEON_ICE_STORAGE:
			var ice_block := ObstacleConfig.new()
			ice_block.type = Obstacle.Type.ICE_BLOCK
			ice_block.spawn_chance = 0.9
			ice_block.density = 0.5
			ice_block.min_obstacles = 2
			configs.append(ice_block)

		Room.Type.DUNGEON_CRYPT:
			var coffin := ObstacleConfig.new()
			coffin.type = Obstacle.Type.COFFIN
			coffin.spawn_chance = 0.8
			coffin.density = 0.8
			configs.append(coffin)

	return configs


func generate_map(width: int, height: int, params: Dictionary = {}) -> Map:
	Log.d("Generating map with params: %s" % params)

	# Initialize factories if not already done
	if ItemFactory.item_data.is_empty():
		ItemFactory._static_init()
	if MonsterFactory.monster_data.is_empty():
		MonsterFactory._static_init()

	# Initialize Dice RNG
	Dice.set_seed()

	var depth: int = params.get("depth", 1)
	var attempts := 50
	var map: Map

	while attempts > 0:
		map = _initialize_empty_map(width, height, depth)
		_rng = RandomNumberGenerator.new()
		Dice._rng = _rng

		if not _generate_basic_structure(map, width, height, params):
			attempts -= 1
			continue

		# Validate map requirements
		if map.rooms.size() < 5:
			Log.d("Map has fewer than 5 rooms, regenerating...")
			attempts -= 1
			continue

		# Check for stairs only if they're required
		if params.get("has_up_stairs", true) and not map.has_stairs_up():
			Log.d("Map missing up stairs, regenerating...")
			attempts -= 1
			continue

		if params.get("has_down_stairs", true) and not map.has_stairs_down():
			Log.d("Map missing down stairs, regenerating...")
			attempts -= 1
			continue

		# If we get here, the map is valid
		_populate_level(map, width, height)
		_add_decorations(map, params)
		return map

	# If we get here, we failed to generate a valid map
	Log.e("Failed to generate valid map after %d attempts" % 50)
	return null


func _generate_basic_structure(map: Map, width: int, height: int, params: Dictionary) -> bool:
	Log.d("Generating basic structure")

	var rooms := _generate_empty_rooms(width, height, params)
	if rooms.is_empty():
		return false

	_connect_all_rooms(map, rooms)

	# First carve out all rooms without obstacles
	for room in rooms:
		_carve_room_basic(map, room)

	# Place doors
	_place_doors(map)

	# Add level features (stairs) first
	_add_level_features(map, params.get("depth", 1) as int, params)

	# Then add room-specific obstacles
	for room in rooms:
		_place_room_obstacles(map, room)

	return true


func _add_level_features(map: Map, depth: int, params: Dictionary) -> void:
	Log.d("Adding level features")

	var rooms: Array[Room] = map.rooms.duplicate()
	rooms.shuffle()

	if params.get("has_up_stairs", true):
		_place_up_stairs(map, rooms[0], depth)
	if params.get("has_down_stairs", true):
		_place_down_stairs(map, rooms[1], depth)
	if params.get("has_amulet", false):
		_place_amulet(map, rooms[-1])


func _populate_level(map: Map, width: int, height: int) -> void:
	Log.d("Populating level")

	# Update this to change item and monster density
	_place_monsters(map, int(sqrt(width * height) / 10))
	_place_items(map, int(sqrt(width * height) / 5))

	# Add special items to specific room types
	for room in map.rooms:
		if room.type == Room.Type.DUNGEON_LIBRARY:
			_place_books(map, room)


func _add_decorations(map: Map, params: Dictionary) -> void:
	Log.d("Adding decorations")

	var chances := DEFAULT_DECORATION_CHANCES.duplicate()
	chances.merge(params, true)  # Override defaults with any provided values

	for x in range(map.width):
		for y in range(map.height):
			var cell: MapCell = map.cells[x][y]
			match cell.terrain.type:
				TerrainType.DUNGEON_FLOOR:
					_add_floor_decorations(map, cell, x, y, chances)
				TerrainType.DUNGEON_WALL:
					_add_wall_decorations(map, cell, x, y, chances)


func _add_floor_decorations(map: Map, cell: MapCell, x: int, y: int, chances: Dictionary) -> void:
	if _rng.randf() < chances.floor_variation:
		cell.decoration_type = DecType.FLOOR_VARIATION_1 + _rng.randi_range(0, 3)
	elif _rng.randf() < chances.light:
		_place_wall_light(map, cell, x, y)


func _add_wall_decorations(map: Map, cell: MapCell, x: int, y: int, chances: Dictionary) -> void:
	if is_corner_wall(x, y, map):
		return

	if _rng.randf() < chances.cracked_wall:
		cell.decoration_type = (
			DecType.VERTICAL_CRACK
			if is_vertical_wall(x, y, map)
			else DecType.HORIZONTAL_CRACK if is_horizontal_wall(x, y, map) else DecType.NONE
		)


func _generate_empty_rooms(width: int, height: int, params: Dictionary) -> Array[Room]:
	Log.d("Generating empty rooms using station algorithm")

	# Set up parameters for the station room generator
	var dungeon_params := {
		"min_room_size": params.get("min_room_size", 5),
		"max_room_size": params.get("max_room_size", 15),
		"size_variation": params.get("size_variation", 0.7),
		"room_placement_attempts": params.get("room_placement_attempts", 500),
		"target_room_count": params.get("target_room_count", 20),
		"border_buffer": params.get("border_buffer", 2),
		"room_expansion_chance": params.get("room_expansion_chance", 0.5),
		"max_expansion_attempts": params.get("max_expansion_attempts", 3),
		"horizontal_expansion_bias": params.get("horizontal_expansion_bias", 0.5)
	}

	return _generate_dungeon_rooms(width, height, dungeon_params)


func _carve_room_basic(map: Map, room: Room) -> void:
	Log.d("Carving basic room %s" % room)

	var room_type := _pick_room_type()
	room.type = room_type  # Store the room type in the Room object
	var map_room := map.add_room(room_type, room.x, room.y, room.width, room.height)
	var room_id := map_room.id

	# Add walls around the room
	for x in range(room.x - 1, room.x + room.width + 1):
		for y in range(room.y - 1, room.y + room.height + 1):
			var cell: MapCell = map.cells[x][y]
			if cell.terrain.type != TerrainType.DUNGEON_FLOOR:
				cell.terrain.type = TerrainType.DUNGEON_WALL
				cell.area_type = MapCell.Type.ROOM
				cell.room_type = room_type
				cell.room_id = room_id

	# Add floor inside the room
	for x in range(room.x, room.x + room.width):
		for y in range(room.y, room.y + room.height):
			var cell: MapCell = map.cells[x][y]
			cell.terrain.type = TerrainType.DUNGEON_FLOOR
			cell.room_type = room_type
			cell.room_id = room_id


func _connect_all_rooms(map: Map, rooms: Array[Room]) -> void:
	Log.d("Connecting all rooms using minimum spanning tree")

	if rooms.size() < 2:
		return

	# Create a list of all possible connections between rooms
	var connections: Array[RoomConnection] = []
	for i in range(rooms.size()):
		for j in range(i + 1, rooms.size()):
			var room1 := rooms[i]
			var room2 := rooms[j]
			var center1 := Vector2(room1.x + room1.width / 2.0, room1.y + room1.height / 2.0)
			var center2 := Vector2(room2.x + room2.width / 2.0, room2.y + room2.height / 2.0)
			var distance := center1.distance_to(center2)
			connections.append(RoomConnection.new(i, j, distance))

	# Sort connections by distance
	connections.sort_custom(
		func(a: RoomConnection, b: RoomConnection) -> bool: return a.distance < b.distance
	)

	# Use Kruskal's algorithm to create minimum spanning tree
	var disjoint_set := DisjointSet.new(rooms.size())
	var connected_pairs: Array[Vector2i] = []

	for connection in connections:
		if disjoint_set.find(connection.room1_id) != disjoint_set.find(connection.room2_id):
			disjoint_set.union(connection.room1_id, connection.room2_id)
			connected_pairs.append(Vector2i(connection.room1_id, connection.room2_id))

	# Create corridors for the selected connections
	for pair in connected_pairs:
		_connect_rooms(map, rooms[pair.x], rooms[pair.y])

	# Convert corridor cells that are inside room boundaries to room areas
	for room in rooms:
		for x in range(room.x, room.x + room.width):
			for y in range(room.y, room.y + room.height):
				var cell: MapCell = map.cells[x][y]
				if cell.area_type == MapCell.Type.CORRIDOR and room.contains(Vector2i(x, y)):
					cell.area_type = MapCell.Type.ROOM


func _place_doors(map: Map) -> void:
	Log.d("Placing doors")

	# Iterate through all cells
	for x in range(map.width):
		for y in range(map.height):
			var pos := Vector2i(x, y)
			var cell: MapCell = map.cells[x][y]

			# Only check corridor cells
			if cell.area_type != MapCell.Type.CORRIDOR:
				continue

			# Check if this is a corridor end (transitions to a room)
			if _is_valid_door_position(map, pos):
				var door := Obstacle.new()
				door.type = (
					Obstacle.Type.DOOR_CLOSED if _rng.randf() < 0.8 else Obstacle.Type.DOOR_OPEN
				)
				cell.obstacle = door


func _is_valid_door_position(map: Map, pos: Vector2i) -> bool:
	var cell: MapCell = map.cells[pos.x][pos.y]
	if cell.area_type != MapCell.Type.CORRIDOR:
		return false
	if cell.terrain.type != TerrainType.DUNGEON_FLOOR:
		return false

	# Check cardinal directions for room cells and walls
	var n := pos + Vector2i.UP
	var s := pos + Vector2i.DOWN
	var e := pos + Vector2i.RIGHT
	var w := pos + Vector2i.LEFT

	# First check if we have valid walls on either N/S or E/W
	var has_ns_walls: bool = (
		map.is_in_bounds(n)
		and map.is_in_bounds(s)
		and map.cells[n.x][n.y].terrain.type == TerrainType.DUNGEON_WALL
		and map.cells[s.x][s.y].terrain.type == TerrainType.DUNGEON_WALL
	)

	var has_ew_walls: bool = (
		map.is_in_bounds(e)
		and map.is_in_bounds(w)
		and map.cells[e.x][e.y].terrain.type == TerrainType.DUNGEON_WALL
		and map.cells[w.x][w.y].terrain.type == TerrainType.DUNGEON_WALL
	)

	# Must have walls on either N/S or E/W
	if not (has_ns_walls or has_ew_walls):
		return false

	# Check if any adjacent cells have doors
	for check_pos: Vector2i in [n, s, e, w]:
		if not map.is_in_bounds(check_pos):
			continue

		var check_cell: MapCell = map.cells[check_pos.x][check_pos.y]
		if (
			check_cell.obstacle
			and check_cell.obstacle.type in [Obstacle.Type.DOOR_OPEN, Obstacle.Type.DOOR_CLOSED]
		):
			return false

	# Now check for room transitions
	var has_room := false
	var has_corridor := false

	for check_pos: Vector2i in [n, s, e, w]:
		if not map.is_in_bounds(check_pos):
			continue

		var check_cell: MapCell = map.cells[check_pos.x][check_pos.y]
		if check_cell.area_type == MapCell.Type.ROOM:
			has_room = true
		elif check_cell.area_type == MapCell.Type.CORRIDOR:
			has_corridor = true

	# Return true if this cell connects a room and corridor and has proper walls
	return has_room and has_corridor


func _place_up_stairs(map: Map, room: Room, depth: int) -> void:
	Log.d("Placing up stairs")

	var attempts := 20  # Limit attempts to prevent infinite loops
	while attempts > 0:
		var pos := Vector2i(
			_rng.randi_range(room.x, room.x + room.width - 1),
			_rng.randi_range(room.y, room.y + room.height - 1)
		)

		var cell: MapCell = map.cells[pos.x][pos.y]
		if _is_valid_empty_floor(cell) and not _has_adjacent_corridor(pos, map):
			var stairs_up := Obstacle.new()
			stairs_up.type = Obstacle.Type.STAIRS_UP
			stairs_up.destination_level = (
				World.ESCAPE_LEVEL if depth == 1 else "level_%d" % (depth - 1)
			)
			cell.obstacle = stairs_up
			return
		attempts -= 1

	Log.w("Failed to place up stairs")


func _place_down_stairs(map: Map, room: Room, depth: int) -> void:
	Log.d("Placing down stairs")

	var attempts := 20  # Limit attempts to prevent infinite loops
	while attempts > 0:
		var pos := Vector2i(
			_rng.randi_range(room.x, room.x + room.width - 1),
			_rng.randi_range(room.y, room.y + room.height - 1)
		)

		var cell: MapCell = map.cells[pos.x][pos.y]
		if _is_valid_empty_floor(cell) and not _has_adjacent_corridor(pos, map):
			var stairs_down := Obstacle.new()
			stairs_down.type = Obstacle.Type.STAIRS_DOWN
			stairs_down.destination_level = "level_%d" % (depth + 1)
			cell.obstacle = stairs_down
			return
		attempts -= 1

	Log.w("Failed to place down stairs")


func _place_monsters(map: Map, count: int) -> void:
	Log.d("Placing monsters")

	# Get all monster IDs except 'human'
	var monster_ids: Array[StringName] = []
	for monster_id: StringName in MonsterFactory.monster_data:
		if monster_id != &"human":
			monster_ids.append(monster_id)

	# Place random monsters
	if monster_ids.is_empty():
		return
	for i in range(count * 2):  # Multiply by 2 since we removed the two separate loops
		var monster_id: StringName = monster_ids[_rng.randi() % monster_ids.size()]
		_place_single_monster(map, monster_id)


func _place_items(map: Map, count: int) -> void:
	Log.d("Placing items")

	# Get list of possible items weighted by probability
	var possible_items: Array[StringName] = []
	for item_id: StringName in ItemFactory.item_data:
		var probability: int = ItemFactory.item_data[item_id].probability
		if probability > 0:
			for _j in range(probability):
				possible_items.append(item_id)

	for _i in range(count):
		var tries := 0
		while tries < 10:
			var x := _rng.randi_range(1, map.width - 2)  # Avoid edges
			var y := _rng.randi_range(1, map.height - 2)
			var cell: MapCell = map.cells[x][y]
			if _is_valid_empty_floor(cell):
				# Create random item from weighted list
				if not possible_items.is_empty():
					var item_id: StringName = possible_items[_rng.randi() % possible_items.size()]
					var item := ItemFactory.create_item(item_id)

					# If it's a container, randomly open it and fill with items
					if item.is_container():
						# 30% chance to be open
						if _rng.randf() < 0.3:
							item.open()

						# Add 1-3 random items inside
						var num_items := _rng.randi_range(1, 3)
						for _j in range(num_items):
							if not possible_items.is_empty():
								var child_id: StringName = possible_items[
									_rng.randi() % possible_items.size()
								]
								var child := ItemFactory.create_item(child_id)

								# If stackable, set random quantity between 1-5
								if child.max_stack_size > 1:
									child.quantity = Dice.roll(1, 5)

								# Add item to container if there's room
								if item.children.size() < item.max_children:
									item.add_child(child)

					# If stackable, set random quantity between 1-5
					elif item.max_stack_size > 1:
						item.quantity = Dice.roll(1, 5)

					map.add_item_with_stacking(Vector2i(x, y), item)
				break
			tries += 1


func _place_room_obstacles(map: Map, room: Room) -> void:
	Log.d("Placing room obstacles")

	var obstacle_configs := _get_obstacle_configs_for_room(room.type)
	if obstacle_configs.is_empty():
		return

	var room_area := room.width * room.height
	var num_obstacles := _calculate_num_obstacles(room_area, obstacle_configs)
	var attempts := num_obstacles * 3
	var placed := 0

	while attempts > 0 and placed < num_obstacles:
		# Apply spawn chance when selecting obstacle
		var total_weight := 0.0
		for config in obstacle_configs:
			total_weight += config.spawn_chance

		var roll := _rng.randf() * total_weight
		var current_weight := 0.0
		var selected_config: ObstacleConfig

		for config in obstacle_configs:
			current_weight += config.spawn_chance
			if roll <= current_weight:
				selected_config = config
				break

		if not selected_config:
			selected_config = obstacle_configs[-1]  # Fallback to last config

		var pos := _find_valid_obstacle_position(map, room, selected_config)
		if pos != Vector2i(-1, -1):
			_place_obstacle(map, pos, selected_config)
			placed += 1
		attempts -= 1


func _calculate_num_obstacles(room_area: int, obstacle_configs: Array[ObstacleConfig]) -> int:
	# Calculate the number of obstacles based on the obstacle configs
	var total_density := 0.0
	var min_obstacles := 0
	var max_obstacles := 0

	# Aggregate the parameters from all obstacle configs
	for config in obstacle_configs:
		total_density += config.density
		min_obstacles = max(min_obstacles, config.min_obstacles)
		max_obstacles = max(max_obstacles, config.max_obstacles)

	# Calculate base number of obstacles using density
	var density_based := int(room_area * total_density)

	# Apply min/max constraints
	var num_obstacles: int = clamp(density_based, min_obstacles, max_obstacles)

	return num_obstacles


func _find_valid_obstacle_position(map: Map, room: Room, config: ObstacleConfig) -> Vector2i:
	# Account for obstacle size when determining placement bounds
	var max_x := room.x + room.width - config.width
	var max_y := room.y + room.height - config.height

	# Try multiple positions
	for _i in range(20):
		var pos := Vector2i(
			_rng.randi_range(room.x, max_x),
			# For vertical obstacles, ensure we have space at the top
			_rng.randi_range(room.y, max_y - (1 if config.is_vertical else 0))
		)

		if _is_valid_obstacle_position(map, pos, config):
			return pos

	return Vector2i(-1, -1)


func _is_valid_obstacle_position(map: Map, pos: Vector2i, config: ObstacleConfig) -> bool:
	# For obstacles that need walls, check if there's an adjacent wall
	if config.needs_wall and not has_adjacent_wall(pos.x, pos.y, map):
		return false

	# For vertical obstacles, ensure there's no wall above the entire structure
	if config.is_vertical:
		var top_y := pos.y - 1
		if top_y >= 0 and map.cells[pos.x][top_y].terrain.type == TerrainType.DUNGEON_WALL:
			return false

	# Check the entire footprint of the obstacle and its surroundings
	for x in range(pos.x - 1, pos.x + config.width + 1):
		for y in range(pos.y - 1, pos.y + config.height + 1):
			# Skip if out of bounds
			if x < 0 or x >= map.width or y < 0 or y >= map.height:
				continue

			var cell: MapCell = map.cells[x][y]

			# Check for stairs in surrounding cells
			if _has_stairs(cell):
				return false

			# For the actual obstacle footprint (not surrounding cells), check basic requirements
			if x >= pos.x and x < pos.x + config.width and y >= pos.y and y < pos.y + config.height:
				if not _is_valid_empty_floor(cell):
					return false

				# Check for nearby corridors
				if _has_adjacent_corridor(Vector2i(x, y), map):
					return false

	return true


func _has_stairs(cell: MapCell) -> bool:
	return (
		cell.obstacle
		and (
			cell.obstacle.type == Obstacle.Type.STAIRS_UP
			or cell.obstacle.type == Obstacle.Type.STAIRS_DOWN
		)
	)


func _place_obstacle(map: Map, pos: Vector2i, config: ObstacleConfig) -> void:
	# Handle multi-cell obstacles
	if config.is_multi_cell():
		_place_multi_cell_obstacle(map, pos, config)
		return

	# Place single-cell obstacle
	var obstacle := Obstacle.new()
	obstacle.type = config.type
	map.cells[pos.x][pos.y].obstacle = obstacle


func _place_amulet(map: Map, room: Room) -> void:
	var amulet := ItemFactory.create_item(&"amulet_of_yendor")
	var attempts := 100

	while attempts > 0:
		var x := _rng.randi_range(room.x, room.x + room.width - 1)
		var y := _rng.randi_range(room.y, room.y + room.height - 1)
		var cell: MapCell = map.cells[x][y]

		if _is_valid_empty_floor(cell):
			cell.items.append(amulet)
			break
		attempts -= 1


func _is_valid_empty_floor(cell: MapCell) -> bool:
	return (
		cell.terrain.type == TerrainType.DUNGEON_FLOOR
		and cell.items.is_empty()
		and not cell.monster
		and not cell.obstacle
	)


func _has_adjacent_corridor(pos: Vector2i, map: Map) -> bool:
	# Check all 8 adjacent tiles for corridors
	for dx: int in [-1, 0, 1]:
		for dy: int in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue

			var check_x := pos.x + dx
			var check_y := pos.y + dy

			# Skip if out of bounds
			if check_x < 0 or check_x >= map.width or check_y < 0 or check_y >= map.height:
				continue

			# Check if adjacent tile is a corridor
			var cell: MapCell = map.cells[check_x][check_y]
			if cell.area_type == MapCell.Type.CORRIDOR:
				return true

	return false


func _initialize_empty_map(width: int, height: int, depth: int) -> Map:
	Log.d("Initializing empty map: %dx%d at depth %d" % [width, height, depth])
	var map := Map.new(width, height, depth)

	# Initialize terrain with empty space
	for x in range(width):
		for y in range(height):
			var tile := Terrain.new()
			tile.type = TerrainType.EMPTY
			map.cells[x][y].terrain = tile

	return map


func _place_wall_light(map: Map, cell: MapCell, x: int, y: int) -> void:
	# Check for walls above/below for light placement
	if y > 0 and map.get_terrain(Vector2i(x, y - 1)).type == TerrainType.DUNGEON_WALL:
		cell.decoration_type = DecType.NORTH_LIGHT
	elif (
		y < map.height - 1 and map.get_terrain(Vector2i(x, y + 1)).type == TerrainType.DUNGEON_WALL
	):
		cell.decoration_type = DecType.SOUTH_LIGHT


func _place_single_monster(map: Map, monster_id: StringName) -> void:
	var monster := MonsterFactory.create_monster(monster_id)

	var tries := 0
	while tries < 10:
		var x := _rng.randi_range(0, map.width - 1)
		var y := _rng.randi_range(0, map.height - 1)
		var cell: MapCell = map.cells[x][y]

		if _is_valid_empty_floor(cell):
			cell.monster = monster
			return
		tries += 1
	Log.w("Failed to place monster")


func _place_single_item(map: Map, item_id: StringName) -> void:
	var item := ItemFactory.create_item(item_id)

	var tries := 0
	while tries < 10:
		var x := _rng.randi_range(0, map.width - 1)
		var y := _rng.randi_range(0, map.height - 1)
		var cell: MapCell = map.cells[x][y]

		if _is_valid_empty_floor(cell):
			cell.items.append(item)
			return
		tries += 1
	Log.w("Failed to place item")


func has_adjacent_wall(x: int, y: int, map: Map) -> bool:
	var pos := Vector2i(x, y)
	# Check cardinal directions for walls
	for offset: Vector2i in Utils.CARDINAL_DIRECTIONS:
		var check_pos := pos + offset
		if (
			check_pos.x >= 0
			and check_pos.x < map.width
			and check_pos.y >= 0
			and check_pos.y < map.height
			and map.get_terrain(check_pos).type == TerrainType.DUNGEON_WALL
		):
			return true
	return false


func is_corner_wall(x: int, y: int, map: Map) -> bool:
	# Check for walls in cardinal directions
	var n := y > 0 and map.get_terrain(Vector2i(x, y - 1)).type == TerrainType.DUNGEON_WALL
	var s := (
		y < map.height - 1 and map.get_terrain(Vector2i(x, y + 1)).type == TerrainType.DUNGEON_WALL
	)
	var e := (
		x < map.width - 1 and map.get_terrain(Vector2i(x + 1, y)).type == TerrainType.DUNGEON_WALL
	)
	var w := x > 0 and map.get_terrain(Vector2i(x - 1, y)).type == TerrainType.DUNGEON_WALL

	# A corner wall should have exactly two adjacent walls at right angles
	return (n and e) or (n and w) or (s and e) or (s and w)


func is_vertical_wall(x: int, y: int, map: Map) -> bool:
	# Check for walls in cardinal directions
	var n := y > 0 and map.get_terrain(Vector2i(x, y - 1)).type == TerrainType.DUNGEON_WALL
	var s := (
		y < map.height - 1 and map.get_terrain(Vector2i(x, y + 1)).type == TerrainType.DUNGEON_WALL
	)
	var e := (
		x < map.width - 1 and map.get_terrain(Vector2i(x + 1, y)).type == TerrainType.DUNGEON_WALL
	)
	var w := x > 0 and map.get_terrain(Vector2i(x - 1, y)).type == TerrainType.DUNGEON_WALL

	# Vertical wall has walls to north and south but not east or west
	return n and s and !e and !w


func is_horizontal_wall(x: int, y: int, map: Map) -> bool:
	# Check for walls in cardinal directions
	var n := y > 0 and map.get_terrain(Vector2i(x, y - 1)).type == TerrainType.DUNGEON_WALL
	var s := (
		y < map.height - 1 and map.get_terrain(Vector2i(x, y + 1)).type == TerrainType.DUNGEON_WALL
	)
	var e := (
		x < map.width - 1 and map.get_terrain(Vector2i(x + 1, y)).type == TerrainType.DUNGEON_WALL
	)
	var w := x > 0 and map.get_terrain(Vector2i(x - 1, y)).type == TerrainType.DUNGEON_WALL

	# Horizontal wall has walls to east and west but not north or south
	return e and w and !n and !s


func _place_multi_cell_obstacle(map: Map, start_pos: Vector2i, config: ObstacleConfig) -> void:
	var positions: Array[Vector2i] = []

	# For vertical obstacles, we place from bottom to top
	if config.is_vertical:
		for y in range(config.height):
			positions.append(Vector2i(start_pos.x, start_pos.y + y))
	else:
		# For horizontal obstacles, left to right
		for x in range(config.width):
			positions.append(Vector2i(start_pos.x + x, start_pos.y))

	# Create obstacles for each cell in the footprint
	for i in range(positions.size()):
		var pos := positions[i]
		var obstacle := Obstacle.new()
		obstacle.type = config.type
		obstacle.parent_pos = start_pos

		# Set direction based on position and orientation
		if config.is_vertical:
			if i == 0:  # Bottom piece
				obstacle.direction = Obstacle.Direction.NORTH
			else:  # Top piece
				obstacle.direction = Obstacle.Direction.SOUTH
		else:
			if i == 0:  # Leftmost piece
				obstacle.direction = Obstacle.Direction.EAST
			elif i == positions.size() - 1:  # Rightmost piece
				obstacle.direction = Obstacle.Direction.WEST
			else:  # Middle pieces
				obstacle.direction = Obstacle.Direction.BOTH

		map.cells[pos.x][pos.y].obstacle = obstacle


func _place_books(map: Map, room: Room) -> void:
	Log.d("Placing books in room %s" % room)

	# Define the items we want to place
	var items := [&"godot_user_guide", &"gdscript_reference", &"orange_scroll", &"green_scroll"]

	# Calculate how many items to place based on room size
	var room_area := room.width * room.height
	var num_items := mini(_rng.randi_range(3, 6), int(room_area / 10.0))

	# Place items
	for _i in range(num_items):
		var tries := 0
		while tries < 10:
			var x := _rng.randi_range(room.x, room.x + room.width - 1)
			var y := _rng.randi_range(room.y, room.y + room.height - 1)
			var cell: MapCell = map.cells[x][y]

			if _is_valid_empty_floor(cell):
				var item_id: StringName = items[_rng.randi() % items.size()]
				var item := ItemFactory.create_item(item_id)

				# If stackable, set random quantity between 1-3
				if item.max_stack_size > 1:
					item.quantity = Dice.roll(1, 3)

				map.add_item_with_stacking(Vector2i(x, y), item)
				break
			tries += 1
