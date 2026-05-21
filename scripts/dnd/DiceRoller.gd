extends Node

# =============================================================
# 🎲 [구역 1] 기본 주사위 굴리기 (BASIC ROLLS)
# =============================================================

## 주사위 표기법 파싱 및 굴리기
## 예: roll("2d6+3"), roll("d20"), roll("1d8-1")
func roll(notation: String) -> int:
	var result := _parse_and_roll(notation)
	print("[DiceRoller] %s → %d" % [notation, result])
	return result

## 어드밴티지: d20 두 개 굴려서 높은 값
func roll_advantage() -> int:
	var a := randi_range(1, 20)
	var b := randi_range(1, 20)
	var result := maxi(a, b)
	print("[DiceRoller] 어드밴티지 d20: [%d, %d] → %d" % [a, b, result])
	return result

## 디스어드밴티지: d20 두 개 굴려서 낮은 값
func roll_disadvantage() -> int:
	var a := randi_range(1, 20)
	var b := randi_range(1, 20)
	var result := mini(a, b)
	print("[DiceRoller] 디스어드밴티지 d20: [%d, %d] → %d" % [a, b, result])
	return result

## 이니셔티브 롤: d20 + DEX modifier
func roll_initiative(dex_modifier: int) -> int:
	var d20 := randi_range(1, 20)
	var result := d20 + dex_modifier
	print("[DiceRoller] 이니셔티브: d20(%d) + DEX mod(%d) = %d" % [d20, dex_modifier, result])
	return result

## 크리티컬 히트 판정 (자연 20)
func is_critical(raw_d20: int) -> bool:
	return raw_d20 == 20

## 크리티컬 히트 데미지: 데미지 주사위 2배 + 보너스
func roll_critical(damage_dice: String, bonus: int) -> int:
	var dice_only := roll(damage_dice)
	var result := (dice_only * 2) + bonus
	print("[DiceRoller] 크리티컬! %s×2 + %d = %d" % [damage_dice, bonus, result])
	return result

# =============================================================
# 🔧 [구역 2] 내부 파싱 (INTERNAL PARSING)
# =============================================================

## "2d6+3" 형태의 표기법을 파싱해서 결과 반환
func _parse_and_roll(notation: String) -> int:
	notation = notation.strip_edges().to_lower()

	# 보너스/페널티 분리 (+/- 기준)
	var bonus := 0
	var dice_part := notation

	if "+" in notation:
		var parts := notation.split("+", false, 1)
		dice_part = parts[0]
		bonus = parts[1].to_int()
	elif notation.count("-") > 0 and not notation.begins_with("-"):
		var idx := notation.rfind("-")
		dice_part = notation.substr(0, idx)
		bonus = -notation.substr(idx + 1).to_int()

	# "d" 기준으로 횟수와 면수 분리
	if "d" in dice_part:
		var d_parts := dice_part.split("d", false, 1)
		var count: int = d_parts[0].to_int() if d_parts[0] != "" else 1
		var sides: int = d_parts[1].to_int()
		var total := 0
		for i in count:
			total += randi_range(1, sides)
		return total + bonus
	else:
		# 주사위 없이 숫자만 (예: "5")
		return dice_part.to_int() + bonus
