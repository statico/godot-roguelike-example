class_name Actor
extends Node2D

const SHAKE_DURATION: float = 0.15
const ANIMATION_SPEED: float = 0.25
const MOVE_DURATION: float = 0.08
const DEATH_FADE_DURATION: float = 0.5
const HIT_EFFECT_DURATION: float = 0.25

var monster: Monster
var grid_pos: Vector2i
var shake_time: float = 0.0
var animation_time: float = 0.0
var is_moving: bool = false
var move_time: float = 0.0
var move_start_pos: Vector2
var move_target_pos: Vector2
var death_fade_time: float = 0.0
var is_fading: bool = false
var popup: StatusPopup = null

var _health_tween: Tween
var _last_health: float = -1  # Initialize to invalid value to force first update

@onready var character: Sprite2D = %Character
@onready var hit_particles: GPUParticles2D = %HitParticles
@onready var health: Node2D = %Health
@onready var health_bg: ColorRect = %HealthBG
@onready var health_level: ColorRect = %HealthLevel


func init(p_pos: Vector2i) -> void:
	grid_pos = p_pos

	# Set position directly without animation for newly created actors
	position = Vector2(grid_pos * Constants.TILE_SIZE)


func _ready() -> void:
	# Set up materials
	character.material = character.material.duplicate()
	assert(character.material is ShaderMaterial)

	# Ensure particle material is unique to this instance
	hit_particles.emitting = false
	character.frame = 0
	character.flip_h = false

	# Face random direction when starting
	if monster != World.player:
		character.flip_h = randi_range(0, 1) == 0

	# Set up initial appearance
	_choose_initial_appearance()

	(character.material as ShaderMaterial).set_shader_parameter("hop_progress", 0.0)


func _process(delta: float) -> void:
	_update_appearance()

	var character_mat := character.material as ShaderMaterial

	# Handle shaking
	if shake_time > 0:
		shake_time -= delta
		if monster.is_dead:
			shake_time = 0
		if shake_time <= 0:
			character_mat.set_shader_parameter("shake_amount", 0.0)

	# Handle animation
	animation_time += delta
	if animation_time >= ANIMATION_SPEED:
		animation_time = 0
		if not monster.is_dead:
			if is_moving or character_mat.get_shader_parameter("bounce_amount") > 0.0:
				character.frame = 0  # Force frame 0 during movement or attacks
			else:
				character.frame = (character.frame + 1) % character.hframes

	# Handle movement transition
	if is_moving:
		if move_time > 0:
			move_time -= delta
			var t: float = 1.0 - (move_time / MOVE_DURATION)
			# Use ease for smooth acceleration and deceleration
			t = ease(t, 2.0)
			# Calculate base position
			position = move_start_pos.lerp(move_target_pos, t)
			# Update hop progress in shader
			character_mat.set_shader_parameter("hop_progress", t)
		else:
			is_moving = false
			position = move_target_pos
			character_mat.set_shader_parameter("hop_progress", 0.0)

	# Handle death fade
	if is_fading:
		death_fade_time -= delta
		if death_fade_time <= 0:
			modulate.a = 0.0
			is_fading = false
		else:
			var t: float = death_fade_time / DEATH_FADE_DURATION
			# Use ease for smooth fade out
			t = ease(t, 0.5)  # Using 0.5 for a slightly accelerated fade
			modulate.a = t

	# Handle health
	var health_percent: float = maxf(0.05, float(monster.hp) / monster.max_hp)
	if monster.is_dead:
		health.visible = false
	elif health_percent < 1.0:
		health.visible = true

		# Only tween if health has changed
		if health_percent != _last_health:
			_last_health = health_percent

			# Kill any existing tween
			if _health_tween:
				_health_tween.kill()

			# Create new tween for smooth health changes
			_health_tween = create_tween()
			var target_width := int((health_bg.size.x - 2.0) * health_percent)
			(
				_health_tween
				. tween_property(health_level, "size:x", target_width, 0.2)
				. set_trans(Tween.TRANS_SINE)
				. set_ease(Tween.EASE_IN_OUT)
			)
	else:
		health.visible = false
		_last_health = 1.0  # Reset last health when full


func _shake(intensity: float = 1.0, duration: float = 0.2) -> void:
	var character_mat := character.material as ShaderMaterial

	shake_time = duration
	character_mat.set_shader_parameter("shake_amount", intensity * 2.0)
	hit_particles.restart()
	hit_particles.emitting = true


func set_facing_direction(direction: Vector2i) -> void:
	if direction.x != 0:  # Only change facing for horizontal movement
		character.flip_h = direction.x > 0


func teleport_to(new_pos: Vector2i) -> void:
	# Calculate movement direction
	var direction: Vector2i = new_pos - grid_pos
	set_facing_direction(direction)

	grid_pos = new_pos

	# Set up movement animation
	move_start_pos = position
	move_target_pos = Vector2(grid_pos * Constants.TILE_SIZE)
	move_time = MOVE_DURATION
	is_moving = true


func move_to(new_pos: Vector2i) -> void:
	teleport_to(new_pos)

	# Set up movement animation
	move_start_pos = position
	move_target_pos = Vector2(grid_pos * Constants.TILE_SIZE)
	move_time = MOVE_DURATION
	is_moving = true

	await get_tree().create_timer(MOVE_DURATION).timeout


func trigger_attack_effect(to_direction: Vector2 = Vector2.ZERO) -> void:
	var mat: ShaderMaterial = character.material
	# Convert grid direction to pixel direction without normalizing
	var bounce_dir: Vector2i = to_direction * (Constants.TILE_SIZE / 2.0)
	mat.set_shader_parameter("bounce_direction", bounce_dir)
	mat.set_shader_parameter("bounce_amount", 1.0)

	# Create a tween to smoothly reset the bounce
	var tween: Tween = create_tween()
	(
		tween
		. tween_property(mat, "shader_parameter/bounce_amount", 0.0, HIT_EFFECT_DURATION)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_IN_OUT)
	)

	# Only wait for half of the bounce animation
	await get_tree().create_timer(HIT_EFFECT_DURATION).timeout


func trigger_hit_effect(from_direction: Vector2 = Vector2.ZERO) -> void:
	_shake(1.0, 0.2)
	hit_particles.restart()
	hit_particles.emitting = true

	# Set particle direction based on hit direction
	var pmat: ParticleProcessMaterial = hit_particles.process_material
	pmat.direction = Vector3(-from_direction.x, -from_direction.y, 0)

	# Add hit flash effect
	var mat := character.material as ShaderMaterial
	mat.set_shader_parameter("hit_flash", 1.0)
	var flash_tween := create_tween()
	flash_tween.tween_property(mat, "shader_parameter/hit_flash", 0.0, SHAKE_DURATION)

	await get_tree().create_timer(hit_particles.lifetime).timeout


func trigger_death_effect() -> void:
	_shake(1.75, 0.5)
	hit_particles.restart()
	hit_particles.emitting = true
	var pmat: ParticleProcessMaterial = hit_particles.process_material
	pmat.direction = Vector3(0, 0, 0)

	# Handle player death differently than monsters
	if monster == World.player:
		# For player, immediately update appearance to tombstone
		_update_appearance()
		modulate.a = 1.0  # Ensure player remains fully visible
	else:
		# Fade out non-player monsters
		is_fading = true
		death_fade_time = DEATH_FADE_DURATION
		modulate.a = 1.0  # Ensure we start fully visible

	# Wait for the longest effect to complete
	var effect_duration: float = max(shake_time, hit_particles.lifetime, DEATH_FADE_DURATION)
	await get_tree().create_timer(effect_duration).timeout


func _choose_initial_appearance() -> void:
	var pmat: ParticleProcessMaterial = hit_particles.process_material

	# Get appearance data from monster factory
	var data := MonsterFactory.monster_data.get(monster.slug, {}) as Dictionary
	var appearances: Array = data.get("appearance", [])

	# Choose sprite based on species and available appearances
	assert(not appearances.is_empty())
	var tile_name: String = appearances[monster.variant % appearances.size()]
	character.region_rect = CharacterTiles.get_region(StringName(tile_name))

	character.flip_h = true
	pmat.color = monster.hit_particles_color


func _update_appearance() -> void:
	# Override sprite with a tombstone if the player is dead
	if monster == World.player and monster.is_dead:
		# Show a tombstone
		# character.texture = WorldTiles.TEXTURE
		# character.region_rect = WorldTiles.get_region(&"tombstone")
		# character.region_enabled = true
		# character.flip_h = false
		# character.frame = 0
		# character.hframes = 1
		character.visible = false
