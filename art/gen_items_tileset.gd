@tool
extends EditorScript
class_name GenItemsTileset

const ATLAS_PATH = "res://assets/generated/item_sprites.png"
const JSON_PATH = "res://assets/generated/item_sprites.json"
const OUTPUT_PATH = "res://assets/generated/item_sprites.tres"


func _run() -> void:
	print("Starting item tileset generation...")

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

	var sprite_size := json.spriteSize as int

	# Create the tileset resource
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(sprite_size, sprite_size)

	# Create the atlas source
	var atlas_source := TileSetAtlasSource.new()
	atlas_source.texture = atlas_texture
	atlas_source.texture_region_size = Vector2i(sprite_size, sprite_size)

	# Add each sprite from the JSON coordinates
	for sprite_name: String in json.sprites:
		var coords := json.sprites[sprite_name] as Array
		var atlas_coords := Vector2i(
			int((coords[0] as float) / float(sprite_size)),
			int((coords[1] as float) / float(sprite_size))
		)

		# Create the tile at the atlas coordinates
		if not atlas_source.has_tile(atlas_coords):
			atlas_source.create_tile(atlas_coords)

	# Add the atlas source to the tileset
	var source_id := 0  # First source
	tileset.add_source(atlas_source, source_id)

	# Save the tileset resource
	var err := ResourceSaver.save(tileset, OUTPUT_PATH)
	if err != OK:
		printerr("Failed to save tileset resource: ", err)
		return

	print("Successfully generated item tileset at ", OUTPUT_PATH)
	print("Tileset contains ", atlas_source.get_tiles_count(), " tiles")
	print("Tile size: ", tileset.tile_size)
