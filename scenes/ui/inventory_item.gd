@icon("res://assets/icons/inventory_item.svg")
class_name InventoryItem
extends Control

signal clicked(item: Item, shift_clicked: bool)
signal double_clicked(item: Item)
signal item_added_to_container(container: Item, added_item: Item)

var item: Item:
	set(value):
		_item = value
		_update_contents()
	get:
		return _item

@export var selected := false:
	set(value):
		_selected = value
		_update_background()
	get:
		return _selected

@export var nesting_depth := 0:
	set(value):
		_nesting_depth = value
		_update_contents()
	get:
		return _nesting_depth

var _item: Item
var _selected := false
var _hovered := false
var _dragging := false
var _nesting_depth := 0

@onready var background: ColorRect = %Background
@onready var outline: ReferenceRect = %Outline
@onready var prefix: Label = %Prefix
@onready var icon: TextureRect = %Icon
@onready var label: Label = %Label
@onready var suffix: Label = %Suffix


func _ready() -> void:
	# Show something useful in the editor for prototyping
	if Engine.is_editor_hint():
		_item = Item.new(true)
		_item.name = "+1 Tactical Banana"
		_item.sprite_name = &"banana"

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exit)
	gui_input.connect(_on_gui_input)

	_update_contents()
	_update_background()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		_dragging = true
		_update_background()
	elif what == NOTIFICATION_DRAG_END:
		_dragging = false
		_update_background()


func _on_mouse_entered() -> void:
	_hovered = true
	_update_background()


func _on_mouse_exit() -> void:
	_hovered = false
	_update_background()


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.double_click:
			double_clicked.emit(item)
		elif mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			clicked.emit(item, mouse_event.shift_pressed)


func _update_contents() -> void:
	if not is_node_ready():
		return

	if not _item:
		icon.texture = null
		label.text = "No item"
		prefix.text = ""
		suffix.text = ""
		tooltip_text = ""
		return

	icon.texture = ItemTiles.get_texture(_item.sprite_name)
	var text := _item.get_name(Item.NameFormat.PLAIN)
	label.text = text
	tooltip_text = _item.get_info()

	# Set prefix based on nesting depth
	if _nesting_depth > 0:
		prefix.text = "   ".repeat(_nesting_depth + 1) + "↳"
	else:
		prefix.text = ""

	if World.player.equipment.is_item_equipped(_item):
		suffix.text = "- Equipped"
	elif _item.is_container():
		suffix.text = "- %s" % ["Open" if _item.is_open else "Closed"]
	elif _item.children.size() > 0:
		# Show container-like status for items with children
		if _item.type == Item.Type.GUN:
			suffix.text = "- %s" % ["Loaded" if _item.children.size() > 0 else "Empty"]
		else:
			suffix.text = "- %s" % ["Open" if _item.is_open else "Closed"]
	else:
		suffix.text = ""


func _update_background() -> void:
	if not is_node_ready():
		return

	outline.visible = false
	background.color = Color.TRANSPARENT
	modulate = Color.WHITE

	var droppable := false
	if _dragging:
		var data: Variant = get_viewport().gui_get_drag_data()
		droppable = (
			data is Item and (item == data or item.can_accept_child(data as Item).can_accept)
		)
		modulate.a = 1.0 if droppable else 0.5

	if _selected and _hovered:
		background.color = GameColors.SELECTION + Color(0.0, 0.0, 0.0, 0.6)
	elif _selected:
		background.color = GameColors.SELECTION
	elif _hovered:
		if _dragging:
			if droppable:
				outline.border_color = GameColors.FOCUS_OUTLINE
				outline.visible = true
		else:
			background.color = GameColors.HIGHLIGHT_MODULATION


func _get_drag_data(_at_position: Vector2) -> Variant:
	if not item:
		return null
	Log.d("[DragDrop] Started dragging item: %s" % item.get_name(Item.NameFormat.THE))
	set_drag_preview(ItemTiles.get_preview(item.sprite_name))
	return item


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	# Make this super permissive because we need to handle this logic elsewhere,
	# such as _update_background() here and the ReparentItemAction action.
	return data is Item


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var dropped_item: Item = data as Item

	# Check if this item can accept the dropped item
	var check := item.can_accept_child(dropped_item)
	if not check.can_accept:
		World.message_logged.emit(check.reason)
		return

	Log.d(
		(
			"[DragDrop] Dropping %s onto %s"
			% [dropped_item.get_name(Item.NameFormat.THE), item.get_name(Item.NameFormat.THE)]
		)
	)

	# Emit signal to handle the container operation through ReparentItemAction
	item_added_to_container.emit(item, dropped_item)
