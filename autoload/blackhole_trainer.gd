extends Node

# =============================================================
# 🎓 [블랙홀 트레이너] BLACKHOLE REINFORCEMENT TRAINER
# =============================================================
# D20 Oracle의 경험을 수집하고, 판 종료 시 REINFORCE로 학습합니다.
#
# 흐름:
#   BTNodesBlackhole.BlackholeDecide.tick()
#     → record_step() 호출 (매 Oracle 턴)
#   EventBus 신호 (monster_damaged, monster_killed)
#     → _add_reward() 호출 (즉시 보상)
#   EventBus.game_ended
#     → _train_all() → backward() → save_weights()
# =============================================================

const LEARNING_RATE := 0.001

# actor.instance_id (int) → BlackholeComputer
var _actor_computers: Dictionary = {}

# BlackholeComputer → Array[{cache, context, action, reward}]
var _logs: Dictionary = {}


func _ready() -> void:
	EventBus.monster_damaged.connect(_on_monster_damaged)
	EventBus.monster_killed.connect(_on_monster_killed)
	EventBus.game_ended.connect(_on_game_ended)
	Log.i("[BlackholeTrainer] 초기화 완료")


# =============================================================
# 🔗 [구역 1] 등록 / 해제
# =============================================================

func register(actor_id: int, computer: BlackholeComputer) -> void:
	_actor_computers[actor_id] = computer
	if not _logs.has(computer):
		_logs[computer] = []
	Log.d("[BlackholeTrainer] Oracle 등록: id=%d" % actor_id)


func unregister(actor_id: int) -> void:
	_actor_computers.erase(actor_id)


# =============================================================
# 📝 [구역 2] 경험 기록
# =============================================================

func record_step(computer: BlackholeComputer, result: Dictionary) -> void:
	if not _logs.has(computer):
		_logs[computer] = []
	var cache:   Dictionary = result.get("cache",   {}) as Dictionary
	var context: Array      = result.get("context", []) as Array
	var action:  int        = int(result.get("action", 0))
	(_logs[computer] as Array).append({
		"cache":   cache,
		"context": context,
		"action":  action,
		"reward":  -0.01,   # 생존 비용 (step penalty)
	})


func _add_reward(computer: BlackholeComputer, r: float) -> void:
	if not _logs.has(computer): return
	var log: Array = _logs[computer] as Array
	if log.is_empty(): return
	var last: Dictionary = log[-1] as Dictionary
	last["reward"] = (last["reward"] as float) + r


func _get_computer(actor_id: int) -> BlackholeComputer:
	if not _actor_computers.has(actor_id): return null
	return _actor_computers[actor_id] as BlackholeComputer


# =============================================================
# 📡 [구역 3] 이벤트 수신
# =============================================================

func _on_monster_damaged(attacker: Monster, target: Monster, damage: int, _damage_type: int) -> void:
	# Oracle이 데미지를 줬을 때 → 양의 보상
	if attacker != null:
		var c := _get_computer(attacker.instance_id)
		if c: _add_reward(c, 0.1 * float(damage))
	# Oracle이 데미지를 받았을 때 → 음의 보상
	var c2 := _get_computer(target.instance_id)
	if c2: _add_reward(c2, -0.1 * float(damage))


func _on_monster_killed(killer: Monster, victim: Monster) -> void:
	# Oracle이 플레이어를 처치 → 큰 양의 보상
	if killer != null and victim == World.player:
		var c := _get_computer(killer.instance_id)
		if c: _add_reward(c, 10.0)
	# Oracle이 죽었을 때 → 큰 음의 보상
	var c2 := _get_computer(victim.instance_id)
	if c2: _add_reward(c2, -5.0)


func _on_game_ended(_reason: String) -> void:
	_train_all()


# =============================================================
# 🏋️ [구역 4] 학습 (판 종료 시 Monte Carlo REINFORCE)
# =============================================================

func _train_all() -> void:
	for key in _logs.keys():
		var computer: BlackholeComputer = key as BlackholeComputer
		var log: Array = _logs[key] as Array
		if log.is_empty(): continue

		# Monte Carlo Return 역방향 누적
		var G := 0.0
		for i in range(log.size() - 1, -1, -1):
			var exp: Dictionary = log[i] as Dictionary
			G = (exp["reward"] as float) + BlackholeComputer.DISCOUNT * G
			var cache:   Dictionary = exp["cache"]   as Dictionary
			var context: Array      = exp["context"] as Array
			var action:  int        = exp["action"]  as int
			# Hawking 복사(캐시 없음)는 학습 제외
			if not cache.is_empty() and not context.is_empty():
				computer.backward(cache, context, action, G, LEARNING_RATE)

		computer.save_weights()
		Log.i("[BlackholeTrainer] 학습 완료 — %d 경험 처리" % log.size())

	_logs.clear()
	_actor_computers.clear()
