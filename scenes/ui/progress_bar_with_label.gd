class_name ProgressBarWithLabel
extends TextureProgressBar

@onready var label: Label = %Label

var _tween: Tween


func set_value_and_max(new_value: float, new_max: float) -> void:
	max_value = new_max * 100
	label.text = "%d/%d" % [new_value, max_value / 100]

	# Kill any existing tween
	if _tween:
		_tween.kill()

	# Create new tween for smooth value changes
	_tween = create_tween()
	_tween.tween_property(self, "value", new_value * 100, 0.3).set_trans(Tween.TRANS_SINE).set_ease(
		Tween.EASE_OUT
	)
