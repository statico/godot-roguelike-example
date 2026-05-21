extends Node

# =============================================================
# 🔑 [INSTANCE ID MANAGER] 인스턴스 ID 관리자
# =============================================================
# 게임 오브젝트(Monster, Item 등)에 직렬화 가능한 고유 정수 ID를 부여합니다.
# 세이브/로드 시 참조 복원에 사용됩니다.
#
# 사용법:
#   var id := InstanceID.register(my_object)   # 등록 → ID 반환
#   var obj := InstanceID.get_object(id)        # ID로 오브젝트 조회
#   InstanceID.unregister(id)                   # 제거 (사망 등)
#   InstanceID.reset()                          # 새 게임 시작 시

var _next_id: int = 1
var _registry: Dictionary = {}  # int -> WeakRef


func register(obj: Object) -> int:
	var id := _next_id
	_next_id += 1
	_registry[id] = weakref(obj)
	return id


func get_object(id: int) -> Object:
	var ref: WeakRef = _registry.get(id, null)
	if ref:
		return ref.get_ref()
	return null


func unregister(id: int) -> void:
	_registry.erase(id)


func reset() -> void:
	_next_id = 1
	_registry.clear()
	Log.i("[InstanceID] Registry reset")
