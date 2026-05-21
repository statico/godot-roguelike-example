class_name BTNodesBlackhole
extends BTCore

# =============================================================
# 🕳️ [블랙홀 BT 노드] BLACKHOLE AI BT NODE
# =============================================================
# BlackholeComputer를 BT 노드로 래핑.
# 이 노드 하나가 전체 AI를 대체한다 — 블랙홀처럼.

class BlackholeDecide:
	extends BTCore.BTNode

	var _computer: BlackholeComputer
	var _actor_id: int = 0

	func _init() -> void:
		_computer = BlackholeComputer.new()

	func tick(actor: Monster, map: Map) -> BTCore.Status:
		# 첫 틱에 트레이너에 Oracle 등록
		if _actor_id == 0:
			_actor_id = actor.instance_id
			BlackholeTrainer.register(_actor_id, _computer)

		var result: Dictionary = _computer.decide(actor, map)

		# Hawking 복사가 아닌 정상 결정만 학습 데이터로 수집
		if not (result.get("cache", {}) as Dictionary).is_empty():
			BlackholeTrainer.record_step(_computer, result)

		var action: BlackholeComputer.Action = result["action"]
		var actor_action := _computer.to_actor_action(actor, map, action)

		if actor_action:
			actor.next_action = actor_action
			return BTCore.Status.SUCCESS

		return BTCore.Status.FAILURE
