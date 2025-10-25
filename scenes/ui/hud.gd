class_name HUD
extends Control

signal drop_requested(selections: Array[ItemSelection])

@onready var hp_bar: ProgressBarWithLabel = %HP
@onready var status_text: RichTextLabel = %StatusText
@onready var inventory_button: Button = %InventoryButton
@onready var hover_info: RichTextLabel = %HoverInfo
@onready var throw_info: RichTextLabel = %ThrowInfo
@onready var drag_effect: ReferenceRect = %DragEffect
@onready var melee_container: HBoxContainer = %MeleeContainer
@onready var ranged_container: HBoxContainer = %RangedContainer
@onready var armor_container: HBoxContainer = %ArmorContainer
@onready var dawnlike_notice: RichTextLabel = %DawnLikeNotice

const MAX_LOG_LENGTH = 10000
const EQUIPMENT_ICON_SIZE := Vector2(16, 16)
const MAX_MODULES := 3

# Disable this during movement path execution
var updates_enabled: bool = true

var _debug_mode: bool = false
var debug_mode: bool:
	get:
		return _debug_mode
	set(value):
		_debug_mode = value
		_update_display()


func _ready() -> void:
	assert(hp_bar, "HP bar is not found")
	assert(status_text, "StatusText is not found")

	World.world_initialized.connect(_on_world_initialized)
	World.turn_ended.connect(_on_turn_ended)

	inventory_button.pressed.connect(_on_inventory_button_pressed)

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	dawnlike_notice.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mouse_event := event as InputEventMouseButton
			if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
				OS.shell_open("https://opengameart.org/content/16x16-dawnhack-roguelike-tileset")
	)

	throw_info.visible = false


func _on_world_initialized() -> void:
	_update_display()


func _on_turn_ended() -> void:
	_update_display()


func set_hover_info(text: Variant) -> void:
	if not updates_enabled:
		return

	if text is String:
		hover_info.visible = true
		hover_info.text = "[right]" + text
	else:
		hover_info.visible = false


func _update_display() -> void:
	if not updates_enabled:
		return

	hp_bar.set_value_and_max(World.player.hp, World.player.max_hp)

	# Update equipment displays
	_build_weapon_container(
		melee_container, "Melee", World.player.equipment.get_equipped_item(Equipment.Slot.MELEE)
	)

	_build_weapon_container(
		ranged_container, "Ranged", World.player.equipment.get_equipped_item(Equipment.Slot.RANGED)
	)

	_build_armor_container(armor_container)

	# Update basic status text
	status_text.text = "Time: %d" % World.current_turn
	var nutrition_status := World.player.nutrition.get_status()
	if nutrition_status != Nutrition.Status.NORMAL:
		var text := Nutrition.get_status_rich_text_label(nutrition_status)
		status_text.text += " - " + text

	# Update status effects
	for effect: StatusEffect in World.player.status_effects:
		var color := GameColors.ORANGE.to_html()
		status_text.text += (
			" - [color=%s][pulse]%s[/pulse][/color]" % [color, effect.get_adjective()]
		)

	# Debug info
	if debug_mode:
		status_text.text += "\n[color=cyan]Debug info\n"
		status_text.text += "Nutr: %d" % World.player.nutrition.value
		status_text.text += (
			" - Load: %.1f/%.1f"
			% [World.player.get_current_load(), World.player.get_max_carrying_capacity()]
		)
		status_text.text += "[/color]"


func _on_inventory_button_pressed() -> void:
	Modals.toggle_inventory()


func _on_mouse_entered() -> void:
	if get_viewport().gui_is_dragging():
		drag_effect.visible = true


func _on_mouse_exited() -> void:
	drag_effect.visible = false


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if data is Item:
		return true
	return false


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if data is Item:
		var item: Item = data
		var selection := ItemSelection.new(item, item.quantity)
		drop_requested.emit([selection])


func _create_equipment_icon(
	texture: Texture2D, tooltip: String, item: Item = null
) -> HBoxContainer:
	var container := HBoxContainer.new()
	container.add_theme_constant_override("separation", 2)

	var icon := TextureRect.new()
	icon.custom_minimum_size = EQUIPMENT_ICON_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = texture
	icon.tooltip_text = tooltip
	container.add_child(icon)

	return container


func _build_weapon_container(container: HBoxContainer, label_text: String, item: Item) -> void:
	# Clear all children
	for child in container.get_children():
		child.queue_free()

	# Set container properties
	container.add_theme_constant_override("separation", 0)

	# Add the label
	var label := Label.new()
	label.text = label_text + ": "  # Added space after colon
	container.add_child(label)

	if item:
		var main_icon := _create_equipment_icon(
			ItemTiles.get_texture(item.sprite_name), item.get_info(), item
		)
		container.add_child(main_icon)

		# Check for missing ammo in ranged weapons
		if label_text == "Ranged" and item.ammo_type != Damage.AmmoType.NONE:
			var has_ammo := false
			for child: Item in item.children.to_array():
				if child.type == Item.Type.AMMO and child.quantity > 0:
					has_ammo = true
					break

			if not has_ammo:
				var meta := Label.new()
				meta.text = "(no ammo)"
				meta.theme_type_variation = &"SubtleLabel"
				container.add_child(meta)
				return

		# Add module slots
		var children := item.children.to_array()
		for i in range(MAX_MODULES):
			if children.size() > i:
				var child: Item = children[i]
				var module_icon := _create_equipment_icon(
					ItemTiles.get_texture(child.sprite_name), child.get_info(), child
				)
				container.add_child(module_icon)

				# Add ammo count for ranged weapons
				if child.type == Item.Type.AMMO and label_text == "Ranged":
					var meta := Label.new()
					meta.text = "(%d)" % child.quantity
					meta.theme_type_variation = &"SubtleLabel"
					container.add_child(meta)
	else:
		var meta := Label.new()
		meta.text = "(none)"
		meta.theme_type_variation = &"SubtleLabel"
		container.add_child(meta)


func _build_armor_container(container: HBoxContainer) -> void:
	# Clear all children
	for child in container.get_children():
		child.queue_free()

	# Set container properties
	container.add_theme_constant_override("separation", 0)

	# Add the label
	var label := Label.new()
	label.text = "Armor: "  # Added space after colon
	container.add_child(label)

	var icons_container := HBoxContainer.new()
	container.add_child(icons_container)

	var has_armor := false
	for slot: Equipment.Slot in [
		Equipment.Slot.UPPER_ARMOR,
		Equipment.Slot.LOWER_ARMOR,
		Equipment.Slot.BASE,
		Equipment.Slot.CLOAK,
		Equipment.Slot.FOOTWEAR,
		Equipment.Slot.MASK,
		Equipment.Slot.GLOVES,
		Equipment.Slot.HEADWEAR,
		Equipment.Slot.BELT
	]:
		var item := World.player.equipment.get_equipped_item(slot)
		if item:
			has_armor = true
			var icon := _create_equipment_icon(
				ItemTiles.get_texture(item.sprite_name), item.get_info(), item
			)
			icons_container.add_child(icon)

			# Check children of armor items for power sources
			for child: Item in item.children.to_array():
				var child_icon := _create_equipment_icon(
					ItemTiles.get_texture(child.sprite_name), child.get_info(), child
				)
				icons_container.add_child(child_icon)

	if not has_armor:
		label.text = "Armor: (none)"
