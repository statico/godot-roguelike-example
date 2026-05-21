class_name ActorAction
extends BaseAction

var actor: Monster


func _init(p_actor: Monster) -> void:
	action_cost = ActionBudget.Cost.ACTION
	actor = p_actor


func _execute(_map: Map, _result: ActionResult) -> bool:
	if not actor:
		return false
	return true


func _to_string() -> String:
	return "ActorAction(actor: %s)" % actor
