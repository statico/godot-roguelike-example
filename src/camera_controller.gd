class_name CameraController
extends Camera2D

@export var margins: Rect2 = Rect2(200, 100, 200, 100)  # left, top, right, bottom

var zoomed_out: bool = false
var hud_offset: float = 0.0
var _inventory: Control = null


func _init() -> void:
	# Set initial zoom
	zoom = Vector2.ONE

	position_smoothing_enabled = true
	drag_vertical_enabled = true
	drag_horizontal_enabled = true
	_reset_margins()


func _reset_margins() -> void:
	drag_top_margin = 0.1
	drag_bottom_margin = 0.1
	drag_left_margin = 0.1
	drag_right_margin = 0.1


func _ready() -> void:
	# Enable position smoothing after a short delay
	await get_tree().process_frame

	# Get HUD reference and calculate offset
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		var left_panel: Control = hud.get_node("%LeftPanel")
		if left_panel:
			# Get the actual width of the left panel
			await get_tree().process_frame  # Wait for layout
			hud_offset = left_panel.size.x / 2.0

	# Wait for World initialization and connect to map changes
	if not World.world_initialized.is_connected(_on_world_initialized):
		World.world_initialized.connect(_on_world_initialized)
	World.map_changed.connect(_on_map_changed)

	# Connect to inventory signals
	Modals.inventory_opened.connect(func(inventory: InventoryModal) -> void: _inventory = inventory)
	Modals.inventory_closed.connect(func() -> void: _inventory = null)

	# Wait for a frame and then enable position smoothing
	position_smoothing_enabled = false
	await get_tree().process_frame
	position_smoothing_enabled = true


func _process(_delta: float) -> void:
	_move_camera_to_player()

	# Handle zoom toggle
	if Input.is_action_just_pressed("toggle_zoom"):
		_toggle_zoom()


func _move_camera_to_player() -> void:
	if not World.player:
		return

	var target: Actor = get_tree().get_first_node_in_group("player")
	if not target:
		return

	var inventory_width: float = 0.0
	if _inventory and _inventory.get_child_count() > 0:
		inventory_width = (_inventory.get_child(0) as Control).size.x
		drag_top_margin = 0.0
		drag_bottom_margin = 0.0
		drag_left_margin = 0.0
		drag_right_margin = 0.0
	else:
		_reset_margins()

	# Set camera position to keep target centered, accounting for tile size and HUD offset
	position = Vector2(
		target.position.x + WorldTiles.tile_size / 2.0 - hud_offset + inventory_width / 2.0,
		target.position.y + WorldTiles.tile_size / 2.0
	)


func _on_world_initialized() -> void:
	# Force an initial camera position update
	if World.player:
		var target: Actor = get_tree().get_first_node_in_group("player")
		if target:
			position = Vector2(
				target.position.x + WorldTiles.tile_size / 1.0,
				target.position.y + WorldTiles.tile_size / 2.0
			)


func _on_map_changed(_map: Map) -> void:
	Log.d("map changed")

	# Disable smoothing temporarily
	position_smoothing_enabled = false
	Log.d("disabled smoothing")

	# Move camera to player
	_move_camera_to_player()
	Log.d("moved camera to player")

	# Wait for 0.25 seconds
	await get_tree().create_timer(0.25).timeout
	Log.d("waited for 0.25 seconds")

	# Re-enable smoothing
	position_smoothing_enabled = true
	Log.d("re-enabled smoothing")


func _toggle_zoom() -> void:
	zoomed_out = !zoomed_out

	# Create a smooth zoom transition
	var target_zoom := Vector2(0.5, 0.5) if zoomed_out else Vector2.ONE
	var tween := create_tween()
	tween.tween_property(self, "zoom", target_zoom, 0.2).set_trans(Tween.TRANS_SINE)
