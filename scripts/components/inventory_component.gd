class_name InventoryComponent
extends RefCounted

# =============================================================
# 🎒 [인벤토리 컴포넌트] INVENTORY COMPONENT
# =============================================================
# 아이템 추가/제거/검색/드랍 전 로직을 담당합니다.
# Equipment 슬롯 관리는 Equipment 클래스에 위임합니다.

var items: Set = Set.new([], typeof(Item))

func _init() -> void:
	Log.d("[InventoryComponent] Initialized")


# =============================================================
# 🔧 [구역 1] 아이템 추가/제거 (MUTATION)
# =============================================================

func add(item: Item) -> void:
	if items.has(item):
		return

	# 스택 가능한 아이템: 기존 스택에 합치기 시도
	if item.max_stack_size > 1:
		for existing: Item in items.to_array():
			if existing.matches(item):
				var space_left := existing.max_stack_size - existing.quantity
				if space_left > 0:
					var amount_to_add := mini(space_left, item.quantity)
					existing.quantity += amount_to_add
					item.quantity -= amount_to_add
					if item.quantity == 0:
						return

	items.add(item)


func remove(item: Item, quantity: int = 1) -> bool:
	# 직접 인벤토리에서 찾기
	if items.has(item):
		if item.quantity > quantity:
			item.quantity -= quantity
			return true
		else:
			items.remove(item)
			return true

	# 중첩 아이템(컨테이너 내부) 탐색
	for inv_item: Item in items.to_array():
		if inv_item.has_child(item):
			if inv_item.remove_child(item):
				return true

	return false


func has(item: Item) -> bool:
	if items.has(item):
		return true
	for inv_item: Item in items.to_array():
		if inv_item.has_child(item):
			return true
	return false


func to_array() -> Array:
	return items.to_array()


func clear() -> void:
	items.clear()


# =============================================================
# 🎁 [구역 2] 드랍 처리 (DROP)
# =============================================================

## 모든 아이템을 현재 위치에 드랍 (사망 처리용)
func drop_all_to_map(equipment: Equipment, pos: Vector2i, map: Map) -> void:
	# 장비 해제 먼저
	for item: Item in equipment.get_all_equipped_items():
		equipment.unequip_item(item)

	# 인벤토리 전체 드랍
	var to_drop: Array = items.to_array()
	items.clear()
	for item: Item in to_drop:
		map.add_item_with_stacking(pos, item)
	Log.d("[InventoryComponent] Dropped %d items at %s" % [to_drop.size(), pos])


# =============================================================
# 🔍 [구역 3] 검색 (SEARCH)
# =============================================================

## slug로 아이템 찾기
func find_by_slug(slug: StringName) -> Item:
	for item: Item in items.to_array():
		if item.slug == slug:
			return item
	return null
