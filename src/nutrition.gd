class_name Nutrition
extends RefCounted

enum Status {
	DEAD,  # <= -200
	STARVING,  # -100 to -199
	FAINTING,  # -1 to -99
	WEAK,  # 0 to 49
	HUNGRY,  # 50 to 149
	NORMAL,  # 150 to 999
	SATIATED,  # 1000 to 2000
	OVERSATIATED,  # > 2000 (Risk of choking!)
}

const STARTING_NUTRITION := 900
const MAX_NUTRITION := 2000
const THRESHOLD_OVERSATIATED := 2000
const THRESHOLD_SATIATED := 1000
const THRESHOLD_NORMAL := 150
const THRESHOLD_HUNGRY := 50
const THRESHOLD_WEAK := 0
const THRESHOLD_FAINTING := -1
const THRESHOLD_STARVING := -100
const THRESHOLD_DEAD := -200


class NutritionChangeResult:
	var message: String = ""
	var choking: bool = false
	var died: bool = false


var value: int = STARTING_NUTRITION


func decrease(amount: int) -> NutritionChangeResult:
	var result := NutritionChangeResult.new()
	var old_value := value
	value = maxi(THRESHOLD_DEAD, value - amount)

	# Check if we crossed any thresholds and set appropriate messages
	if old_value >= THRESHOLD_NORMAL and value < THRESHOLD_NORMAL:
		result.message = "You are beginning to feel hungry."
	elif old_value >= THRESHOLD_WEAK and value < THRESHOLD_WEAK:
		result.message = "You are getting weak from hunger."
	elif old_value >= THRESHOLD_FAINTING and value < THRESHOLD_FAINTING:
		result.message = "You feel faint from hunger."
	elif old_value >= THRESHOLD_STARVING and value < THRESHOLD_STARVING:
		result.message = "You are starving!"
	elif value <= THRESHOLD_DEAD:
		result.message = "You die from starvation."
		result.died = true

	return result


func increase(amount: int) -> NutritionChangeResult:
	var result := NutritionChangeResult.new()
	var old_value := value
	value = mini(value + amount, THRESHOLD_OVERSATIATED + 200)  # Allow slight overflow for choking check

	# Check for choking when going over maximum
	if value > THRESHOLD_OVERSATIATED:
		if old_value <= THRESHOLD_OVERSATIATED:
			result.message = "You're having a hard time getting all of it down."

		# NetHack-style choking check: roll d20, choke on 1
		if Dice.roll(1, 20) == 1:
			result.message = "You choke over your food!"
			result.choking = true
			result.died = true

	return result


func get_status() -> Status:
	if value <= THRESHOLD_DEAD:
		return Status.DEAD
	elif value <= THRESHOLD_STARVING:
		return Status.STARVING
	elif value <= THRESHOLD_FAINTING:
		return Status.FAINTING
	elif value <= THRESHOLD_WEAK:
		return Status.WEAK
	elif value <= THRESHOLD_HUNGRY:
		return Status.HUNGRY
	elif value <= THRESHOLD_SATIATED:
		return Status.NORMAL
	elif value <= THRESHOLD_OVERSATIATED:
		return Status.SATIATED
	else:
		return Status.OVERSATIATED


static func get_status_name(status: Status) -> String:
	match status:
		Status.DEAD:
			return "Dead"
		Status.STARVING:
			return "Starving"
		Status.FAINTING:
			return "Fainting"
		Status.WEAK:
			return "Weak"
		Status.HUNGRY:
			return "Hungry"
		Status.NORMAL:
			return ""  # No display when normal
		Status.SATIATED:
			return "Satiated"
		Status.OVERSATIATED:
			return "Oversatiated"
		_:
			return "Unknown"


static func get_status_rich_text_label(status: Status) -> String:
	var red := GameColors.RED.to_html()
	var orange := GameColors.ORANGE.to_html()
	var yellow := GameColors.YELLOW.to_html()
	var green := GameColors.GREEN.to_html()
	var gray := GameColors.SUBTLE.to_html()

	match status:
		Status.DEAD:
			return "[color=%s]Dead[/color]" % gray
		Status.STARVING:
			return "[color=%s][pulse]Starving[/pulse][/color]" % red
		Status.FAINTING:
			return "[color=%s][pulse]Fainting[/pulse][/color]" % orange
		Status.WEAK:
			return "[color=%s][pulse]Weak[/pulse][/color]" % orange
		Status.HUNGRY:
			return "[color=%s]Hungry[/color]" % yellow
		Status.NORMAL:
			return ""  # No display when normal
		Status.SATIATED:
			return "[color=%s]Satiated[/color]" % green
		Status.OVERSATIATED:
			return "[color=%s][pulse]Oversatiated[/pulse][/color]" % red
		_:
			return "Unknown"
