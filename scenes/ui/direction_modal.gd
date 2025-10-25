class_name DirectionModal
extends Modal

signal direction_selected(direction: Vector3i)

const NW := Vector3i(-1, -1, 0)
const N := Vector3i(0, -1, 0)
const NE := Vector3i(1, -1, 0)
const W := Vector3i(-1, 0, 0)
const HERE := Vector3i(0, 0, 0)
const E := Vector3i(1, 0, 0)
const SW := Vector3i(-1, 1, 0)
const S := Vector3i(0, 1, 0)
const SE := Vector3i(1, 1, 0)
const UP := Vector3i(0, 0, 1)
const DOWN := Vector3i(0, 0, -1)

@onready var nw_button: Button = %NW
@onready var n_button: Button = %N
@onready var ne_button: Button = %NE
@onready var w_button: Button = %W
@onready var here_button: Button = %Here
@onready var e_button: Button = %E
@onready var sw_button: Button = %SW
@onready var s_button: Button = %S
@onready var se_button: Button = %SE
@onready var up_button: Button = %Up
@onready var down_button: Button = %Down
@onready var cancel_button: Button = %Cancel


func _ready() -> void:
	super._ready()
	# Connect all button signals
	nw_button.pressed.connect(_on_direction_pressed.bind(NW))
	n_button.pressed.connect(_on_direction_pressed.bind(N))
	ne_button.pressed.connect(_on_direction_pressed.bind(NE))
	w_button.pressed.connect(_on_direction_pressed.bind(W))
	here_button.pressed.connect(_on_direction_pressed.bind(HERE))
	e_button.pressed.connect(_on_direction_pressed.bind(E))
	sw_button.pressed.connect(_on_direction_pressed.bind(SW))
	s_button.pressed.connect(_on_direction_pressed.bind(S))
	se_button.pressed.connect(_on_direction_pressed.bind(SE))
	up_button.pressed.connect(_on_direction_pressed.bind(UP))
	down_button.pressed.connect(_on_direction_pressed.bind(DOWN))
	cancel_button.pressed.connect(_on_cancel_pressed)

	visible = true


func _unhandled_input(event: InputEvent) -> void:
	super._unhandled_input(event)

	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_cancel_pressed()
	elif event.is_action_pressed("move_up_left"):
		get_viewport().set_input_as_handled()
		_on_direction_pressed(NW)
	elif event.is_action_pressed("move_up"):
		get_viewport().set_input_as_handled()
		_on_direction_pressed(N)
	elif event.is_action_pressed("move_up_right"):
		get_viewport().set_input_as_handled()
		_on_direction_pressed(NE)
	elif event.is_action_pressed("move_left"):
		get_viewport().set_input_as_handled()
		_on_direction_pressed(W)
	elif event.is_action_pressed("rest"):
		get_viewport().set_input_as_handled()
		_on_direction_pressed(HERE)
	elif event.is_action_pressed("move_right"):
		get_viewport().set_input_as_handled()
		_on_direction_pressed(E)
	elif event.is_action_pressed("move_down_left"):
		get_viewport().set_input_as_handled()
		_on_direction_pressed(SW)
	elif event.is_action_pressed("move_down"):
		get_viewport().set_input_as_handled()
		_on_direction_pressed(S)
	elif event.is_action_pressed("move_down_right"):
		get_viewport().set_input_as_handled()
		_on_direction_pressed(SE)
	elif event.is_action_pressed("move_upstairs"):
		get_viewport().set_input_as_handled()
		_on_direction_pressed(UP)
	elif event.is_action_pressed("move_downstairs"):
		get_viewport().set_input_as_handled()
		_on_direction_pressed(DOWN)


func _on_direction_pressed(direction: Vector3i) -> void:
	direction_selected.emit(direction)
	_close_modal()


func _on_cancel_pressed() -> void:
	direction_selected.emit(Vector3i.ZERO)
	_close_modal()
