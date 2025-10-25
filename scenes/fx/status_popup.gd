class_name StatusPopup
extends Control

const RISE_DISTANCE := 8.0
const RISE_TIME := 0.2
const STAY_TIME := 1.0
const FADE_TIME := 0.2

@onready var label: RichTextLabel = %Label

var tween: Tween


func _ready() -> void:
	modulate.a = 1.0
	label.text = "[center]"


func show_popup(text: String, color: Color = GameColors.FOREGROUND) -> void:
	label.text += "[color=#%s]%s[/color]" % [color.to_html(), text]
	modulate.a = 0.0  # Start fully transparent
	_restart_tween()


func append(text: String, color: Color = GameColors.FOREGROUND) -> void:
	label.text += "\n[color=#%s]%s[/color]" % [color.to_html(), text]
	_restart_tween()


func destroy() -> void:
	label.text = ""
	if tween:
		tween.kill()
	queue_free()


func _restart_tween() -> void:
	if tween and is_instance_valid(tween):
		tween.kill()
	tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, RISE_TIME)
	tween.tween_property(self, "position:y", position.y - RISE_DISTANCE, RISE_TIME)
	tween.finished.connect(_on_finished)


func _on_finished() -> void:
	# Wait a bit
	await get_tree().create_timer(STAY_TIME).timeout

	# Fade out
	tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE_TIME)

	# Queue for deletion when done
	await tween.finished
	queue_free()
