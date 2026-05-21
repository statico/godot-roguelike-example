extends BTCore
# =============================================================
# ⚔️ [전투 BT 노드] COMBAT BT NODES
# =============================================================
# 근접 공격, 원거리 공격, 지능 체크 관련 Behavior Tree 노드들.

class_name BTNodesCombat


# 인접 시 플레이어 공격
class AttackPlayer:
	extends BTCore.BTNode

	func tick(actor: Monster, map: Map) -> BTCore.Status:
		var monster_pos := map.find_monster_position(actor)
		var player_pos  := map.find_monster_position(World.player)

		if actor.is_adjacent_to(monster_pos, player_pos):
			var direction := player_pos - monster_pos
			actor.next_action = AttackMoveAction.new(actor, direction)
			Log.d("  AttackPlayer: Attacking in direction %s" % direction)
			return BTCore.Status.SUCCESS
		Log.d("  AttackPlayer: Player not adjacent")
		return BTCore.Status.FAILURE


# 원거리 무기 장착 여부 확인
class CheckHasRangedWeapon:
	extends BTCore.BTNode

	func tick(actor: Monster, _map: Map) -> BTCore.Status:
		var weapon := actor.equipment.get_equipped_item(Equipment.Slot.RANGED)
		if weapon and weapon.is_ranged_weapon():
			Log.d("  CheckHasRangedWeapon: Has ranged weapon %s" % weapon)
			return BTCore.Status.SUCCESS
		Log.d("  CheckHasRangedWeapon: No ranged weapon")
		return BTCore.Status.FAILURE


# 원거리 무기로 플레이어 사격
class FireAtPlayer:
	extends BTCore.BTNode

	func tick(actor: Monster, map: Map) -> BTCore.Status:
		var monster_pos := map.find_monster_position(actor)
		var player_pos  := map.find_monster_position(World.player)
		var distance    := monster_pos.distance_to(player_pos)

		if distance > 6:
			Log.d("  FireAtPlayer: Player too far (distance: %.1f)" % distance)
			return BTCore.Status.FAILURE

		var weapon := actor.equipment.get_equipped_item(Equipment.Slot.RANGED)
		if not weapon or not weapon.is_ranged_weapon():
			Log.d("  FireAtPlayer: No ranged weapon equipped")
			return BTCore.Status.FAILURE

		actor.next_action = FireAction.new(actor, player_pos)
		Log.d("  FireAtPlayer: Firing at player at position %s" % player_pos)
		return BTCore.Status.SUCCESS


# 근접 무기 장착 여부 확인
class CheckHasMeleeWeapon:
	extends BTCore.BTNode

	func tick(actor: Monster, _map: Map) -> BTCore.Status:
		var weapon := actor.equipment.get_equipped_item(Equipment.Slot.MELEE)
		if weapon and weapon.is_weapon() and not weapon.is_ranged_weapon():
			Log.d("  CheckHasMeleeWeapon: Has melee weapon %s" % weapon)
			return BTCore.Status.SUCCESS
		Log.d("  CheckHasMeleeWeapon: No melee weapon")
		return BTCore.Status.FAILURE


# 지능 충분 여부 확인 (무기 사용 가능 여부)
class CheckIntelligentEnough:
	extends BTCore.BTNode

	func tick(actor: Monster, _map: Map) -> BTCore.Status:
		if actor.intelligence >= 4:
			Log.d("  CheckIntelligentEnough: Intelligence sufficient (%d)" % actor.intelligence)
			return BTCore.Status.SUCCESS
		Log.d("  CheckIntelligentEnough: Intelligence too low (%d)" % actor.intelligence)
		return BTCore.Status.FAILURE
