class_name MonsterAI
extends RefCounted

# =============================================================
# 🤖 [MonsterAI] Facade (하위 호환 래퍼)
# =============================================================
# 실제 구현은 scripts/ai/bt/ 하위 파일들로 이전됐습니다.
# 기존 코드가 MonsterAI.BTNode, MonsterAI.BTStatus,
# MonsterAI.create_behavior_tree() 를 참조하므로 여기서 재노출합니다.
#
# 실제 BT 시스템:
#   BTCore            → scripts/ai/bt/bt_core.gd
#   BTNodesMovement   → scripts/ai/bt/bt_nodes_movement.gd
#   BTNodesCombat     → scripts/ai/bt/bt_nodes_combat.gd
#   BTNodesInventory  → scripts/ai/bt/bt_nodes_inventory.gd
#   BTTrees           → scripts/ai/bt/bt_trees.gd

# --- 하위 호환 타입 별칭 ---
const BTStatus = BTCore.Status   # MonsterAI.BTStatus.SUCCESS 등 기존 코드 유지
const BTNode   = BTCore.BTNode   # MonsterAI.BTNode 타입 기존 코드 유지


# --- 하위 호환 팩토리 함수 ---
static func create_behavior_tree(monster: Monster) -> BTCore.BTNode:
	Log.d("[MonsterAI] Creating behavior tree for %s (behavior: %s)" % [
		monster.name,
		Monster.Behavior.keys()[monster.behavior]
	])
	return BTTrees.create(monster)


# --- DSL 헬퍼 재노출 (party_ai.gd 등에서 사용 가능) ---
static func sequence(
	a: Variant, b: Variant = null, c: Variant = null,
	d: Variant = null, e: Variant = null, f: Variant = null
) -> BTCore.BTNode:
	return BTCore.sequence(a, b, c, d, e, f)


static func selector(
	a: Variant, b: Variant = null, c: Variant = null,
	d: Variant = null, e: Variant = null, f: Variant = null
) -> BTCore.BTNode:
	return BTCore.selector(a, b, c, d, e, f)
