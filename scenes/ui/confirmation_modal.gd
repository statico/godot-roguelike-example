class_name ConfirmationModal
extends Modal

signal confirmed(confirmed: bool)

var _title: String
var _message: String

var title: String:
	get:
		return _title
	set(value):
		_title = value
		if title_label:
			title_label.text = value

var message: String:
	get:
		return _message
	set(value):
		_message = value
		if message_label:
			message_label.text = value

@onready var title_label: Label = %TitleLabel
@onready var message_label: Label = %MessageLabel
@onready var yes_button: Button = %YesButton
@onready var no_button: Button = %NoButton


func _ready() -> void:
	super._ready()
	title_label.text = _title
	message_label.text = _message
	yes_button.pressed.connect(_on_yes_button_pressed)
	no_button.pressed.connect(_on_no_button_pressed)


func _unhandled_input(event: InputEvent) -> void:
	super._unhandled_input(event)

	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_on_yes_button_pressed()
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_no_button_pressed()


func _on_yes_button_pressed() -> void:
	confirmed.emit(true)
	_close_modal()


func _on_no_button_pressed() -> void:
	confirmed.emit(false)
	_close_modal()
