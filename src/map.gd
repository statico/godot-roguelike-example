class_name Map
extends RefCounted

var id := ""
var depth := 1
var width := 20
var height := 20

var cells: Array[Array] = []  # Array[Array[MapCell]]
var visible_cells: Array[Array] = []  # Array of currently visible cells
var seen_cells: Array[Array] = []  # Array of cells that have been seen before
var rooms: Array[Room] = []
var next_room_id: int = 0


func _init(p_width: int, p_height: int, p_depth: int = 1, p_id: String = "") -> void:
	width = p_width
	height = p_height
	depth = p_depth

	# If no ID provided, generate one based on depth
	id = p_id if p_id else "level_%d" % depth
	# Initialize cells array
	cells = []
	visible_cells = []
	seen_cells = []
	for x in range(width):
		cells.append([])
		visible_cells.append([])
		seen_cells.append([])
		for y in range(height):
			cells[x].append(MapCell.new())
			visible_cells[x].append(false)
			seen_cells[x].append(false)


func _to_string() -> String:
	return "Map(id: %s, depth: %d, width: %d, height: %d)" % [id, depth, width, height]


## Gets the cell at the specified position
func get_cell(pos: Vector2i) -> MapCell:
	return cells[pos.x][pos.y]


## Gets the terrain at the specified position
func get_terrain(pos: Vector2i) -> Terrain:
	return cells[pos.x][pos.y].terrain


## Gets the obstacle at the specified position
func get_obstacle(pos: Vector2i) -> Obstacle:
	return cells[pos.x][pos.y].obstacle


## Gets the items at the specified position
func get_items(pos: Vector2i) -> Array[Item]:
	if not is_in_bounds(pos):
		return []
	return cells[pos.x][pos.y].items


## Gets the top item at the specified position
func get_top_item(pos: Vector2i) -> Item:
	if not is_in_bounds(pos):
		return null
	var items: Array[Item] = cells[pos.x][pos.y].items
	return items[items.size() - 1] if items.size() > 0 else null


## Gets the monster at the specified position
func get_monster(pos: Vector2i) -> Monster:
	return cells[pos.x][pos.y].monster


## Gets all monsters on the map
func get_monsters() -> Array[Monster]:
	var monsters: Array[Monster] = []
	for x in range(width):
		for y in range(height):
			var cell: MapCell = cells[x][y]
			var monster := cell.monster
			if monster:
				monsters.append(monster)
	return monsters


## Adds a monster at the stairs of the specified type
func add_monster_at_stairs(monster: Monster, stairs_type: Obstacle.Type) -> bool:
	Log.i("Attempting to add monster at stairs type: %s" % stairs_type)

	if cells.is_empty():
		Log.e("Map cells array is empty")
		return false

	for x in range(width):
		for y in range(height):
			var cell: MapCell = cells[x][y]
			if cell.obstacle and cell.obstacle.type == stairs_type:
				Log.i("Found matching stairs at position (%d, %d)" % [x, y])

				if not cell.is_walkable():
					Log.e("MapCell at stairs is not walkable")
					return false

				if cell.monster:
					Log.e("Monster already exists at stairs position")
					return false

				cell.monster = monster
				Log.d("Successfully placed monster at stairs (%d, %d)" % [x, y])
				return true

	Log.e("Could not find valid stairs position")
	return false


## Finds and removes a monster from the map
func find_and_remove_monster(monster: Monster) -> bool:
	for x in range(width):
		for y in range(height):
			if cells[x][y].monster == monster:
				cells[x][y].monster = null
				return true
	return false


## Finds the position of a monster on the map
func find_monster_position(monster: Monster) -> Vector2i:
	for x in range(width):
		for y in range(height):
			if cells[x][y].monster == monster:
				return Vector2i(x, y)
	return Utils.INVALID_POS


## Checks if a position is stairs
func is_stairs(pos: Vector2i) -> bool:
	var obstacle := get_obstacle(pos)
	return (
		obstacle
		and (obstacle.type == Obstacle.Type.STAIRS_UP or obstacle.type == Obstacle.Type.STAIRS_DOWN)
	)


## Gets the type of stairs at the specified position
func get_stairs_type(pos: Vector2i) -> Obstacle.Type:
	var obstacle := get_obstacle(pos)
	if (
		obstacle
		and (obstacle.type == Obstacle.Type.STAIRS_UP or obstacle.type == Obstacle.Type.STAIRS_DOWN)
	):
		return obstacle.type
	return Obstacle.Type.NONE


## Checks if a position is visible
func is_visible(pos: Vector2i) -> bool:
	return visible_cells[pos.x][pos.y]


## Checks if a position has been seen
func was_seen(pos: Vector2i) -> bool:
	return seen_cells[pos.x][pos.y]


## Prints the debug terrain
func print_debug_terrain() -> void:
	Log.i("Terrain:")
	var output := ""
	for y in range(height):
		for x in range(width):
			output += (
				get_obstacle(Vector2i(x, y)).get_char()
				if get_obstacle(Vector2i(x, y))
				else get_terrain(Vector2i(x, y)).get_char()
			)
		output += "\n"
	Log.i(output)


## Prints the debug area types
func print_debug_area_types() -> void:
	Log.i("Area types:")
	var output := ""
	for y in range(height):
		for x in range(width):
			output += str(cells[x][y].area_type)
		output += "\n"
	Log.i(output)


## Prints the debug visible cells
func print_visible_cells() -> void:
	Log.i("Visible cells:")
	var output := ""
	for y in range(height):
		for x in range(width):
			if visible_cells[x][y]:
				output += "■"
			else:
				output += (
					get_obstacle(Vector2i(x, y)).get_char()
					if get_obstacle(Vector2i(x, y))
					else get_terrain(Vector2i(x, y)).get_char()
				)
		output += "\n"
	Log.i(output)


## Prints the debug seen cells
func print_seen_cells() -> void:
	Log.i("Seen cells:")
	var output := ""
	for y in range(height):
		for x in range(width):
			output += "X" if seen_cells[x][y] else "."
		output += "\n"
	Log.i(output)


## Checks if a position is opaque
func is_opaque(pos: Vector2i) -> bool:
	var terrain := get_terrain(pos)
	var obstacle := get_obstacle(pos)

	# Check for opaque terrain (walls)
	if terrain and terrain.type == Terrain.Type.DUNGEON_WALL:
		return true

	# Check for closed doors
	if obstacle and obstacle.type == Obstacle.Type.DOOR_CLOSED:
		return true

	return false


## Checks if a position is a wall
func is_wall(pos: Vector2i) -> bool:
	return is_opaque(pos)


func clear_fov(origin: Vector2i) -> void:
	for y in range(height):
		for x in range(width):
			visible_cells[x][y] = false

	# Mark origin as visible
	visible_cells[origin.x][origin.y] = true
	seen_cells[origin.x][origin.y] = true


# Adam Miazzola's implementation of FOV - https://www.adammil.net/blog/v125_Roguelike_Vision_Algorithms.html
func compute_fov(origin: Vector2i) -> void:
	# Clear previous visibility
	clear_fov(origin)

	# Process all 4 quadrants
	for quadrant in range(4):
		_fov_scan_quadrant(quadrant, origin)


func _fov_scan_quadrant(quadrant: int, origin: Vector2i) -> void:
	var first_row := Row.new(1, -1.0, 1.0)
	_fov_scan_recursive(quadrant, origin, first_row)


func _fov_scan_recursive(quadrant: int, origin: Vector2i, row: Row) -> void:
	var prev_tile: Vector2i = Utils.INVALID_POS

	for tile: Vector2i in row.get_tiles():
		var world_pos := transform_tile(quadrant, origin, tile)

		# Skip if out of bounds
		if not is_in_bounds(world_pos):
			continue

		if is_wall(world_pos) or is_symmetric(row, tile):
			mark_visible(world_pos)

		if prev_tile != Utils.INVALID_POS:
			# Floor to wall transition
			if not is_wall(transform_tile(quadrant, origin, prev_tile)) and is_wall(world_pos):
				var next_row := row.next()
				next_row.end_slope = get_slope(tile)
				_fov_scan_recursive(quadrant, origin, next_row)

			# Wall to floor transition
			elif is_wall(transform_tile(quadrant, origin, prev_tile)) and not is_wall(world_pos):
				row.start_slope = get_slope(tile)

		prev_tile = tile

	# If we hit the end with a floor tile, continue to next row
	if prev_tile != Utils.INVALID_POS and not is_wall(transform_tile(quadrant, origin, prev_tile)):
		_fov_scan_recursive(quadrant, origin, row.next())


class Row:
	extends RefCounted

	var depth: int
	var start_slope: float
	var end_slope: float

	func _init(p_depth: int, p_start: float, p_end: float) -> void:
		depth = p_depth
		start_slope = p_start
		end_slope = p_end

	func next() -> Row:
		return Row.new(depth + 1, start_slope, end_slope)

	func get_tiles() -> Array:
		var tiles := []
		var min_col := round_ties_up(depth * start_slope)
		var max_col := round_ties_down(depth * end_slope)
		for col in range(min_col, max_col + 1):
			tiles.append(Vector2i(depth, col))
		return tiles

	func round_ties_up(n: float) -> int:
		return floori(n + 0.5)

	func round_ties_down(n: float) -> int:
		return ceili(n - 0.5)


## Transforms a tile to the correct position based on the quadrant
func transform_tile(quadrant: int, origin: Vector2i, tile: Vector2i) -> Vector2i:
	var row := tile.x
	var col := tile.y
	match quadrant:
		0:  # North
			return Vector2i(origin.x + col, origin.y - row)
		1:  # South
			return Vector2i(origin.x + col, origin.y + row)
		2:  # East
			return Vector2i(origin.x + row, origin.y + col)
		3:  # West
			return Vector2i(origin.x - row, origin.y + col)
	return Vector2i.ZERO


## Checks if a position is within the bounds of the map
func is_in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < width and pos.y >= 0 and pos.y < height


## Marks a position as visible
func mark_visible(pos: Vector2i) -> void:
	visible_cells[pos.x][pos.y] = true
	seen_cells[pos.x][pos.y] = true


## Gets the slope of a tile
func get_slope(tile: Vector2i) -> float:
	return float(2 * tile.y - 1) / float(2 * tile.x)


## Checks if a tile is symmetric
func is_symmetric(row: Row, tile: Vector2i) -> bool:
	var col := float(tile.y)
	return col >= row.depth * row.start_slope and col <= row.depth * row.end_slope


## Removes an item from the map at the specified position
func remove_item(pos: Vector2i, item: Item) -> bool:
	if not is_in_bounds(pos):
		return false
	var cell: MapCell = cells[pos.x][pos.y]
	var index := cell.items.find(item)
	if index != -1:
		cell.items.remove_at(index)
		return true
	return false


## Adds an item to the map at the specified position
func add_item(pos: Vector2i, item: Item) -> bool:
	if not is_in_bounds(pos):
		return false
	var cell: MapCell = cells[pos.x][pos.y]
	cell.items.append(item)
	return true


## Adds an item to the map at the specified position, handling stacking if possible
## Returns the final item that was added or stacked with
func add_item_with_stacking(pos: Vector2i, item: Item) -> Item:
	if not is_in_bounds(pos):
		return null

	# Check for matching items at the location if stackable
	if item.max_stack_size > 1:
		var cell_items: Array[Item] = get_items(pos)
		for existing_item in cell_items:
			if existing_item.matches(item):
				# Stack with existing item
				existing_item.quantity += item.quantity
				return existing_item

	# No match found or item not stackable, add as new item
	if add_item(pos, item):
		return item

	return null


## Adds a designated room area to the map
func add_room(type: Room.Type, x: int, y: int, p_width: int, p_height: int) -> Room:
	var room := Room.new(x, y, p_width, p_height, type, next_room_id)
	rooms.append(room)
	next_room_id += 1
	return room


## Pushes an obstacle in the specified direction
func push_obstacle(from_pos: Vector2i, direction: Vector2i) -> bool:
	# Get the obstacle at the starting position
	var obstacle := get_obstacle(from_pos)
	if not obstacle or not obstacle.is_pushable():
		return false

	# Calculate target position
	var to_pos := from_pos + direction

	# Check if target position is valid and walkable
	if not is_in_bounds(to_pos):
		return false

	var target_cell: MapCell = cells[to_pos.x][to_pos.y]
	# Add check for existing obstacle in target cell
	if not target_cell.is_walkable() or target_cell.monster or target_cell.obstacle:
		return false

	# Move the obstacle
	cells[to_pos.x][to_pos.y].obstacle = obstacle
	cells[from_pos.x][from_pos.y].obstacle = null

	return true


## Checks if the map has stairs up anywhere
func has_stairs_up() -> bool:
	for x in range(width):
		for y in range(height):
			var obstacle: Variant = cells[x][y].obstacle
			if obstacle is Obstacle and obstacle.type == Obstacle.Type.STAIRS_UP:
				return true
	return false


## Checks if the map has stairs down anywhere
func has_stairs_down() -> bool:
	for x in range(width):
		for y in range(height):
			var obstacle: Variant = cells[x][y].obstacle
			if obstacle is Obstacle and obstacle.type == Obstacle.Type.STAIRS_DOWN:
				return true
	return false


## Gets all visible monsters on the map
func get_visible_monsters() -> Array[Monster]:
	var visible_monsters: Array[Monster] = []
	for x in range(width):
		for y in range(height):
			var pos := Vector2i(x, y)
			var monster := get_monster(pos)
			if monster and is_visible(pos):
				visible_monsters.append(monster)
	return visible_monsters


## Applies a new area effect centered at the given position
func apply_aoe(
	center: Vector2i, radius: int, type: Damage.Type, damage: Array[int], turns: int
) -> void:
	# Get all cells within radius (using Manhattan distance for simplicity)
	for x in range(max(0, center.x - radius), min(width, center.x + radius + 1)):
		for y in range(max(0, center.y - radius), min(height, center.y + radius + 1)):
			var pos := Vector2i(x, y)
			if pos.distance_to(center) <= radius:
				var cell := get_cell(pos)
				cell.area_effects.append(MapCell.AreaEffect.new(type, damage, turns))
