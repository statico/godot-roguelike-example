class_name BTCore
extends RefCounted

# =============================================================
# 🌳 [BT 코어] BEHAVIOR TREE CORE
# =============================================================
# Behavior Tree의 기반 타입과 복합 노드(Sequence, Selector)를 정의합니다.
# 모든 BTNode 서브클래스는 이 파일의 타입을 공유합니다.

# =============================================================
# 📌 [구역 1] 상태 열거형 (STATUS ENUM)
# =============================================================

enum Status {
	SUCCESS,
	FAILURE,
	RUNNING,
}


# =============================================================
# 🔧 [구역 2] 베이스 노드 (BASE NODE)
# =============================================================

class BTNode:
	extends RefCounted

	func tick(_actor: Monster, _map: Map) -> BTCore.Status:
		return BTCore.Status.FAILURE


# Node that explicitly does nothing and always succeeds
class DoNothing:
	extends BTNode

	func tick(_actor: Monster, _map: Map) -> BTCore.Status:
		Log.d("  DoNothing: Doing nothing")
		return BTCore.Status.SUCCESS


# =============================================================
# 🔧 [구역 3] 복합 노드 (COMPOSITE NODES)
# =============================================================

# Sequence: 자식을 순서대로 실행, 하나라도 실패하면 FAILURE (논리 AND)
class BTSequence:
	extends BTNode
	var children: Array[BTNode]

	func _init(p_children: Array[BTNode] = []) -> void:
		children = p_children

	func tick(actor: Monster, map: Map) -> BTCore.Status:
		for child in children:
			match child.tick(actor, map):
				BTCore.Status.FAILURE:
					return BTCore.Status.FAILURE
				BTCore.Status.RUNNING:
					return BTCore.Status.RUNNING
				BTCore.Status.SUCCESS:
					continue
		return BTCore.Status.SUCCESS


# Selector: 자식을 순서대로 실행, 하나라도 성공하면 SUCCESS (논리 OR)
class BTSelector:
	extends BTNode
	var children: Array[BTNode]

	func _init(p_children: Array[BTNode] = []) -> void:
		children = p_children

	func tick(actor: Monster, map: Map) -> BTCore.Status:
		for child in children:
			match child.tick(actor, map):
				BTCore.Status.SUCCESS:
					return BTCore.Status.SUCCESS
				BTCore.Status.RUNNING:
					return BTCore.Status.RUNNING
		return BTCore.Status.FAILURE


# =============================================================
# 🔧 [구역 4] DSL 헬퍼 (BUILDER DSL)
# =============================================================
# BT 트리를 코드로 읽기 쉽게 작성할 수 있는 static 빌더 함수들.

static func sequence(
	a: Variant,
	b: Variant = null,
	c: Variant = null,
	d: Variant = null,
	e: Variant = null,
	f: Variant = null
) -> BTNode:
	return BTSequence.new(_build_nodes([a, b, c, d, e, f]))


static func selector(
	a: Variant,
	b: Variant = null,
	c: Variant = null,
	d: Variant = null,
	e: Variant = null,
	f: Variant = null
) -> BTNode:
	return BTSelector.new(_build_nodes([a, b, c, d, e, f]))


static func _build_nodes(children: Array) -> Array[BTNode]:
	var nodes: Array[BTNode] = []
	for child: Variant in children:
		if child == null:
			continue
		elif child is BTNode:
			nodes.append(child)
		elif child is GDScript:
			nodes.append((child as GDScript).new())
		elif child is Array:
			nodes.append_array(_build_nodes(child as Array))
	return nodes
