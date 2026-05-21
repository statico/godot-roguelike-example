extends BTCore
# =============================================================
# 🎒 [인벤토리 BT 노드] INVENTORY BT NODES
# =============================================================
# 무기 탐색, 장착, 이동-습득 관련 Behavior Tree 노드들.

class_name BTNodesInventory


# 근처 근접 무기 탐색 (위치를 static 변수에 저장)
class FindNearbyMeleeWeapon:
	extends BTCore.BTNode

	# 발견한 무기 위치를 공유 (MoveToAndPickupWeapon이 사용)
	static var weapon_location: Vector2i = Utils.INVALID_POS
	static var weapon_distance: float    = 999999.0

	func tick(actor: Monster, map: Map) -> BTCore.Status:
		var monster_pos := map.find_monster_position(actor)

		weapon_location = Utils.INVALID_POS
		weapon_distance = 999999.0

		# 현재 위치 먼저 확인
		for item in map.get_items(monster_pos):
			if item.is_weapon() and not item.is_ranged_weapon():
				Log.d("  FindNearbyMeleeWeapon: Found at current position: %s" % item)
				weapon_location = monster_pos
				weapon_distance = 0.0
				return BTCore.Status.SUCCESS

		# 시야 반경 내 탐색
		for y in range(-actor.sight_radius, actor.sight_radius + 1):
			for x in range(-actor.sight_radius, actor.sight_radius + 1):
				var check_pos := monster_pos + Vector2i(x, y)
				if not map.is_in_bounds(check_pos) or not map.is_visible(check_pos):
					continue
				var distance := monster_pos.distance_to(check_pos)
				if distance > actor.sight_radius:
					continue
				for item in map.get_items(check_pos):
					if item.is_weapon() and not item.is_ranged_weapon():
						if distance < weapon_distance:
							weapon_distance = distance
							weapon_location = check_pos

		if weapon_location != Utils.INVALID_POS:
			Log.d("  FindNearbyMeleeWeapon: Found at %s (distance: %.1f)" % [
				weapon_location, weapon_distance
			])
			return BTCore.Status.SUCCESS

		Log.d("  FindNearbyMeleeWeapon: No nearby melee weapons found")
		return BTCore.Status.FAILURE


# 무기 위치로 이동 후 습득
class MoveToAndPickupWeapon:
	extends BTCore.BTNode

	func tick(actor: Monster, map: Map) -> BTCore.Status:
		if FindNearbyMeleeWeapon.weapon_location == Utils.INVALID_POS:
			Log.d("  MoveToAndPickupWeapon: No weapon location set")
			return BTCore.Status.FAILURE

		var monster_pos := map.find_monster_position(actor)
		var distance    := monster_pos.distance_to(FindNearbyMeleeWeapon.weapon_location)

		# 같은 칸 → 습득 시도
		if distance < 0.1:
			for item in map.get_items(monster_pos):
				if item.is_weapon() and not item.is_ranged_weapon():
					Log.d("  MoveToAndPickupWeapon: Picking up weapon %s" % item)
					actor.next_action = PickupAction.new(actor, [ItemSelection.new(item)])
					return BTCore.Status.RUNNING
			FindNearbyMeleeWeapon.weapon_location = Utils.INVALID_POS
			return BTCore.Status.FAILURE

		# 인접 → 이동
		if distance <= 1.5:
			var dir := FindNearbyMeleeWeapon.weapon_location - monster_pos
			actor.next_action = MoveAction.new(actor, dir)
			Log.d("  MoveToAndPickupWeapon: Moving onto weapon at %s" % FindNearbyMeleeWeapon.weapon_location)
			return BTCore.Status.RUNNING

		# 원거리 → 경로탐색
		var next_pos := actor.get_next_step_towards_player(
			map, monster_pos, FindNearbyMeleeWeapon.weapon_location
		)
		if next_pos != Vector2i.ZERO:
			actor.next_action = MoveAction.new(actor, next_pos)
			Log.d("  MoveToAndPickupWeapon: Moving toward weapon at %s" % FindNearbyMeleeWeapon.weapon_location)
			return BTCore.Status.RUNNING

		FindNearbyMeleeWeapon.weapon_location = Utils.INVALID_POS
		Log.d("  MoveToAndPickupWeapon: Cannot find path to weapon")
		return BTCore.Status.FAILURE


# 인벤토리에서 근접 무기 장착
class EquipMeleeWeapon:
	extends BTCore.BTNode

	func tick(actor: Monster, _map: Map) -> BTCore.Status:
		var equipped_melee := actor.equipment.get_equipped_item(Equipment.Slot.MELEE)
		if equipped_melee and equipped_melee.is_weapon() and not equipped_melee.is_ranged_weapon():
			Log.d("  EquipMeleeWeapon: Already equipped")
			return BTCore.Status.SUCCESS

		for item: Item in actor.inventory.to_array():
			if item.is_weapon() and not item.is_ranged_weapon() and not item.parent:
				if equipped_melee:
					actor.equipment.unequip_item(equipped_melee)
				actor.equipment.equip(item, Equipment.Slot.MELEE)
				Log.d("  EquipMeleeWeapon: Equipped %s" % item)
				return BTCore.Status.SUCCESS

		Log.d("  EquipMeleeWeapon: No suitable melee weapon found")
		return BTCore.Status.FAILURE


# 원거리 무기 + 탄약 장착 시도
class CheckAndEquipRangedWeapon:
	extends BTCore.BTNode

	func tick(actor: Monster, _map: Map) -> BTCore.Status:
		var equipped_ranged := actor.equipment.get_equipped_item(Equipment.Slot.RANGED)
		if equipped_ranged and equipped_ranged.is_ranged_weapon():
			if equipped_ranged.ammo_type != Damage.AmmoType.NONE:
				# 탄약 부착 여부 확인
				var has_ammo := false
				for child: Item in equipped_ranged.children.to_array():
					if child.type == Item.Type.AMMO and child.ammo_type == equipped_ranged.ammo_type:
						has_ammo = true
						break
				if has_ammo:
					Log.d("  CheckAndEquipRangedWeapon: Already equipped with ammo")
					return BTCore.Status.SUCCESS
				# 인벤토리에서 탄약 탐색
				for item: Item in actor.inventory.to_array():
					if item.type == Item.Type.AMMO and item.ammo_type == equipped_ranged.ammo_type and not item.parent:
						equipped_ranged.add_child(item)
						Log.d("  CheckAndEquipRangedWeapon: Attached ammo %s" % item)
						return BTCore.Status.SUCCESS
			else:
				Log.d("  CheckAndEquipRangedWeapon: Already equipped, no ammo needed")
				return BTCore.Status.SUCCESS

		# 인벤토리에서 원거리 무기 탐색
		for item: Item in actor.inventory.to_array():
			if item.is_ranged_weapon() and not item.parent and item != equipped_ranged:
				if equipped_ranged:
					actor.equipment.unequip_item(equipped_ranged)
				actor.equipment.equip(item, Equipment.Slot.RANGED)
				Log.d("  CheckAndEquipRangedWeapon: Equipped %s" % item)
				if item.ammo_type != Damage.AmmoType.NONE:
					for ammo: Item in actor.inventory.to_array():
						if ammo.type == Item.Type.AMMO and ammo.ammo_type == item.ammo_type and not ammo.parent:
							item.add_child(ammo)
							Log.d("  CheckAndEquipRangedWeapon: Attached ammo %s" % ammo)
							break
				return BTCore.Status.SUCCESS

		Log.d("  CheckAndEquipRangedWeapon: No suitable ranged weapon found")
		return BTCore.Status.FAILURE
