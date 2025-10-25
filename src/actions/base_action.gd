class_name BaseAction
extends RefCounted


func apply(map: Map) -> ActionResult:
	var result := ActionResult.new()
	result.success = _execute(map, result)
	return result


func _execute(_map: Map, _result: ActionResult) -> bool:
	return false  # Override in subclasses


func _to_string() -> String:
	return "BaseAction()"
