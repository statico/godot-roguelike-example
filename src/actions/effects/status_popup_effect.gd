class_name StatusPopupEffect
extends ActionEffect

var text: String
var color: Color


func _init(
	p_target: Monster,
	p_location: Vector2i,
	p_text: String,
	p_color: Color = GameColors.FOREGROUND,
) -> void:
	super(p_target, p_location)
	text = p_text
	color = p_color


func _to_string() -> String:
	return "StatusPopupEffect(target: %s, text: %s, color: %s)" % [target, text, color]
