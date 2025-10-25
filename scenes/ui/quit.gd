extends Control


func _ready() -> void:
	Log.i("Quitting...")
	await get_tree().process_frame
	get_tree().quit()
