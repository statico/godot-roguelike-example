@tool
extends AtlasTexture
class_name ItemTexture

# Property to store the sprite coordinates constant name
@export var sprite_name: StringName:
	get:
		return sprite_name
	set(value):
		sprite_name = value
		_update_region()


func _init() -> void:
	atlas = ItemTiles.TEXTURE


# Update the region rect when the sprite name changes
func _update_region() -> void:
	if Engine.is_editor_hint() and sprite_name and ItemTiles:
		region = ItemTiles.get_region(sprite_name)
