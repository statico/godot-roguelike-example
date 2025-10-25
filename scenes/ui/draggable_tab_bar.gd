@icon("res://assets/icons/tab_bar.svg")
class_name DraggableTabBar
extends TabBar

signal item_dropped(item: Item, tab_idx: int)

var _last_drag_hover_tab: int = -1


func _ready() -> void:
	pass


func _can_drop_data(p_position: Vector2, _data: Variant) -> bool:
	# Get the tab index at the drop position
	var tab_idx := get_tab_idx_at_point(p_position)
	if tab_idx >= 0:
		_last_drag_hover_tab = tab_idx
		# Switch to the tab being dragged over
		current_tab = tab_idx
	return true


func _drop_data(_position: Vector2, data: Variant) -> void:
	if data is Item:
		item_dropped.emit(data, _last_drag_hover_tab)
	_last_drag_hover_tab = -1
