class_name BaseMapGenerator
extends RefCounted


class Split:
	var x: int
	var y: int
	var width: int
	var height: int
	var is_horizontal: bool

	func _init(p_x: int, p_y: int, p_w: int, p_h: int, p_horizontal: bool) -> void:
		x = p_x
		y = p_y
		width = p_w
		height = p_h
		is_horizontal = p_horizontal


# Add this as a class variable
var debug_splits: Array[Split] = []


# Abstract base class for map generators
func generate_map(_width: int, _height: int, _params: Dictionary = {}) -> Map:
	Log.e("BaseMapGenerator.generate_map() must be overridden")
	return null


# Common utility functions all generators might need
func _initialize_empty_map(width: int, height: int, depth: int) -> Map:
	return Map.new(width, height, depth)


func _add_outer_walls(map: Map) -> void:
	for x in range(map.width):
		for y in range(map.height):
			if x == 0 or x == map.width - 1 or y == 0 or y == map.height - 1:
				var tile := Terrain.new()
				tile.type = Terrain.Type.DUNGEON_WALL
				map.cells[x][y].terrain = tile


# BSP room generation
func _generate_bsp_rooms(
	start_x: int,
	start_y: int,
	w: int,
	h: int,
	depth: int,
	min_room_size: int = 3,
	min_split_size: int = 8,
	horizontal_split_chance: float = 0.5
) -> Array[Room]:
	var rooms: Array[Room] = []

	# Prevent processing if the space is too small
	if w < min_split_size or h < min_split_size:
		return rooms

	# Add the current split to debug_splits regardless of whether it's a leaf or not
	debug_splits.append(Split.new(start_x, start_y, w, h, false))

	if depth <= 0:
		# Calculate maximum room size leaving 1 cell padding on each side
		var max_room_w := w - 4  # -4 for 2 cell padding on each side
		var max_room_h := h - 4  # -4 for 2 cell padding on each side

		# Ensure room size is between min_room_size and max available space
		var room_w: int = min(max_room_w, max(min_room_size, randi() % max_room_w))
		var room_h: int = min(max_room_h, max(min_room_size, randi() % max_room_h))

		# Calculate room position ensuring 1 cell padding from split boundaries
		var room_x := start_x + 2 + randi() % (w - room_w - 2)
		var room_y := start_y + 2 + randi() % (h - room_h - 2)

		rooms.append(Room.new(room_x, room_y, room_w, room_h))
		return rooms

	# Split either horizontally or vertically based on horizontal_split_chance
	if randf() < horizontal_split_chance and h > min_split_size:  # horizontal split
		var split := start_y + int(h / 2.0)
		debug_splits[-1].is_horizontal = true  # Update the last added split's orientation
		rooms.append_array(
			_generate_bsp_rooms(
				start_x,
				start_y,
				w,
				split - start_y,
				depth - 1,
				min_room_size,
				min_split_size,
				horizontal_split_chance
			)
		)
		rooms.append_array(
			_generate_bsp_rooms(
				start_x,
				split,
				w,
				h - (split - start_y),
				depth - 1,
				min_room_size,
				min_split_size,
				horizontal_split_chance
			)
		)
	elif w > min_split_size:  # vertical split
		var split := start_x + int(w / 2.0)
		# No need to update is_horizontal as it defaults to false
		rooms.append_array(
			_generate_bsp_rooms(
				start_x,
				start_y,
				split - start_x,
				h,
				depth - 1,
				min_room_size,
				min_split_size,
				horizontal_split_chance
			)
		)
		rooms.append_array(
			_generate_bsp_rooms(
				split,
				start_y,
				w - (split - start_x),
				h,
				depth - 1,
				min_room_size,
				min_split_size,
				horizontal_split_chance
			)
		)
	else:
		# If we can't split anymore, create a room with padding
		var room_w: int = min(w - 2, max(min_room_size, w - 2))  # -2 for padding
		var room_h: int = min(h - 2, max(min_room_size, h - 2))  # -2 for padding
		rooms.append(Room.new(start_x + 1, start_y + 1, room_w, room_h))

	return rooms


# Dungeon algorithm based on the "Brogue-like" approach
# This creates more organic, packed-together rooms of different sizes
func _generate_dungeon_rooms(width: int, height: int, params: Dictionary = {}) -> Array[Room]:
	var rooms: Array[Room] = []
	var rng := RandomNumberGenerator.new()

	# Parameters with defaults
	var min_room_size: int = params.get("min_room_size", 5)
	var max_room_size: int = params.get("max_room_size", 15)
	var size_variation: float = params.get("size_variation", 0.7)
	var room_placement_attempts: int = params.get("room_placement_attempts", 500)
	var target_room_count: int = params.get("target_room_count", 20)
	var room_expansion_chance: float = params.get("room_expansion_chance", 0.5)
	var max_expansion_attempts: int = params.get("max_expansion_attempts", 3)
	var horizontal_expansion_bias: float = params.get("horizontal_expansion_bias", 0.5)
	var border_buffer: int = params.get("border_buffer", 2)

	# Grid to track occupied cells
	var grid: Array[Array] = []
	for x in range(width):
		var row: Array[bool] = []
		for y in range(height):
			row.append(false)  # false means cell is free
		grid.append(row)

	# Border buffer to keep rooms away from map edges
	var border: int = border_buffer

	# Step 1: Place initial rooms
	var attempts: int = 0
	while attempts < room_placement_attempts and rooms.size() < target_room_count:
		attempts += 1

		# Generate random room size with size variation
		var size_range: int = max_room_size - min_room_size
		var variation: float = size_variation * rng.randf()
		var room_w: int = min_room_size + int(size_range * variation)
		var room_h: int = min_room_size + int(size_range * variation)

		# Ensure room fits within map boundaries
		room_w = min(room_w, width - 2 * border)
		room_h = min(room_h, height - 2 * border)

		# Generate random position (with border buffer)
		var room_x: int = rng.randi_range(border, width - room_w - border)
		var room_y: int = rng.randi_range(border, height - room_h - border)

		# Check if room overlaps with existing rooms (including 1-cell buffer)
		var can_place: bool = true
		for x in range(room_x - 1, room_x + room_w + 1):
			for y in range(room_y - 1, room_y + room_h + 1):
				if x < 0 or x >= width or y < 0 or y >= height or grid[x][y]:
					can_place = false
					break
			if not can_place:
				break

		if can_place:
			# Mark cells as occupied
			for x in range(room_x, room_x + room_w):
				for y in range(room_y, room_y + room_h):
					grid[x][y] = true

			# Add room
			rooms.append(Room.new(room_x, room_y, room_w, room_h))

			# Add to debug splits for visualization
			debug_splits.append(Split.new(room_x, room_y, room_w, room_h, false))

			# Reset attempts counter to give more chances after successful placement
			attempts = max(0, attempts - 5)

	# Step 2: Try to expand rooms
	if room_expansion_chance > 0:
		for room in rooms:
			# Try to expand in each direction
			var directions: Array[Vector2i] = [
				Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)  # right  # left  # down  # up
			]

			# Shuffle directions for more organic results
			directions.shuffle()

			# Apply horizontal expansion bias
			if horizontal_expansion_bias != 0.5:
				# Sort directions to prioritize horizontal or vertical expansion
				directions.sort_custom(
					func(a: Vector2i, b: Vector2i) -> bool:
						var a_is_horizontal: bool = abs(a.x) > 0
						var b_is_horizontal: bool = abs(b.x) > 0
						if a_is_horizontal and not b_is_horizontal:
							return horizontal_expansion_bias > 0.5
						elif not a_is_horizontal and b_is_horizontal:
							return horizontal_expansion_bias < 0.5
						return false
				)

			# Track expansion attempts per room
			var expansion_attempts: int = 0

			for dir in directions:
				# Skip expansion with random chance
				if rng.randf() > room_expansion_chance:
					continue

				# Limit expansion attempts per room
				if expansion_attempts >= max_expansion_attempts:
					break

				expansion_attempts += 1

				var can_expand: bool = true
				var new_x: int = room.x
				var new_y: int = room.y
				var new_w: int = room.width
				var new_h: int = room.height

				# Calculate new room bounds based on expansion direction
				if dir.x > 0:  # expand right
					new_w += 1
				elif dir.x < 0:  # expand left
					new_x -= 1
					new_w += 1
				elif dir.y > 0:  # expand down
					new_h += 1
				elif dir.y < 0:  # expand up
					new_y -= 1
					new_h += 1

				# Check if expansion is valid
				# We need to check the new cells plus a 1-cell buffer around them
				var check_x_start: int = new_x - 1
				var check_y_start: int = new_y - 1
				var check_x_end: int = new_x + new_w
				var check_y_end: int = new_y + new_h

				for x in range(check_x_start, check_x_end + 1):
					for y in range(check_y_start, check_y_end + 1):
						# Skip checking the original room cells
						if (
							x >= room.x
							and x < room.x + room.width
							and y >= room.y
							and y < room.y + room.height
						):
							continue

						# Check if cell is out of bounds or already occupied
						if x < 0 or x >= width or y < 0 or y >= height or grid[x][y]:
							can_expand = false
							break
					if not can_expand:
						break

				# If expansion is valid, update room and grid
				if can_expand:
					# Mark new cells as occupied
					for x in range(new_x, new_x + new_w):
						for y in range(new_y, new_y + new_h):
							if (
								x < room.x
								or x >= room.x + room.width
								or y < room.y
								or y >= room.y + room.height
							):
								grid[x][y] = true

					# Update room dimensions
					room.x = new_x
					room.y = new_y
					room.width = new_w
					room.height = new_h

					# Update debug split for this room
					for i in range(debug_splits.size()):
						if debug_splits[i].x == room.x and debug_splits[i].y == room.y:
							debug_splits[i] = Split.new(new_x, new_y, new_w, new_h, false)
							break

	return rooms


func _connect_rooms(map: Map, room1: Room, room2: Room) -> void:
	# Find centers of rooms
	var start_x: int = room1.x + int(room1.width / 2.0)
	var start_y: int = room1.y + int(room1.height / 2.0)
	var end_x: int = room2.x + int(room2.width / 2.0)
	var end_y: int = room2.y + int(room2.height / 2.0)

	# Create L-shaped corridor with walls
	# First handle the horizontal part
	var x_start: int = min(start_x, end_x)
	var x_end: int = max(start_x, end_x)
	for x in range(x_start - 1, x_end + 2):
		# Add walls above and below
		for y_offset: int in [-1, 1]:
			var wall := Terrain.new()
			wall.type = Terrain.Type.DUNGEON_WALL
			if (
				not map.cells[x][start_y + y_offset].terrain
				or map.cells[x][start_y + y_offset].terrain.type != Terrain.Type.DUNGEON_FLOOR
			):
				map.cells[x][start_y + y_offset].terrain = wall
				map.cells[x][start_y + y_offset].area_type = MapCell.Type.CORRIDOR

		# Add floor (but only in the actual corridor)
		if x > x_start - 1 and x < x_end + 1:
			var tile := Terrain.new()
			tile.type = Terrain.Type.DUNGEON_FLOOR
			map.cells[x][start_y].terrain = tile
			map.cells[x][start_y].area_type = MapCell.Type.CORRIDOR

	# Then handle the vertical part
	var y_start: int = min(start_y, end_y)
	var y_end: int = max(start_y, end_y)
	for y in range(y_start - 1, y_end + 2):
		# Add walls to the left and right
		for x_offset: int in [-1, 1]:
			var wall := Terrain.new()
			wall.type = Terrain.Type.DUNGEON_WALL
			if (
				not map.cells[end_x + x_offset][y].terrain
				or map.cells[end_x + x_offset][y].terrain.type != Terrain.Type.DUNGEON_FLOOR
			):
				map.cells[end_x + x_offset][y].terrain = wall
				map.cells[end_x + x_offset][y].area_type = MapCell.Type.CORRIDOR

		# Add floor (but only in the actual corridor)
		if y > y_start - 1 and y < y_end + 1:
			var tile := Terrain.new()
			tile.type = Terrain.Type.DUNGEON_FLOOR
			map.cells[end_x][y].terrain = tile
			map.cells[end_x][y].area_type = MapCell.Type.CORRIDOR

	# Add diagonal walls at the turn
	var corners := [
		Vector2i(end_x - 1, start_y - 1),
		Vector2i(end_x + 1, start_y - 1),
		Vector2i(end_x - 1, start_y + 1),
		Vector2i(end_x + 1, start_y + 1)
	]

	for corner: Vector2i in corners:
		if (
			not map.cells[corner.x][corner.y].terrain
			or map.cells[corner.x][corner.y].terrain.type != Terrain.Type.DUNGEON_FLOOR
		):
			var wall := Terrain.new()
			wall.type = Terrain.Type.DUNGEON_WALL
			map.cells[corner.x][corner.y].terrain = wall
			map.cells[corner.x][corner.y].area_type = MapCell.Type.CORRIDOR
