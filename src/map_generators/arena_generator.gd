class_name ArenaGenerator
extends BaseMapGenerator


func generate_map(width: int, height: int, _params: Dictionary = {}) -> Map:
	Log.i("Generating new map with dimensions: ", width, "x", height)
	var map := _initialize_empty_map(width, height, 1)

	# Initialize terrain array
	Log.i("Initializing terrain array...")
	for x in range(width):
		for y in range(height):
			# Create walls around the edges
			if x == 0 or x == width - 1 or y == 0 or y == height - 1:
				var tile := Terrain.new()
				tile.type = Terrain.Type.DUNGEON_WALL
				map.cells[x][y].terrain = tile
			else:
				var tile := Terrain.new()
				tile.type = Terrain.Type.DUNGEON_FLOOR
				map.cells[x][y].terrain = tile

	# Add stairs in corners (avoiding the outer walls)
	var stairs_up := Obstacle.new()
	stairs_up.type = Obstacle.Type.STAIRS_UP
	map.cells[1][1].obstacle = stairs_up

	# Add some random containers filled with random items
	var container_types := [
		&"sack",
		&"large_box",
	]
	for _i in range(randi_range(5, 10)):
		var tries := 0
		while tries < 10:
			var x := randi_range(1, width - 2)  # Avoid edges
			var y := randi_range(1, height - 2)
			var cell: MapCell = map.cells[x][y]
			if _is_valid_empty_floor(cell):
				# Create random container
				var container_type: StringName = container_types[randi() % container_types.size()]
				var container := ItemFactory.create_item(container_type)

				# Randomly set container as open or closed (30% chance to be open)
				if randf() < 0.3:
					container.open()

				# Add 1-3 random items inside
				var num_items := randi_range(1, 3)
				for _j in range(num_items):
					# Get list of possible items weighted by probability
					var possible_items: Array[StringName] = []
					for item_id: StringName in ItemFactory.item_data:
						var probability: int = ItemFactory.item_data[item_id].probability
						if probability > 0:
							for _k in range(probability):
								possible_items.append(item_id)

					# Create random item from weighted list
					if not possible_items.is_empty():
						var item_id: StringName = possible_items[randi() % possible_items.size()]
						var item := ItemFactory.create_item(item_id)

						# If stackable, set random quantity between 1-5
						if item.max_stack_size > 1:
							item.quantity = Dice.roll(1, 5)

						# Add item to container if there's room
						if container.children.size() < container.max_children:
							container.add_child(item)

				# Add container to map
				map.add_item_with_stacking(Vector2i(x, y), container)
				break
			tries += 1

	# # Add some random crates
	# for _i in range(10):
	# 	var tries := 0
	# 	while tries < 10:
	# 		var x := randi_range(1, width - 2)  # Avoid edges
	# 		var y := randi_range(1, height - 2)
	# 		var cell: MapCell = map.cells[x][y]
	# 		if _is_valid_empty_floor(cell):
	# 			var crate := Obstacle.new()
	# 			crate.type = Obstacle.Type.CRATE
	# 			cell.obstacle = crate
	# 			break
	# 		tries += 1

	# # Add some monsters (not humans)
	# var monster_ids: Array[StringName] = []
	# for monster_id: StringName in MonsterFactory.monster_data:
	# 	if monster_id != &"human":
	# 		monster_ids.append(monster_id)
	# for i in range(10):
	# 	var monster_id: StringName = monster_ids[randi() % monster_ids.size()]
	# 	var monster := MonsterFactory.create_monster(monster_id)

	# 	var tries := 0
	# 	while tries < 10:
	# 		var x := randi_range(0, map.width - 1)
	# 		var y := randi_range(0, map.height - 1)
	# 		var cell: MapCell = map.cells[x][y]
	# 		if _is_valid_empty_floor(cell):
	# 			cell.monster = monster
	# 			break
	# 		tries += 1

	# # Add some random items
	# for _i in range(20):  # Try to place 20 items
	# 	var tries := 0
	# 	while tries < 10:
	# 		var x := randi_range(1, width - 2)  # Avoid edges
	# 		var y := randi_range(1, height - 2)
	# 		var cell: MapCell = map.cells[x][y]
	# 		if _is_valid_empty_floor(cell):
	# 			# Get list of possible items weighted by probability
	# 			var possible_items: Array[StringName] = []
	# 			for item_id: StringName in ItemFactory.item_data:
	# 				var probability: int = ItemFactory.item_data[item_id].probability
	# 				if probability > 0:
	# 					for _j in range(probability):
	# 						possible_items.append(item_id)

	# 			# Create random item from weighted list
	# 			if not possible_items.is_empty():
	# 				var item_id: StringName = possible_items[randi() % possible_items.size()]
	# 				var item := ItemFactory.create_item(item_id)

	# 				# If stackable, set random quantity between 1-5
	# 				if item.max_stack_size > 1:
	# 					item.quantity = Dice.roll(1, 5)

	# 				map.add_item_with_stacking(Vector2i(x, y), item)
	# 			break
	# 		tries += 1

	Log.i("Map generation complete")
	return map


func _is_valid_empty_floor(cell: MapCell) -> bool:
	return (
		cell.terrain.type == Terrain.Type.DUNGEON_FLOOR
		and cell.items.is_empty()
		and not cell.monster
		and not cell.obstacle
	)
