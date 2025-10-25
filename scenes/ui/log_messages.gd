@tool
class_name LogMessages
extends ScrollContainer

enum Level {
	GREAT = 2,
	GOOD = 1,
	NORMAL = 0,
	BAD = -1,
	TERRIBLE = -2,
	FATAL = -3,
	ERROR = -4,
}

const OLD_MESSAGE_OPACITY := 0.6

@onready var messages_container: Control = %Messages


func _ready() -> void:
	_clear_messages()

	if Engine.is_editor_hint():
		return

	World.message_logged.connect(_on_message_logged)
	World.world_initialized.connect(_on_world_initialized)
	World.turn_started.connect(_on_turn_started)


func _on_world_initialized() -> void:
	_clear_messages()
	_on_message_logged("You descend into the dungeon...")


func _on_turn_started() -> void:
	# Dim existing messages at the start of each turn
	for message_label: RichTextLabel in messages_container.get_children():
		message_label.modulate.a = OLD_MESSAGE_OPACITY


func _on_message_logged(message: String, level: int = Level.NORMAL) -> void:
	var color := ""
	match level:
		Level.GREAT:
			color = GameColors.GREEN.to_html()
		Level.GOOD:
			color = GameColors.CYAN.to_html()
		Level.BAD:
			color = GameColors.YELLOW.to_html()
		Level.TERRIBLE:
			color = GameColors.RED.to_html()
		Level.FATAL:
			color = GameColors.RED.to_html()
		Level.ERROR:
			color = GameColors.ORANGE.to_html()

	# Add new message with full opacity
	var label := RichTextLabel.new()
	if color:
		label.text = "[color=%s]%s[/color]" % [color, message]
	else:
		label.text = message
	label.bbcode_enabled = true
	label.fit_content = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_END
	label.modulate.a = 1.0  # Ensure new message is fully visible

	messages_container.add_child(label)

	# Ensure we scroll to the bottom to show newest messages
	await get_tree().process_frame
	ensure_control_visible(label)


func _clear_messages() -> void:
	for child in messages_container.get_children():
		child.queue_free()
