class_name SecondWindAction
extends ActorAction

# =============================================================
# 💨 [세컨드 윈드] SECOND WIND
# =============================================================
# 파이터 1레벨 특성.
# 보너스 액션: 1d10 + 레벨 HP 회복. 단휴식/장휴식으로 충전.
# =============================================================

func _init(p_actor: Monster) -> void:
	super(p_actor)
	action_cost = ActionBudget.Cost.BONUS


func _execute(_map: Map, _result: ActionResult) -> bool:
	if not actor:
		return false
	if actor.class_comp.class_type != ClassComponent.Type.FIGHTER:
		return false

	var healed := actor.class_comp.use_second_wind()
	if healed < 0:
		Log.d("[SecondWind] 이미 사용됨 — 단휴식 필요")
		return false

	actor.hp = mini(actor.max_hp, actor.hp + healed)
	Log.i("[SecondWind] %s → +%d HP (%d/%d)" % [
		actor.get_name(Monster.NameFormat.THE), healed, actor.hp, actor.max_hp
	])
	return true


func _to_string() -> String:
	return "SecondWindAction(actor: %s)" % actor
