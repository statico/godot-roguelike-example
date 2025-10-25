@tool
extends Node

const JSON_PATH = &"res://assets/generated/item_sprites.json"
const TEXTURE = preload("res://assets/generated/item_sprites.png")

var tile_size: int = 16
var _tile_map: Dictionary[StringName, Vector2i] = {}


func _init() -> void:
	_load_tiles()


func _load_tiles() -> void:
	# Check if we need to reload by comparing modified times
	var file := FileAccess.open(JSON_PATH, FileAccess.READ)
	if not file:
		printerr("Failed to open JSON file at ", JSON_PATH)
		return

	# Parse JSON
	var json_text: String = file.get_as_text()
	var json: Variant = JSON.parse_string(json_text)
	if not json:
		printerr("Failed to parse JSON data")
		return

	# Update sprite size and clear existing map
	tile_size = json.spriteSize as int
	_tile_map.clear()

	# Populate sprite map with StringNames
	for sprite_name: String in json.sprites:
		var coords: Array = json.sprites[sprite_name]
		_tile_map[StringName(sprite_name)] = Vector2i(
			int(coords[0] as float / float(tile_size)), int(coords[1] as float / float(tile_size))
		)


func get_coords(p_name: StringName) -> Vector2i:
	assert(not _tile_map.is_empty(), "Tile map not loaded")
	var ret: Variant = _tile_map.get(p_name, Utils.INVALID_POS)
	assert(ret != Utils.INVALID_POS, "Sprite not found: %s" % p_name)
	return ret as Vector2i


func get_all_names() -> Array[StringName]:
	return _tile_map.keys()


func get_region(p_name: StringName) -> Rect2:
	var coords := get_coords(p_name)
	return Rect2(coords.x * tile_size, coords.y * tile_size, tile_size, tile_size)


func get_texture(p_name: StringName) -> AtlasTexture:
	# Create atlas texture for the sprite
	var texture := AtlasTexture.new()
	texture.atlas = TEXTURE
	texture.region = get_region(p_name)
	return texture


func get_preview(p_name: StringName) -> TextureRect:
	var preview := TextureRect.new()
	preview.texture = get_texture(p_name)
	preview.position = Vector2(tile_size * -.75, tile_size * -.75)

	# Wrap the preview in a Control so it will be centered properly
	var container := Control.new()
	container.add_child(preview)
	return container


func get_name_from_coords(p_coords: Vector2i) -> StringName:
	var ret: Variant = _tile_map.find_key(p_coords)
	assert(ret != null, "Item tile not found: %s" % p_coords)
	return ret as StringName


func get_bbcode_image(p_name: String) -> String:
	var coords := get_coords(p_name)
	# Return BBCode that references the atlas texture and specifies the region
	return (
		"[img=%dx%d region=%d,%d,%d,%d]%s[/img]"
		% [
			tile_size,
			tile_size,  # Display size
			coords.x * tile_size,
			coords.y * tile_size,  # Region x,y
			tile_size,
			tile_size,  # Region width,height
			TEXTURE.resource_path  # Texture path
		]
	)
