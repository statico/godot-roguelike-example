@tool
extends EditorScript
class_name GenCharactersTileset

const ATLAS_PATH = "res://assets/generated/character_tiles.png"
const JSON_PATH = "res://assets/generated/character_tiles.json"
const OUTPUT_PATH = "res://assets/generated/character_tiles.tres"


func _run() -> void:
	print("Starting character tileset generation...")

	# Load the atlas texture
	var atlas_texture := load(ATLAS_PATH) as Texture2D
	if not atlas_texture:
		printerr("Failed to load atlas texture from ", ATLAS_PATH)
		return

	# Load the JSON coordinates
	var json_file := FileAccess.open(JSON_PATH, FileAccess.READ)
	if not json_file:
		printerr("Failed to open JSON file at ", JSON_PATH)
		return

	var json_text := json_file.get_as_text()
	json_file.close()

	var json := JSON.parse_string(json_text) as Dictionary
	if not json:
		printerr("Failed to parse JSON data")
		return

	var tile_width := json.tileWidth as int
	var tile_height := json.tileHeight as int

	# Create the tileset resource
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(int(tile_width / 2.0), tile_height)  # Divide width by 2 for single frame

	# Create the atlas source
	var atlas_source := TileSetAtlasSource.new()
	atlas_source.texture = atlas_texture
	atlas_source.texture_region_size = Vector2i(int(tile_width / 2.0), tile_height)  # Single frame size

	# Add each tile from the JSON coordinates
	for tile_name: String in json.sprites:
		var coords := json.sprites[tile_name] as Array
		var atlas_coords := Vector2i(
			int((coords[0] as float) / (tile_width / 2.0)),
			int((coords[1] as float) / float(tile_height))
		)

		# Create two tiles for each sprite (one for each frame)
		for frame in range(2):
			var frame_coords := Vector2i(atlas_coords.x + frame, atlas_coords.y)
			if not atlas_source.has_tile(frame_coords):
				atlas_source.create_tile(frame_coords)

	# Add the atlas source to the tileset
	var source_id := 0  # First source
	tileset.add_source(atlas_source, source_id)

	# Save the tileset resource
	var err := ResourceSaver.save(tileset, OUTPUT_PATH)
	if err != OK:
		printerr("Failed to save tileset resource: ", err)
		return

	print("Successfully generated character tileset at ", OUTPUT_PATH)
	print("Tileset contains ", atlas_source.get_tiles_count(), " tiles")
	print("Tile size: ", tileset.tile_size)
