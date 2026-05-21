extends BTCore
# =============================================================
# 🏃 [이동 BT 노드] MOVEMENT BT NODES
# =============================================================
# 이동, 도주, 랜덤 이동 관련 Behavior Tree 노드들.

class_name BTNodesMovement


# 플레이어 시야 내 확인
class CheckPlayerVisible:
	extends BTCore.BTNode

	func tick(actor: Monster, map: Map) -> BTCore.Status:
		var monster_pos := map.find_monster_position(actor)
		var player_pos  := map.find_monster_position(World.player)

		if monster_pos == Utils.INVALID_POS or player_pos == Utils.INVALID_POS:
			Log.d("  CheckPlayerVisible: Invalid position")
			return BTCore.Status.FAILURE

		var distance := (monster_pos - player_pos).length()
		var visible  := distance <= 20
		Log.d("  CheckPlayerVisible: Player %s (distance: %.1f)" % [
			"visible" if visible else "not visible", distance
		])
		return BTCore.Status.SUCCESS if visible else BTCore.Status.FAILURE


# 플레이어에게 적대적인지 확인
class CheckHostileToPlayer:
	extends BTCore.BTNode

	func tick(actor: Monster, _map: Map) -> BTCore.Status:
		if actor.is_hostile_to(World.player):
			Log.d("  CheckHostileToPlayer: Monster is hostile")
			return BTCore.Status.SUCCESS
		Log.d("  CheckHostileToPlayer: Monster is not hostile")
		return BTCore.Status.FAILURE


# 플레이어 방향으로 이동
class MoveTowardPlayer:
	extends BTCore.BTNode

	func tick(actor: Monster, map: Map) -> BTCore.Status:
		var monster_pos := map.find_monster_position(actor)
		var player_pos  := map.find_monster_position(World.player)

		var move_dir := actor.get_next_step_towards_player(map, monster_pos, player_pos, true)
		if move_dir == Vector2i.ZERO and not actor.is_adjacent_to(monster_pos, player_pos):
			move_dir = actor.get_next_step_towards_player(map, monster_pos, player_pos, false)

		if move_dir != Vector2i.ZERO:
			actor.next_action = MoveAction.new(actor, move_dir)
			Log.d("  MoveTowardPlayer: Moving toward player in direction %s" % move_dir)
			return BTCore.Status.SUCCESS
		Log.d("  MoveTowardPlayer: No valid path to player")
		return BTCore.Status.FAILURE


# 플레이어로부터 도주
class FleeFromPlayer:
	extends BTCore.BTNode

	func tick(actor: Monster, map: Map) -> BTCore.Status:
		var monster_pos := map.find_monster_position(actor)
		var player_pos  := map.find_monster_position(World.player)

		var away_dir := Vector2(monster_pos - player_pos).normalized()
		var move_dir := actor.get_safe_move_direction(map, monster_pos, away_dir)
		if move_dir != Vector2i.ZERO:
			actor.next_action = AttackMoveAction.new(actor, move_dir)
			Log.d("  FleeFromPlayer: Fleeing in direction %s" % move_dir)
			return BTCore.Status.SUCCESS
		Log.d("  FleeFromPlayer: No valid escape direction")
		return BTCore.Status.FAILURE


# 랜덤 방향으로 이동
class MoveRandomly:
	extends BTCore.BTNode

	func tick(actor: Monster, _map: Map) -> BTCore.Status:
		var move_dir := Utils.ALL_DIRECTIONS.pick_random() as Vector2i
		actor.next_action = AttackMoveAction.new(actor, move_dir)
		Log.d("  MoveRandomly: Moving in direction %s" % move_dir)
		return BTCore.Status.SUCCESS


# 랜덤 확률 체크
class CheckRandomChance:
	extends BTCore.BTNode
	var chance: float

	func _init(p_chance: float) -> void:
		chance = Utils.to_float(p_chance)

	func tick(_actor: Monster, _map: Map) -> BTCore.Status:
		var success := Dice.chance(chance)
		Log.d("  CheckRandomChance: chance %.2f, success: %s" % [chance, success])
		return BTCore.Status.SUCCESS if success else BTCore.Status.FAILURE
