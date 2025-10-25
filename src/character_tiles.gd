@tool
extends Node

const JSON_PATH = &"res://assets/generated/character_tiles.json"
const TEXTURE = preload("res://assets/generated/character_tiles.png")

var tile_width: int = 32
var tile_height: int = 16
const FRAMES_PER_TILE = 2

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

	# Update tile dimensions and clear existing map
	tile_width = json.tileWidth as int
	tile_height = json.tileHeight as int
	_tile_map.clear()

	# Populate tile map with StringNames
	for tile_name: String in json.sprites:
		var coords: Array = json.sprites[tile_name]
		_tile_map[StringName(tile_name)] = Vector2i(
			coords[0] / tile_width as int, coords[1] / tile_height as int
		)


func get_coords(p_name: StringName) -> Vector2i:
	var ret: Variant = _tile_map.get(p_name, Utils.INVALID_POS)
	assert(ret != Utils.INVALID_POS, "Character tile not found: %s" % p_name)
	return ret as Vector2i


func get_all_names() -> Array[StringName]:
	return _tile_map.keys()


func get_region(p_name: StringName) -> Rect2:
	var coords := get_coords(p_name)
	return Rect2(coords.x * tile_width, coords.y * tile_height, tile_width, tile_height)


func get_texture(p_name: StringName) -> AtlasTexture:
	# Create atlas texture for the character tile
	var texture := AtlasTexture.new()
	texture.atlas = TEXTURE
	texture.region = get_region(p_name)
	return texture


func get_name_from_coords(p_coords: Vector2i) -> StringName:
	var ret: Variant = _tile_map.find_key(p_coords)
	assert(ret != null, "Character tile not found: %s" % p_coords)
	return ret as StringName
