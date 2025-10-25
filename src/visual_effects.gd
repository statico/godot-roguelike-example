class_name VisualEffects
extends RefCounted

## This used to be sprite-based, but for the example we'll use simple particles.

const PROJECTILE_SPEED := 400.0


## Animates a projectile from start to end position
static func animate_projectile(
	parent: Node,
	start_pos: Vector2i,
	end_pos: Vector2i,
	item: Item = null,
	is_thrown_item: bool = false
) -> void:
	var projectile := Sprite2D.new()
	if is_thrown_item and item:
		projectile.texture = ItemTiles.get_texture(item.sprite_name)
	else:
		projectile.texture = preload("res://assets/textures/fx/arrow.png")

	var start := Vector2(start_pos) * Constants.TILE_SIZE_VEC2 + Constants.HALF_TILE_SIZE_VEC2
	var end := Vector2(end_pos) * Constants.TILE_SIZE_VEC2 + Constants.HALF_TILE_SIZE_VEC2
	projectile.position = start
	parent.add_child(projectile)

	var distance := start.distance_to(end)
	var duration := distance / PROJECTILE_SPEED * (2.0 if is_thrown_item else 1.0)

	# Calculate rotation to face movement direction
	projectile.rotation = (end - start).angle()

	# Create animation tween
	var tween := parent.create_tween().set_parallel(true)
	tween.tween_property(projectile, "position", end, duration).set_ease(Tween.EASE_IN_OUT)

	if is_thrown_item:
		# Make thrown items spin and scale
		(
			tween
			. tween_property(projectile, "rotation", PI * 8 * distance / PROJECTILE_SPEED, duration)
			. set_ease(Tween.EASE_IN_OUT)
		)
		tween.tween_property(projectile, "scale", Vector2(1.2, 1.2), duration / 2.0).set_ease(
			Tween.EASE_IN_OUT
		)
		(
			tween
			. chain()
			. tween_property(projectile, "scale", Vector2(1.0, 1.0), duration / 2.0)
			. set_ease(Tween.EASE_IN_OUT)
		)

	await tween.finished
	projectile.queue_free()


## Creates and plays an explosion effect at the given position
static func create_explosion(
	parent: Node, pos: Vector2i, _big: bool = false, _item: Item = null
) -> void:
	var explosion := AnimatedSprite2D.new()
	explosion.sprite_frames = preload("res://scenes/fx/explosion.tres")
	explosion.position = (Vector2(pos) * Constants.TILE_SIZE_VEC2 + Constants.HALF_TILE_SIZE_VEC2)
	parent.add_child(explosion)
	explosion.play()
	await explosion.animation_finished
	explosion.queue_free()

## -------------------- OLD IMPLEMENTATION WITH SPTITE ANIMATIONS --------------------

# ## Animates a projectile from start to end position
# static func animate_projectile(
# 	parent: Node,
# 	start_pos: Vector2i,
# 	end_pos: Vector2i,
# 	item: Item = null,
# 	is_thrown_item: bool = false
# ) -> void:
# 	var projectile: Node2D
# 	if is_thrown_item and item:
# 		var sprite := Sprite2D.new()
# 		sprite.texture = ItemTiles.get_texture(item.sprite_name)
# 		projectile = sprite
# 	else:
# 		var sprite := AnimatedSprite2D.new()
# 		sprite.sprite_frames = preload("res://assets/fx/projectile.tres")
# 		sprite.play(_get_projectile_animation(item))
# 		projectile = sprite

# 	var start := Vector2(start_pos) * Constants.TILE_SIZE_VEC2 + Constants.HALF_TILE_SIZE_VEC2
# 	var end := Vector2(end_pos) * Constants.TILE_SIZE_VEC2 + Constants.HALF_TILE_SIZE_VEC2
# 	projectile.position = start
# 	parent.add_child(projectile)

# 	var distance := start.distance_to(end)
# 	var duration := distance / PROJECTILE_SPEED * (2.0 if is_thrown_item else 1.0)

# 	# Calculate rotation to face movement direction
# 	projectile.rotation = (end - start).angle()

# 	# Create animation tween
# 	var tween := parent.create_tween().set_parallel(true)
# 	tween.tween_property(projectile, "position", end, duration).set_ease(Tween.EASE_IN_OUT)

# 	if is_thrown_item:
# 		# Make thrown items spin and scale
# 		(
# 			tween
# 			. tween_property(projectile, "rotation", PI * 8 * distance / PROJECTILE_SPEED, duration)
# 			. set_ease(Tween.EASE_IN_OUT)
# 		)
# 		tween.tween_property(projectile, "scale", Vector2(1.2, 1.2), duration / 2.0).set_ease(
# 			Tween.EASE_IN_OUT
# 		)
# 		(
# 			tween
# 			. chain()
# 			. tween_property(projectile, "scale", Vector2(1.0, 1.0), duration / 2.0)
# 			. set_ease(Tween.EASE_IN_OUT)
# 		)

# 	await tween.finished
# 	projectile.queue_free()

# ## Creates and plays an explosion effect at the given position
# static func create_explosion(
# 	parent: Node, pos: Vector2i, big: bool = false, item: Item = null
# ) -> void:
# 	var explosion := AnimatedSprite2D.new()
# 	explosion.sprite_frames = preload("res://assets/fx/explosion.tres")
# 	explosion.position = (Vector2(pos) * Constants.TILE_SIZE_VEC2 + Constants.HALF_TILE_SIZE_VEC2)
# 	parent.add_child(explosion)

# 	if big:
# 		explosion.play(&"bigblast")
# 	else:
# 		explosion.play(_get_explosion_animation(item))

# 	await explosion.animation_finished
# 	explosion.queue_free()

# ## Gets the appropriate projectile animation name based on damage type and item
# static func _get_projectile_animation(item: Item = null) -> StringName:
# 	if not item:
# 		return &"firebolt1"  # Default projectile

# 	# Handle special cases for thrown items
# 	if item.type == Item.Type.GRENADE:
# 		return &"flare"

# 	# Check damage types from the item
# 	if item.damage_types:
# 		if Damage.Type.PLASMA in item.damage_types:
# 			return &"plasma"
# 		elif Damage.Type.CORROSIVE in item.damage_types:
# 			return &"corrosive"
# 		elif Damage.Type.RADIATION in item.damage_types:
# 			return &"radiation"
# 		elif Damage.Type.EMP in item.damage_types:
# 			return &"emp"
# 		elif Damage.Type.EXOTIC in item.damage_types:
# 			return &"exotic"
# 		elif Damage.Type.FIRE in item.damage_types:
# 			return &"firebolt1" if randf() > 0.5 else &"firebolt2"

# 	# Default projectile variations for regular weapons
# 	return &"firedot1" if randf() > 0.5 else &"firedot2"

# ## Gets the appropriate explosion animation name based on damage type and item
# static func _get_explosion_animation(item: Item = null) -> StringName:
# 	if not item:
# 		return &"blast1"

# 	# Handle special cases for thrown items
# 	if item.type == Item.Type.GRENADE:
# 		return &"bigblast"

# 	# Check damage types from the item
# 	if item.damage_types:
# 		if Damage.Type.PLASMA in item.damage_types:
# 			return &"plasma"
# 		elif Damage.Type.CORROSIVE in item.damage_types:
# 			return &"corrosive1" if randf() > 0.5 else &"corrosive2"
# 		elif Damage.Type.RADIATION in item.damage_types:
# 			return &"radiation"
# 		elif Damage.Type.EMP in item.damage_types:
# 			return &"emp"
# 		elif Damage.Type.EXOTIC in item.damage_types:
# 			return &"exotic"
# 		elif Damage.Type.FIRE in item.damage_types:
# 			return &"flare"

# 	# Default explosion variations
# 	return &"blast1" if randf() > 0.5 else &"blast2"
