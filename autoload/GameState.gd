extends Node

# =============================================================
# ⚙️ [구역 1] AI 설정 (AI CONFIGURATION)
# =============================================================

## AI 행동 모드. 언제든 런타임에 토글 가능.
## "behavior_tree" = 기존 BT 로직 (안정적)
## "rl_model"      = 강화학습 ONNX 모델 (실험적)
var ai_mode: String = "behavior_tree"

## 난이도별 RL 행동 노이즈 계수 (epsilon)
## 0.0 = 완전 결정론적 / 1.0 = 완전 랜덤
const AI_DIFFICULTY_EPSILON: Dictionary = {
	"easy":   0.3,
	"normal": 0.1,
	"hard":   0.0,
}

var current_difficulty: String = "normal"

# =============================================================
# ⚔️ [구역 2] 파티 상태 (PARTY STATE)
# =============================================================

## 현재 파티 멤버 (최대 4명: 플레이어 1 + AI 3)
var party: Array = []

## 파티 마칭 오더 (Marching Order) — 포지션 [0~3]
## 포지션 0 = 선두(Tank), 3 = 후미(Ranger)
var marching_order: Array = []

# =============================================================
# 🗺️ [구역 3] 던전 상태 (DUNGEON STATE)
# =============================================================

var current_floor: int = 1
var dungeon_seed: int = 0

# =============================================================
# 📊 [구역 4] 게임 통계 (SESSION STATS)
# =============================================================

var turns_elapsed: int = 0
var monsters_defeated: int = 0
var items_collected: int = 0

# =============================================================
# 🔧 [구역 5] 초기화 (INIT)
# =============================================================

func _ready() -> void:
	print("[GameState] 초기화 완료 — AI 모드: %s, 난이도: %s" % [ai_mode, current_difficulty])

# =============================================================
# 🎮 [구역 6] 공개 API (PUBLIC API)
# =============================================================

## AI 모드 전환 (디버그 콘솔 or 설정 메뉴에서 호출)
func set_ai_mode(mode: String) -> void:
	assert(mode in ["behavior_tree", "rl_model"], "유효하지 않은 AI 모드: " + mode)
	ai_mode = mode
	print("[GameState] AI 모드 변경 → %s" % ai_mode)

## 현재 난이도의 epsilon 반환
func get_ai_epsilon() -> float:
	return AI_DIFFICULTY_EPSILON.get(current_difficulty, 0.1)

## 파티 등록
func register_party(members: Array) -> void:
	party = members
	marching_order = members.duplicate()
	print("[GameState] 파티 등록 완료 — %d명" % party.size())

## 새 던전 층 진입
func enter_floor(floor_num: int, seed_val: int = 0) -> void:
	current_floor = floor_num
	dungeon_seed  = seed_val if seed_val != 0 else randi()
	print("[GameState] %d층 진입 — 시드: %d" % [current_floor, dungeon_seed])
