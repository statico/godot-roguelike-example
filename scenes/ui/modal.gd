@tool
@icon("res://assets/icons/modal.svg")
class_name Modal
extends Control

signal modal_closed(modal: Modal)


# Override this to handle specific modal input
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close_modal()


# Override this to handle GUI-specific input (clicks, etc)
func _gui_input(_event: InputEvent) -> void:
	pass


# Class this to close the modal
func _close_modal() -> void:
	modal_closed.emit(self)


func _ready() -> void:
	# Overlay is optional. Create one for full screen modals.
	var overlay: ColorRect = get_node_or_null("%Overlay")
	if overlay is ColorRect:
		overlay.mouse_filter = MOUSE_FILTER_STOP
		overlay.gui_input.connect(_on_overlay_clicked)


func _on_overlay_clicked(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_close_modal()
