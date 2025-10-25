class_name AreaOfEffectDamageEffect
extends ActionEffect

var damage: int
var damage_type: Damage.Type
var target_pos: Vector2i


func _init(
	p_target: Monster, p_damage: int, p_damage_type: Damage.Type, p_target_pos: Vector2i
) -> void:
	super(p_target, p_target_pos)
	damage = p_damage
	damage_type = p_damage_type
	target_pos = p_target_pos
