extends Node

## Various async utilities for GDScript inspired by TypeScript.


func await_all(list: Array) -> void:
	var counter: Dictionary = {"value": list.size()}

	for el: Variant in list:
		var fn: Callable = _count_down.bind(counter)
		if el is Signal:
			(el as Signal).connect(fn, CONNECT_ONE_SHOT)
		elif el is Callable:
			_func_wrapper(el as Callable, fn)

	while counter.value > 0:
		await get_tree().process_frame


func _count_down(dict: Dictionary) -> void:
	dict.value -= 1


func _func_wrapper(p_call: Callable, call_back: Callable) -> void:
	await p_call.call()
	call_back.call()
