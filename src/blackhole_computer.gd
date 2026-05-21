class_name BlackholeComputer
extends RefCounted

# =============================================================
# 🕳️ [D20 블랙홀 컴퓨터] D20 BLACK HOLE COMPUTER
# =============================================================
# nanoGPT(Self-Attention) + brain.js(MLP) 하이브리드
# + REINFORCE 정책 경사 학습 (판당 Monte Carlo Returns)
#
# 학습 사이클:
#   판 플레이 중   → 경험(state, action, reward) 수집
#   판 종료 시     → Monte Carlo Return 계산
#   역전파         → MLP + Attention 가중치 업데이트
#   가중치 저장    → 다음 판에 로드
# =============================================================

const D20      := 20
const FACES    := 12   # 컨텍스트 윈도우 = 정12면체 면 수
const INPUT_N  := 8
const OUTPUT_N := 6
const HEAD_DIM := 8

const DEMON_THRESHOLD  := 0.4
const HAWKING_THRESHOLD := 1.0
const WEIGHT_PATH      := "user://d20_oracle_weights.json"
const DISCOUNT         := 0.95  # Monte Carlo 할인율

enum Action { IDLE, MOVE_TOWARD, MOVE_AWAY, MELEE_ATTACK, RANGED_ATTACK, MOVE_RANDOM }

# ── Attention 가중치 ──────────────────────────────────────────
var _w_q:    Array   # [INPUT_N][HEAD_DIM]
var _w_k:    Array   # [INPUT_N][HEAD_DIM]
var _w_v:    Array   # [INPUT_N][HEAD_DIM]
var _w_proj: Array   # [HEAD_DIM][INPUT_N]

# ── MLP 가중치 (brain.js) ──────────────────────────────────────
var _w_ih: Array     # [INPUT_N][FACES]
var _w_ho: Array     # [FACES][OUTPUT_N]
var _b_h:  Array[float]
var _b_o:  Array[float]

# ── 상태 ──────────────────────────────────────────────────────
var _context:        Array = []
var _time_phase:     int   = 0
var _hawking_energy: float = 0.0


func _init() -> void:
	if not load_weights():
		_init_weights_d20()
		Log.i("[D20 BHC] 새 가중치 초기화 (D20)")
	else:
		Log.i("[D20 BHC] 저장된 가중치 로드 완료")


# =============================================================
# 🎲 [구역 1] 초기화
# =============================================================

func _init_weights_d20() -> void:
	_w_q    = _make_matrix(INPUT_N, HEAD_DIM)
	_w_k    = _make_matrix(INPUT_N, HEAD_DIM)
	_w_v    = _make_matrix(INPUT_N, HEAD_DIM)
	_w_proj = _make_matrix(HEAD_DIM, INPUT_N)
	_w_ih   = _make_matrix(INPUT_N, FACES)
	_w_ho   = _make_matrix(FACES, OUTPUT_N)
	_b_h    = _make_bias(FACES)
	_b_o    = _make_bias(OUTPUT_N)


func _make_matrix(rows: int, cols: int) -> Array:
	var m := []
	for _i in rows:
		var row: Array[float] = []
		for _j in cols:
			row.append(_d20_to_weight(randi_range(1, D20)))
		m.append(row)
	return m


func _make_bias(size: int) -> Array[float]:
	var b: Array[float] = []
	for _i in size:
		b.append(_d20_to_weight(randi_range(1, D20)))
	return b


func _d20_to_weight(roll: int) -> float:
	return (float(roll) / float(D20)) * 2.0 - 1.0


# =============================================================
# 🔢 [구역 2] 수학 유틸
# =============================================================

func _sigmoid(x: float) -> float:
	return 1.0 / (1.0 + exp(-x))


func _sigmoid_d(y: float) -> float:  # sigmoid'(x) = y(1-y), y=sigmoid(x)
	return y * (1.0 - y)


func _softmax(x: Array) -> Array[float]:
	var mx: float = x[0]
	for v: float in x:
		if v > mx: mx = v
	var exps: Array[float] = []
	var total := 0.0
	for v: float in x:
		var e := exp(v - mx); exps.append(e); total += e
	var r: Array[float] = []
	for e in exps: r.append(e / total)
	return r


func _linear(x: Array, w: Array, b: Array) -> Array[float]:
	var out_dim := (w[0] as Array).size()
	var result: Array[float] = []
	for j in out_dim:
		var s: float = b[j] if b.size() > j else 0.0
		for i in x.size():
			s += (x[i] as float) * ((w[i] as Array)[j] as float)
		result.append(s)
	return result


func _dot(a: Array, b: Array) -> float:
	var s := 0.0
	for i in a.size(): s += (a[i] as float) * (b[i] as float)
	return s


# =============================================================
# 🤖 [구역 3] 순전파 (캐시 포함)
# =============================================================

## 순전파 결과 + 학습에 필요한 중간값 모두 반환
func forward_with_cache(state: Array[float]) -> Dictionary:
	var T := _context.size()
	var scale := sqrt(float(HEAD_DIM))

	# ── Attention ──────────────────────────────────────────────
	var Q := []; var K := []; var V := []
	for t in T:
		Q.append(_linear(_context[t], _w_q, []))
		K.append(_linear(_context[t], _w_k, []))
		V.append(_linear(_context[t], _w_v, []))

	var q_last: Array = Q[T - 1]
	var raw_scores: Array[float] = []
	for t in T:
		raw_scores.append(_dot(q_last, K[t]) / scale)

	var attn: Array[float] = _softmax(raw_scores)

	# 가중합 → 컨텍스트 표현
	var ctx_vec: Array[float] = []
	for _i in HEAD_DIM: ctx_vec.append(0.0)
	for t in T:
		for i in HEAD_DIM:
			ctx_vec[i] += attn[t] * ((V[t] as Array)[i] as float)

	var proj_out: Array[float] = _linear(ctx_vec, _w_proj, [])

	# ── MLP ────────────────────────────────────────────────────
	var hidden: Array[float] = []
	for j in FACES:
		var s := _b_h[j]
		for i in INPUT_N: s += proj_out[i] * (_w_ih[i] as Array)[j]
		hidden.append(_sigmoid(s))

	var output: Array[float] = []
	for k in OUTPUT_N:
		var s := _b_o[k]
		for j in FACES: s += hidden[j] * (_w_ho[j] as Array)[k]
		output.append(_sigmoid(s))

	return {
		"output":   output,
		"hidden":   hidden,
		"proj_out": proj_out,
		"ctx_vec":  ctx_vec,
		"attn":     attn,
		"Q": Q, "K": K, "V": V,
		"q_last":   q_last,
		"scale":    scale,
	}


# =============================================================
# 📐 [구역 4] 역전파 (REINFORCE)
# =============================================================
# G = Monte Carlo Return (할인된 미래 보상 합계)
# 정책 경사: 좋은 행동은 확률 ↑, 나쁜 행동은 확률 ↓

func backward(
	cache:   Dictionary,
	context: Array,     # 이 경험의 컨텍스트 스냅샷
	action:  int,
	G:       float,
	lr:      float
) -> void:
	var output:   Array = cache["output"]
	var hidden:   Array = cache["hidden"]
	var proj_out: Array = cache["proj_out"]
	var ctx_vec:  Array = cache["ctx_vec"]
	var attn:     Array = cache["attn"]
	var Q: Array        = cache["Q"]
	var K: Array        = cache["K"]
	var V: Array        = cache["V"]
	var q_last: Array   = cache["q_last"]
	var scale:  float   = cache["scale"]
	var T := context.size()

	# ── 1. 출력층 기울기 (REINFORCE 정책 경사) ─────────────────
	var delta_o: Array[float] = []
	for k in OUTPUT_N:
		# 선택한 행동 쪽으로, Return 크기만큼 밀기
		var target := 1.0 if k == action else 0.0
		delta_o.append(G * (target - (output[k] as float)) * _sigmoid_d(output[k] as float))

	# ── 2. MLP 가중치 업데이트 ─────────────────────────────────
	# W_ho, b_o
	for j in FACES:
		for k in OUTPUT_N:
			(_w_ho[j] as Array)[k] = (_w_ho[j] as Array)[k] + lr * (hidden[j] as float) * delta_o[k]
	for k in OUTPUT_N:
		_b_o[k] = _b_o[k] + lr * delta_o[k]

	# 은닉층 기울기
	var delta_h: Array[float] = []
	for j in FACES:
		var grad := 0.0
		for k in OUTPUT_N: grad += delta_o[k] * (_w_ho[j] as Array)[k]
		delta_h.append(grad * _sigmoid_d(hidden[j] as float))

	# W_ih, b_h
	for i in INPUT_N:
		for j in FACES:
			(_w_ih[i] as Array)[j] = (_w_ih[i] as Array)[j] + lr * (proj_out[i] as float) * delta_h[j]
	for j in FACES:
		_b_h[j] = _b_h[j] + lr * delta_h[j]

	# ── 3. Attention 역전파 ────────────────────────────────────
	# MLP 입력(proj_out)에 대한 기울기
	var d_proj: Array[float] = []
	for i in INPUT_N:
		var g := 0.0
		for j in FACES: g += delta_h[j] * (_w_ih[i] as Array)[j]
		d_proj.append(g)

	# W_proj 업데이트
	for i in HEAD_DIM:
		for j in INPUT_N:
			(_w_proj[i] as Array)[j] = (_w_proj[i] as Array)[j] + lr * (ctx_vec[i] as float) * d_proj[j]

	# ctx_vec에 대한 기울기
	var d_ctx: Array[float] = []
	for i in HEAD_DIM:
		var g := 0.0
		for j in INPUT_N: g += d_proj[j] * (_w_proj[i] as Array)[j]
		d_ctx.append(g)

	# V에 대한 기울기: d_V[t] = attn[t] * d_ctx
	# attn weight에 대한 기울기: d_attn[t] = dot(d_ctx, V[t])
	var d_attn: Array[float] = []
	for t in T:
		d_attn.append(_dot(d_ctx, V[t]))

	# Softmax 역전파: d_scores[t] = attn[t] * (d_attn[t] - dot(attn, d_attn))
	var attn_dot_d := _dot(attn, d_attn)
	var d_scores: Array[float] = []
	for t in T:
		d_scores.append((attn[t] as float) * (d_attn[t] - attn_dot_d))

	# Q, K 기울기 → W_q, W_k 업데이트
	for t in T:
		var ds := d_scores[t] / scale
		# d_K[t] = ds * q_last → W_k 업데이트
		for i in INPUT_N:
			for h in HEAD_DIM:
				(_w_k[i] as Array)[h] = (_w_k[i] as Array)[h] + \
					lr * (context[t] as Array)[i] * (q_last[h] as float) * ds
		# d_q_last += ds * K[t] → W_q 업데이트 (마지막 토큰 기준)
		for i in INPUT_N:
			for h in HEAD_DIM:
				(_w_q[i] as Array)[h] = (_w_q[i] as Array)[h] + \
					lr * (context[T-1] as Array)[i] * (K[t] as Array)[h] * ds

	# W_v 업데이트
	for t in T:
		var a := attn[t] as float
		for i in INPUT_N:
			for h in HEAD_DIM:
				(_w_v[i] as Array)[h] = (_w_v[i] as Array)[h] + \
					lr * (context[t] as Array)[i] * d_ctx[h] * a


# =============================================================
# 💾 [구역 5] 가중치 저장 / 로드
# =============================================================

func save_weights() -> void:
	var data := {
		"w_q": _w_q, "w_k": _w_k, "w_v": _w_v, "w_proj": _w_proj,
		"w_ih": _w_ih, "w_ho": _w_ho, "b_h": _b_h, "b_o": _b_o,
	}
	var f := FileAccess.open(WEIGHT_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		Log.i("[D20 BHC] 가중치 저장 → %s" % WEIGHT_PATH)


func load_weights() -> bool:
	if not FileAccess.file_exists(WEIGHT_PATH):
		return false
	var f := FileAccess.open(WEIGHT_PATH, FileAccess.READ)
	if not f:
		return false
	var result := JSON.parse_string(f.get_as_text())
	if not result is Dictionary:
		return false
	var d: Dictionary = result
	_w_q    = d.get("w_q",    [])
	_w_k    = d.get("w_k",    [])
	_w_v    = d.get("w_v",    [])
	_w_proj = d.get("w_proj", [])
	_w_ih   = d.get("w_ih",   [])
	_w_ho   = d.get("w_ho",   [])
	_b_h    = d.get("b_h",    [])
	_b_o    = d.get("b_o",    [])
	return (_w_ih.size() == INPUT_N)


# =============================================================
# 😈 [구역 6] 맥스웰의 악마 + 호킹 복사
# =============================================================

func _surprise(p: float) -> float:
	return -log(maxf(p, 0.0001)) / log(2.0)


func _maxwell_demon(output: Array[float]) -> Action:
	var best := -1.0
	var chosen: Action = Action.IDLE
	for k in output.size():
		var s := _surprise(output[k])
		if s > DEMON_THRESHOLD and s > best:
			best = s; chosen = k as Action
	Log.d("[D20 BHC] 악마 → %s (서프라이즈=%.3f, 위상=%d)" % [
		Action.keys()[chosen], best, _time_phase])
	return chosen


func _hawking_check() -> int:
	_hawking_energy += randf_range(0.05, 0.2)
	if _hawking_energy >= HAWKING_THRESHOLD:
		_hawking_energy = 0.0
		var r := randi_range(0, OUTPUT_N - 1)
		Log.i("[D20 BHC] ☢ 호킹 복사 → %s" % Action.keys()[r])
		return r
	return -1


# =============================================================
# 🌌 [구역 7] 상태 인코딩
# =============================================================

func encode(actor: Monster, map: Map) -> Array[float]:
	var plyr      := World.player
	var actor_pos := map.find_monster_position(actor)
	var plyr_pos  := map.find_monster_position(plyr)
	var dist := 10.0
	if actor_pos != Utils.INVALID_POS and plyr_pos != Utils.INVALID_POS:
		dist = actor_pos.distance_to(plyr_pos)
	return [
		float(actor.hp)  / maxf(1.0, actor.max_hp),
		float(plyr.hp)   / maxf(1.0, plyr.max_hp),
		clampf(dist / 12.0, 0.0, 1.0),
		1.0 if actor.equipment.get_equipped_item(Equipment.Slot.RANGED) else 0.0,
		1.0 if actor.equipment.get_equipped_item(Equipment.Slot.MELEE)  else 0.0,
		float(_time_phase) / float(FACES),
		1.0 if map.is_visible(plyr_pos) else 0.0,
		_hawking_energy,
	]


# =============================================================
# 🎯 [구역 8] 메인 결정 함수
# =============================================================

func decide(actor: Monster, map: Map) -> Dictionary:
	_time_phase = (_time_phase + 1) % FACES

	var hawking := _hawking_check()
	if hawking >= 0:
		return {"action": hawking as Action, "cache": {}, "context": [], "state": []}

	var state   := encode(actor, map)
	_context.append(state)
	if _context.size() > FACES: _context.pop_front()

	var cache := forward_with_cache(state)
	var action := _maxwell_demon(cache["output"])

	return {
		"action":  action,
		"cache":   cache,
		"context": _context.duplicate(),  # 학습용 스냅샷
		"state":   state,
	}


# =============================================================
# 🔧 [구역 9] Action → ActorAction
# =============================================================

func to_actor_action(actor: Monster, map: Map, action: Action) -> ActorAction:
	var ap := map.find_monster_position(actor)
	var pp := map.find_monster_position(World.player)
	if ap == Utils.INVALID_POS or pp == Utils.INVALID_POS: return null
	match action:
		Action.IDLE:         return null
		Action.MOVE_TOWARD, Action.MELEE_ATTACK:
			var dir := actor.get_next_step_towards_player(map, ap, pp)
			return AttackMoveAction.new(actor, dir) if dir != Vector2i.ZERO else null
		Action.MOVE_AWAY:
			var away := ap - pp
			var dir  := Vector2i(sign(away.x), sign(away.y))
			if dir == Vector2i.ZERO: dir = Utils.ALL_DIRECTIONS.pick_random()
			return MoveAction.new(actor, dir)
		Action.RANGED_ATTACK:
			var weapon := actor.equipment.get_equipped_item(Equipment.Slot.RANGED)
			if weapon and weapon.is_ranged_weapon(): return FireAction.new(actor, pp)
			var dir := actor.get_next_step_towards_player(map, ap, pp)
			return AttackMoveAction.new(actor, dir) if dir != Vector2i.ZERO else null
		Action.MOVE_RANDOM:
			return MoveAction.new(actor, Utils.ALL_DIRECTIONS.pick_random())
	return null
