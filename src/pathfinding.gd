class_name Pathfinding
extends RefCounted

const MAX_PATHFINDING_STEPS := 15


## Returns the next step direction from start to target, or Vector2i.ZERO if no path found
static func get_next_step(
	map: Map, start: Vector2i, target: Vector2i, avoid_monsters: bool = false
) -> Vector2i:
	# If target is too far, don't bother pathfinding
	var direct_distance: int = abs(start.x - target.x) + abs(start.y - target.y)
	if direct_distance > MAX_PATHFINDING_STEPS:
		return Vector2i.ZERO

	# Queue format: {pos: Vector2i, path: Array[Vector2i]}
	var queue: Array[Dictionary] = []
	var visited: Dictionary = {}

	# Add starting position
	queue.push_back({"pos": start, "path": []})
	visited[start] = true

	while not queue.is_empty():
		var current: Dictionary = queue.pop_front()
		var current_pos: Vector2i = current.pos
		var current_path: Array = current.path

		# If we've gone too many steps, stop searching
		if current_path.size() >= MAX_PATHFINDING_STEPS:
			continue

		for dir in Utils.ALL_DIRECTIONS:
			var next_pos := current_pos + dir

			# Skip if already visited or invalid
			if next_pos in visited:
				continue
			if not map.is_in_bounds(next_pos):
				continue
			if not map.get_cell(next_pos).is_walkable():
				continue

			# Skip if there's a monster and we're avoiding them, UNLESS it's our target position
			if avoid_monsters and next_pos != target and map.get_monster(next_pos) != null:
				continue

			# Mark as visited
			visited[next_pos] = true

			# If this is our target, return the first step of the path
			if next_pos == target:
				if current_path.is_empty():
					return next_pos - start
				return current_path[0] - start

			# Add next position to queue with updated path
			var next_path := current_path.duplicate()
			if next_path.is_empty():
				next_path.append(next_pos)
			queue.push_back({"pos": next_pos, "path": next_path})

	return Vector2i.ZERO


## Returns a safe move direction that tries to align with the preferred direction
static func get_safe_move_direction(map: Map, start: Vector2i, preferred_dir: Vector2i) -> Vector2i:
	var possible_moves: Array[Dictionary] = []
	for dx: int in [-1, 0, 1]:
		for dy: int in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue

			var new_pos := start + Vector2i(dx, dy)
			if not map.is_in_bounds(new_pos):
				continue

			if not map.get_cell(new_pos).is_walkable():
				continue

			var dir := Vector2i(dx, dy)
			var dot_product := dir.x * preferred_dir.x + dir.y * preferred_dir.y
			possible_moves.append({"dir": dir, "score": dot_product})

	if possible_moves.is_empty():
		return Vector2i.ZERO

	# Sort by score (highest dot product = most aligned with preferred direction)
	possible_moves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
	return possible_moves[0].dir


## Returns the full path from start to target, limited by max_steps
static func find_path(
	map: Map, start: Vector2i, target: Vector2i, max_steps: int = MAX_PATHFINDING_STEPS
) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var visited: Dictionary = {}
	var queue: Array[Dictionary] = []

	# Add starting position
	queue.push_back({"pos": start, "path": path})
	visited[start] = true

	while not queue.is_empty():
		var current: Dictionary = queue.pop_front()
		var current_pos: Vector2i = current.pos
		var current_path: Array[Vector2i] = current.path

		# If we've gone too many steps, stop searching
		if current_path.size() >= max_steps:
			continue

		for dir in Utils.ALL_DIRECTIONS:
			var next_pos := current_pos + dir

			# Skip if already visited or invalid
			if next_pos in visited:
				continue
			if not map.is_in_bounds(next_pos):
				continue
			# Allow non-walkable cells if they're the target (for doors/walls)
			if not map.get_cell(next_pos).is_walkable() and next_pos != target:
				continue

			# Mark as visited
			visited[next_pos] = true

			# Create new path including this position
			var new_path := current_path.duplicate()
			new_path.append(next_pos)

			# If this is our target, return the path
			if next_pos == target:
				return new_path

			# Add to queue
			queue.push_back({"pos": next_pos, "path": new_path})

	return []
