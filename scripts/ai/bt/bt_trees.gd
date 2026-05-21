class_name BTTrees
extends RefCounted

# =============================================================
# 🌳 [BT 트리 팩토리] BEHAVIOR TREE FACTORY
# =============================================================
# Monster.Behavior에 따른 행동 트리를 생성합니다.
# 새로운 Behavior 타입 추가 시 이 파일만 수정하면 됩니다.
#
# 의존 노드 클래스:
#   BTCore            (bt_core.gd)
#   BTNodesMovement   (bt_nodes_movement.gd)
#   BTNodesCombat     (bt_nodes_combat.gd)
#   BTNodesInventory  (bt_nodes_inventory.gd)

# --- 편의를 위한 타입 별칭 ---
const S   = BTCore.Status


# --- Movement 노드 별칭 ---
const CheckPlayerVisible  = BTNodesMovement.CheckPlayerVisible
const CheckHostileToPlayer = BTNodesMovement.CheckHostileToPlayer
const MoveTowardPlayer    = BTNodesMovement.MoveTowardPlayer
const FleeFromPlayer      = BTNodesMovement.FleeFromPlayer
const MoveRandomly        = BTNodesMovement.MoveRandomly
const CheckRandomChance   = BTNodesMovement.CheckRandomChance

# --- Combat 노드 별칭 ---
const AttackPlayer          = BTNodesCombat.AttackPlayer
const CheckHasRangedWeapon  = BTNodesCombat.CheckHasRangedWeapon
const FireAtPlayer          = BTNodesCombat.FireAtPlayer
const CheckHasMeleeWeapon   = BTNodesCombat.CheckHasMeleeWeapon
const CheckIntelligentEnough = BTNodesCombat.CheckIntelligentEnough

# --- Inventory 노드 별칭 ---
const FindNearbyMeleeWeapon     = BTNodesInventory.FindNearbyMeleeWeapon
const MoveToAndPickupWeapon     = BTNodesInventory.MoveToAndPickupWeapon
const EquipMeleeWeapon          = BTNodesInventory.EquipMeleeWeapon
const CheckAndEquipRangedWeapon = BTNodesInventory.CheckAndEquipRangedWeapon
const DoNothing                 = BTCore.DoNothing


# =============================================================
# 🔧 [구역 1] 트리 생성 (TREE FACTORY)
# =============================================================

static func create(monster: Monster) -> BTCore.BTNode:
	match monster.behavior:
		Monster.Behavior.AGGRESSIVE:
			return _create_aggressive()
		Monster.Behavior.FEARFUL:
			return _create_fearful()
		Monster.Behavior.CURIOUS:
			return _create_curious()
		Monster.Behavior.PASSIVE:
			return _create_passive()
		Monster.Behavior.BLACKHOLE_AI:
			return _create_blackhole()
		_:
			assert(false, "Invalid behavior: %s" % monster.behavior)
			return BTCore.BTNode.new()


# =============================================================
# 🔧 [구역 2] 개별 트리 정의 (TREE DEFINITIONS)
# =============================================================

static func _create_aggressive() -> BTCore.BTNode:
	return BTCore.sequence(
		BTCore.selector(
			# 적대 + 시야 확보 시 전투
			BTCore.sequence(
				CheckHostileToPlayer,
				CheckPlayerVisible,
				BTCore.selector(
					# 원거리 우선
					BTCore.sequence(
						CheckAndEquipRangedWeapon,
						CheckHasRangedWeapon,
						BTCore.selector(FireAtPlayer, MoveTowardPlayer)
					),
					# 근접 + 무기 탐색
					BTCore.sequence(
						CheckIntelligentEnough,
						BTCore.selector(
							CheckHasMeleeWeapon,
							EquipMeleeWeapon,
							BTCore.sequence(FindNearbyMeleeWeapon, MoveToAndPickupWeapon)
						),
						BTCore.selector(AttackPlayer, MoveTowardPlayer)
					),
					# 기본 근접
					BTCore.sequence(BTCore.selector(AttackPlayer, MoveTowardPlayer))
				)
			),
			# 비적대 시 랜덤 이동
			BTCore.sequence(CheckRandomChance.new(0.5), MoveRandomly),
			DoNothing
		)
	)


static func _create_fearful() -> BTCore.BTNode:
	return BTCore.sequence(
		CheckPlayerVisible,
		FleeFromPlayer,
		DoNothing
	)


static func _create_curious() -> BTCore.BTNode:
	return BTCore.sequence(
		CheckPlayerVisible,
		BTCore.selector(MoveTowardPlayer)
	)


static func _create_passive() -> BTCore.BTNode:
	return BTCore.sequence(
		BTCore.selector(
			BTCore.sequence(CheckRandomChance.new(0.5), MoveRandomly),
			DoNothing
		)
	)


static func _create_blackhole() -> BTCore.BTNode:
	# 블랙홀 컴퓨터 단일 노드 — BT 전체를 대체
	return BTCore.sequence(BTNodesBlackhole.BlackholeDecide.new())
