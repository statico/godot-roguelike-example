class_name Log
extends RefCounted

enum LogLevel { DEBUG, INFO, WARNING, ERROR }

const COLORS = {
	LogLevel.DEBUG: "blue",
	LogLevel.INFO: "green",
	LogLevel.WARNING: "yellow",
	LogLevel.ERROR: "red"
}

# Customize which classes to ignore in the log
const IGNORED_CLASSES = ["DungeonGenerator", "Equipment", "Map"]

static var _last_message := ""


static func d(
	msg: String,
	arg1: Variant = null,
	arg2: Variant = null,
	arg3: Variant = null,
	arg4: Variant = null,
	arg5: Variant = null,
	arg6: Variant = null,
	arg7: Variant = null,
	arg8: Variant = null
) -> void:
	if OS.is_debug_build():
		_log(LogLevel.DEBUG, msg, [arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8])


static func i(
	msg: String,
	arg1: Variant = null,
	arg2: Variant = null,
	arg3: Variant = null,
	arg4: Variant = null,
	arg5: Variant = null,
	arg6: Variant = null,
	arg7: Variant = null,
	arg8: Variant = null
) -> void:
	_log(LogLevel.INFO, msg, [arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8])


static func w(
	msg: String,
	arg1: Variant = null,
	arg2: Variant = null,
	arg3: Variant = null,
	arg4: Variant = null,
	arg5: Variant = null,
	arg6: Variant = null,
	arg7: Variant = null,
	arg8: Variant = null
) -> void:
	_log(LogLevel.WARNING, msg, [arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8])


static func e(
	msg: String,
	arg1: Variant = null,
	arg2: Variant = null,
	arg3: Variant = null,
	arg4: Variant = null,
	arg5: Variant = null,
	arg6: Variant = null,
	arg7: Variant = null,
	arg8: Variant = null
) -> void:
	_log(LogLevel.ERROR, msg, [arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8])


static func _log(level: LogLevel, msg: String, args: Array) -> void:
	var stack := get_stack()
	var classname := ""
	if stack.size() > 2:
		var frame: Dictionary = get_stack()[2]
		classname = _get_class_name(frame)

	if classname in IGNORED_CLASSES:
		return

	# Format the message and arguments
	var message := str(msg)
	for arg: Variant in args:
		if arg != null:
			if arg is Array:
				message += " " + str(arg)
			else:
				message += " " + str(arg)

	# Format with BBCode, stripping colors if in browser
	var color: String = COLORS[level]
	var prefix: String = _get_level_prefix(level)
	var formatted: String
	var is_web := OS.has_feature("web")

	if is_web:
		formatted = "%s[%s] %s" % [prefix, classname, message]
	else:
		formatted = "[color=%s][b]%s[%s][/b][/color] %s" % [color, prefix, classname, message]

	# Skip if this is the same as the last message
	if formatted == _last_message:
		return

	_last_message = formatted

	if is_web:
		print(formatted)
	else:
		print_rich(formatted)

	if level == LogLevel.ERROR:
		for frame: Dictionary in stack:
			if frame["source"] == "res://src/log.gd":
				continue
			var stack_line := (
				"  at %s:%s in %s"
				% [str(frame["source"]), str(frame["line"]), str(frame["function"])]
			)
			if is_web:
				print(stack_line)
			else:
				print_rich("[color=gray]%s[/color]" % stack_line)


static func _get_level_prefix(level: LogLevel) -> String:
	match level:
		LogLevel.DEBUG:
			return ""
		LogLevel.INFO:
			return ""
		LogLevel.WARNING:
			return "WARN "
		LogLevel.ERROR:
			return "ERROR "
	return ""


static func _get_class_name(frame: Dictionary) -> String:
	if not frame.has("source"):
		return "Unknown"

	var path: String = frame["source"]
	if path == null:
		return "Unknown"

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if not file:
		return "Unknown"

	var classname := ""

	# Read first few lines to find class name
	for _i in range(10):
		if file.eof_reached():
			break

		var line := file.get_line().strip_edges()
		if line.begins_with("class_name"):
			classname = line.split(" ")[1]
			break

	file.close()
	return classname if classname else path.get_file().get_basename()
