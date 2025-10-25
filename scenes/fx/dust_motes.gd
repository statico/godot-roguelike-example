class_name DustMotes
extends Node2D

@onready var clipping_mask: Polygon2D = $ClippingMask
@onready var particles: GPUParticles2D = $ClippingMask/Particles

var _pending_rect: Rect2  # Store the rect if set before ready


func _ready() -> void:
	# If a rect was set before ready, apply it now
	if _pending_rect:
		set_rect(_pending_rect)
	else:
		# Set a default rectangle if none is specified
		set_rect(Rect2(-50, -50, 100, 100))


func set_rect(rect: Rect2) -> void:
	if not is_node_ready():
		_pending_rect = rect
		return

	# Convert rectangle to polygon points (clockwise order)
	var points := PackedVector2Array(
		[
			Vector2(rect.position.x, rect.position.y),  # Top-left
			Vector2(rect.position.x + rect.size.x, rect.position.y),  # Top-right
			Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y),  # Bottom-right
			Vector2(rect.position.x, rect.position.y + rect.size.y)  # Bottom-left
		]
	)

	clipping_mask.polygon = points


func set_dust_visible(p_is_visible: bool) -> void:
	# Only change emitting state if it's different to avoid resetting particles
	if particles.emitting != p_is_visible:
		particles.emitting = p_is_visible
