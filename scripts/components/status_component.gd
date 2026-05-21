class_name StatusComponent
extends RefCounted

# =============================================================
# ☠️ [상태이상 컴포넌트] STATUS COMPONENT
# =============================================================
# 상태이상의 추가, 제거, 틱(턴 경과), 독 피해 처리를 담당합니다.
# 기존 monster.gd의 status_effects 관련 로직 전부를 이관합니다.

var _effects: Array[StatusEffect] = []

# 부모 Monster 참조 (월드 메시지 발송, HP 접근용)
# Object 타입으로 선언해 순환 참조 파싱 오류 방지.
var _owner: Object

func _init(owner_monster: Object) -> void:
	_owner = owner_monster
	Log.d("[StatusComponent] Initialized")


func _get_owner() -> Object:
	return _owner


# =============================================================
# 🔧 [구역 1] 상태이상 조회 (QUERY)
# =============================================================

func has_effect(type: StatusEffect.Type) -> bool:
	for effect in _effects:
		if effect.type == type:
			return true
	return false


func get_effect(type: StatusEffect.Type) -> StatusEffect:
	for effect in _effects:
		if effect.type == type:
			return effect
	return null


func get_all_effects() -> Array[StatusEffect]:
	return _effects.duplicate()


# =============================================================
# ➕ [구역 2] 상태이상 추가/제거 (MUTATION)
# =============================================================

## 단순 추가 (magnitude 갱신만, duration 없음)
func add_effect(type: StatusEffect.Type, magnitude: int = 1) -> void:
	for effect in _effects:
		if effect.type == type:
			effect.magnitude = maxi(effect.magnitude, magnitude)
			return
	var effect := StatusEffect.new(type, magnitude)
	_effects.append(effect)


## 지속 시간 있는 추가 (기존 효과 교체 + stim 특수처리)
func apply_effect(type: StatusEffect.Type, turns: int, magnitude: int = 1) -> void:
	var old_effect: StatusEffect = remove_effect(type)

	if type == StatusEffect.Type.STIM:
		remove_effect(StatusEffect.Type.STIM_RECOVERY)

	var effect := StatusEffect.new(type, turns, magnitude)
	_effects.append(effect)
	Log.d("[StatusComponent] Applied effect: %s (turns=%d, mag=%d)" % [
		StatusEffect.Type.keys()[type], turns, magnitude
	])

	if type == StatusEffect.Type.STIM and old_effect:
		effect.original_turns += old_effect.original_turns


func remove_effect(type: StatusEffect.Type) -> StatusEffect:
	for i in range(_effects.size() - 1, -1, -1):
		if _effects[i].type == type:
			var effect := _effects[i]
			_effects.remove_at(i)
			return effect
	return null


# =============================================================
# ⏱️ [구역 3] 틱 처리 (TICK)
# =============================================================

func tick(owner_name: String) -> void:
	var owner: Object = _get_owner()
	var current_effects := _effects.duplicate()

	for effect: StatusEffect in current_effects:
		effect.turns_remaining -= 1
		if effect.turns_remaining <= 0:
			_effects.erase(effect)

			# Stim이 끝나면 회복 효과 추가
			if effect.type == StatusEffect.Type.STIM:
				var recovery_turns := int(effect.original_turns / 2.0)
				if recovery_turns > 0:
					apply_effect(StatusEffect.Type.STIM_RECOVERY, recovery_turns, effect.magnitude)
					if owner and owner == World.player:
						var adjective := "exhausted" if effect.magnitude == 1 else "very exhausted"
						World.message_logged.emit(
							"The stim wears off. You feel %s." % adjective,
							LogMessages.Level.BAD
						)

	# 독 피해
	if has_effect(StatusEffect.Type.POISONED) and owner:
		var owner_stats = owner.get("stats")
		if owner_stats:
			owner_stats.hp = maxi(0, owner_stats.hp - 2)
		if owner == World.player:
			World.message_logged.emit("You are poisoned!", LogMessages.Level.TERRIBLE)
		else:
			World.message_logged.emit("%s is poisoned!" % owner_name, LogMessages.Level.BAD)
