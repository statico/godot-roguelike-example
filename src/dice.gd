## A class that handles all dice rolling and probability functions.
## Uses its own RandomNumberGenerator to ensure consistent seeding.
##
## Adapted from https://www.redblobgames.com/articles/probability/damage-rolls.html
##
## @experimental
class_name Dice
extends Node

static var _rng := RandomNumberGenerator.new()


## Sets the seed for the dice rolling RNG.
## @param value The seed value to use. Pass -1 for a random seed based on system time.
static func set_seed(value: int = -1) -> void:
	if value < 0:
		_rng.randomize()
	else:
		_rng.seed = value


## Rolls dice and returns the sum.
## @param num_dice The number of dice to roll
## @param sides The number of sides on each die
## @return The sum of all dice rolls
static func roll(num_dice: int, sides: int) -> int:
	var total := 0
	for i in num_dice:
		total += _rng.randi_range(1, sides)
	return total


## Formats a dice roll as a string.
static func format(num_dice: int, sides: int) -> String:
	return "%dd%d" % [num_dice, sides]


## Rolls dice and keeps the highest results.
## @param num_dice The number of dice to roll
## @param sides The number of sides on each die
## @param keep The number of highest dice to keep
## @return The sum of the kept dice
static func keep_highest(num_dice: int, sides: int, keep: int) -> int:
	keep = mini(keep, num_dice)  # Can't keep more dice than we roll
	var rolls: Array[int] = []
	for i in num_dice:
		rolls.append(_rng.randi_range(1, sides))
	rolls.sort()
	rolls.reverse()

	var total := 0
	for i in keep:
		total += rolls[i]
	return total


## Rolls dice and keeps the lowest results.
## @param num_dice The number of dice to roll
## @param sides The number of sides on each die
## @param keep The number of lowest dice to keep
## @return The sum of the kept dice
static func keep_lowest(num_dice: int, sides: int, keep: int) -> int:
	keep = mini(keep, num_dice)  # Can't keep more dice than we roll
	var rolls: Array[int] = []
	for i in num_dice:
		rolls.append(_rng.randi_range(1, sides))
	rolls.sort()

	var total := 0
	for i in keep:
		total += rolls[i]
	return total


## Returns a random percentage value.
## @return A float between 0.0 and 100.0
static func percent() -> float:
	return _rng.randf() * 100.0


## Performs a probability check.
## @param p_chance The percentage chance of success (0-1.0)
## @return True if the check succeeds
static func chance(p_chance: float) -> bool:
	return percent() < p_chance * 100.0


## Performs a roll with critical hit chance.
## @param base_roll The callable that performs the base roll
## @param crit_chance The percentage chance of a critical hit (0-100)
## @param crit_roll The callable that performs the critical hit roll
## @return The final roll result including any critical damage
static func with_critical(base_roll: Callable, crit_chance: float, crit_roll: Callable) -> int:
	var result: int = base_roll.call()
	if chance(crit_chance):
		result += crit_roll.call()
	return result


## A class for creating arbitrary probability distributions.
## @experimental
class WeightedTable:
	extends RefCounted

	var entries: Array[Dictionary] = []
	var total_weight: int = 0

	## Adds a new entry to the probability table.
	## @param value The value to add
	## @param weight The relative weight of this entry
	func add_entry(value: Variant, weight: int) -> void:
		entries.append({"value": value, "weight": weight})
		total_weight += weight

	## Rolls on the probability table.
	## @return A randomly selected value based on weights
	func roll() -> Variant:
		var value := Dice._rng.randi_range(0, total_weight - 1)
		var current_total := 0

		for entry in entries:
			current_total += entry.weight
			if value < current_total:
				return entry.value

		# Fallback (shouldn't happen unless table is empty)
		return null


## Creates and rolls a weighted table in one operation.
## @param values The array of possible values
## @param weights The array of weights corresponding to the values
## @return A randomly selected value based on weights
static func weighted_choice(values: Array, weights: Array[int]) -> Variant:
	var table := WeightedTable.new()
	for i in values.size():
		table.add_entry(values[i], weights[i])
	return table.roll()
