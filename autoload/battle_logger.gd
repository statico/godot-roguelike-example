extends Node

# =============================================================
# 📊 [BattleLogger] 배틀로그 기록 및 RL 데이터 수출기
# =============================================================
# 캠페인(런) 단위로 전투 이벤트를 기록하고,
# 게임 종료(사망/탈출) 시 JSON으로 내보낸다.
#
# 현저성(salience) 점수는 섀넌 정보이론 기반:
# 낮은 확률의 사건 = 높은 정보량 = 높은 현저성.
# nanoGPT 파인튜닝 시 salience를 샘플링 가중치로 활용한다.
# =============================================================

const MAX_EVENTS := 10_000

var _events: Array[Dictionary] = []
var _turn: int = 0
var _active: bool = false


func _ready() -> void:
	EventBus.monster_damaged.connect(_on_damaged)
	EventBus.monster_killed.connect(_on_killed)
	EventBus.melee_attack_made.connect(_on_melee)
	EventBus.action_executed.connect(_on_action_executed)
	World.world_initialized.connect(_on_world_initialized)
	World.turn_ended.connect(_on_turn_ended)
	World.game_ended.connect(_on_game_ended)


# =============================================================
# 🔌 이벤트 핸들러
# =============================================================

func _on_world_initialized() -> void:
	_events.clear()
	_turn = 0
	_active = true
	Log.i("[BattleLogger] Campaign started — recording events")


func _on_turn_ended() -> void:
	_turn += 1


func _on_damaged(attacker: Monster, target: Monster, damage: int, damage_type: int) -> void:
	if not _active or _events.size() >= MAX_EVENTS:
		return

	var hp_after := float(target.hp) / maxf(1.0, target.max_hp)
	# 최대 HP 대비 피해 비율 = 기본 현저성
	var salience := minf(1.0, float(damage) / maxf(1.0, target.max_hp))
	# 피격 후 HP가 위험 구간이면 현저성 추가 상승
	if hp_after < 0.25:
		salience = maxf(salience, 0.7)

	_record({
		"t":    _turn,
		"ev":   "dmg",
		"src":  attacker.slug if attacker else &"env",
		"tgt":  target.slug,
		"dmg":  damage,
		"dt":   damage_type,
		"hp_r": snappedf(hp_after, 0.01),
		"sal":  snappedf(salience, 0.01),
	})


func _on_killed(killer: Monster, victim: Monster) -> void:
	if not _active:
		return

	var salience := 0.5
	# 플레이어 사망 = 최고 현저성
	if victim == World.player:
		salience = 1.0
	# 아군 사망
	elif EntityManager.is_ally(victim):
		salience = 0.75
	# 플레이어가 고XP 적 처치 = 인상적인 사건
	elif killer == World.player and victim.xp_reward > 0:
		salience = maxf(salience, minf(0.9, float(victim.xp_reward) / 200.0))

	_record({
		"t":   _turn,
		"ev":  "kill",
		"src": killer.slug if killer else &"env",
		"tgt": victim.slug,
		"xp":  victim.xp_reward,
		"sal": snappedf(salience, 0.01),
	})


func _on_melee(attacker: Monster, target: Monster) -> void:
	if not _active:
		return
	# 플레이어/아군의 근접 공격만 기록 (적군끼리 싸우는 건 저현저성)
	if not (attacker == World.player or EntityManager.is_ally(attacker)):
		return

	_record({
		"t":   _turn,
		"ev":  "melee",
		"src": attacker.slug,
		"tgt": target.slug,
		"sal": 0.1,
	})


func _on_action_executed(
	actor: Monster, cost: int, action_name: String, success: bool, budget: Dictionary
) -> void:
	if not _active or _events.size() >= MAX_EVENTS:
		return

	# 행동 추적 이벤트 — LLM 학습용 핵심 데이터
	# 실패한 행동도 기록 (왜 못 했는지 컨텍스트)
	var cost_name: String = ActionBudget.Cost.keys()[cost] if cost < ActionBudget.Cost.size() else "?"
	_record({
		"t":      _turn,
		"ev":     "act",
		"actor":  actor.slug,
		"cost":   cost_name,         # "ACTION" / "BONUS" / "MOVE" / "FREE"
		"action": action_name,       # "MeleeAction" / "FireAction" 등
		"ok":     success,
		"budget": budget,            # 행동 후 남은 예산 스냅샷
		"sal":    0.05,              # 기본 현저성 낮음 (행동 자체는 흔함)
	})


func _on_game_ended() -> void:
	if not _active:
		return
	_active = false
	_export()


# =============================================================
# 🗃️ 내부 유틸
# =============================================================

func _record(entry: Dictionary) -> void:
	_events.append(entry)


func _export() -> void:
	if _events.is_empty():
		Log.i("[BattleLogger] No events to export")
		return

	var path := "user://battle_log_%d.json" % int(Time.get_unix_time_from_system())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if not f:
		Log.e("[BattleLogger] Failed to open %s for writing" % path)
		return

	f.store_string(JSON.stringify(_events, "\t"))
	Log.i("[BattleLogger] Exported %d events → %s" % [_events.size(), path])
