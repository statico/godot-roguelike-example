class_name BaseAction
extends RefCounted

## 이 행동이 소모하는 행동 토큰 종류.
## 서브클래스에서 오버라이드하여 선언.
var action_cost: ActionBudget.Cost = ActionBudget.Cost.FREE


func apply(map: Map) -> ActionResult:
	var result := ActionResult.new()
	result.success = _execute(map, result)
	return result


func _execute(_map: Map, _result: ActionResult) -> bool:
	return false  # Override in subclasses


func _to_string() -> String:
	return "BaseAction()"
