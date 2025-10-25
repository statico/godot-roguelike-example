class_name Utils
extends RefCounted

const INVALID_POS: Vector2i = Vector2i(-1, -1)

const ALL_DIRECTIONS: Array[Vector2i] = [
	# Order matters here for pathfinding
	Vector2i.UP,
	Vector2i.DOWN,
	Vector2i.LEFT,
	Vector2i.RIGHT,
	Vector2i.UP + Vector2i.LEFT,
	Vector2i.UP + Vector2i.RIGHT,
	Vector2i.DOWN + Vector2i.LEFT,
	Vector2i.DOWN + Vector2i.RIGHT,
]

const CARDINAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i.UP,
	Vector2i.DOWN,
	Vector2i.LEFT,
	Vector2i.RIGHT,
]

static func capitalize_first(text: String) -> String:
	if text.is_empty():
		return text
	return text[0].to_upper() + text.substr(1)


static func array_of_strings(array: Variant) -> Array[String]:
	var ret: Array[String] = []
	for el: Variant in array:
		ret.append(el as String)
	return ret


static func array_of_stringnames(array: Variant) -> Array[StringName]:
	var ret: Array[StringName] = []
	for el: Variant in array:
		if el is String:
			ret.append(StringName(el as String))
		elif el is StringName:
			ret.append(el)
		else:
			Log.e("Invalid element in array: %s" % [el])
			assert(false, "Invalid element in array: %s" % [el])
	return ret


static func array_of_ints(array: Variant) -> Array[int]:
	var ret: Array[int] = []
	for el: Variant in array:
		ret.append(el as int)
	return ret


static func to_int(value: Variant) -> int:
	if value is int:
		return value
	if value is float:
		return int(value as float)
	if value is String:
		return int(value as String)
	Log.e("Invalid value: %s" % value)
	assert(false, "Invalid value: %s" % value)
	return 0


static func to_float(value: Variant) -> float:
	if value is float:
		return value
	if value is int:
		return float(value as int)
	if value is String:
		return float(value as String)
	Log.e("Invalid value: %s" % value)
	assert(false, "Invalid value: %s" % value)
	return 0


static func with_sign(value: int) -> String:
	return ("+" if value >= 0 else "") + str(value)


static func with_sign_non_zero(value: int) -> String:
	return with_sign(value) if value != 0 else str(value)


static func levenshtein_distance(a: String, b: String) -> int:
	# Create matrix of size (m+1)x(n+1) where m and n are lengths of strings
	var m := a.length()
	var n := b.length()
	var matrix: Array[Array] = []

	# Initialize first row and column
	for i in range(m + 1):
		var row: Array[int] = []
		for j in range(n + 1):
			if i == 0:
				row.append(j)
			elif j == 0:
				row.append(i)
			else:
				row.append(0)
		matrix.append(row)

	# Fill rest of matrix
	for i in range(1, m + 1):
		for j in range(1, n + 1):
			if a[i - 1] == b[j - 1]:
				matrix[i][j] = matrix[i - 1][j - 1]
			else:
				matrix[i][j] = min(
					matrix[i - 1][j] + 1, min(matrix[i][j - 1] + 1, matrix[i - 1][j - 1] + 1)  # deletion  # insertion  # substitution
				)

	return matrix[m][n]


static func calculate_trajectory(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var trajectory: Array[Vector2i] = []

	# Calculate the diagonal distance between points
	var dx: int = to.x - from.x
	var dy := to.y - from.y
	var n := maxi(abs(dx) as int, abs(dy) as int)  # diagonal_distance

	# Handle the case where from == to
	if n == 0:
		trajectory.append(from)
		return trajectory

	# Calculate n+1 points along the line
	for step in range(n + 1):
		var t := float(step) / n
		# Linear interpolation for both x and y
		var x := roundi(lerpf(float(from.x), float(to.x), t))
		var y := roundi(lerpf(float(from.y), float(to.y), t))
		trajectory.append(Vector2i(x, y))

	return trajectory
