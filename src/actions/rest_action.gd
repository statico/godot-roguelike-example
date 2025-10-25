class_name RestAction
extends ActorAction


func _execute(_map: Map, result: ActionResult) -> bool:
	if not super(_map, result):
		return false

	# Rest is always successful
	result.message = "%s rests for a moment..." % actor
	return true


func _to_string() -> String:
	return "RestAction(actor: %s)" % actor
