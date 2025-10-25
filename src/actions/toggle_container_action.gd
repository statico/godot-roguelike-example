class_name ToggleContainerAction

extends ActorAction

var container: Item


func _init(p_actor: Monster, p_container: Item) -> void:
	super(p_actor)
	container = p_container


func _execute(map: Map, result: ActionResult) -> bool:
	if not super(map, result):
		return false

	# Check if actor has the container
	if not actor.has_item(container):
		result.message = "You don't have that container."
		return false

	# Check if it's a container
	if not container.is_container():
		result.message = "%s isn't openable." % container.get_name(Item.NameFormat.THE)
		return false

	# Toggle the container state
	container.toggle_open()

	# Set the message
	result.message = (
		"You %s %s."
		% ["open" if container.is_open else "close", container.get_name(Item.NameFormat.THE)]
	)

	return true


func _to_string() -> String:
	return "ToggleContainerAction(actor: %s, container: %s)" % [actor, container]
