from __future__ import annotations
from dataclasses import dataclass, field
from enum import Enum, auto
from typing import Optional, TYPE_CHECKING

if TYPE_CHECKING:
    from .entity import Entity

class CastingTime(Enum):
    ACTION       = "action"
    BONUS_ACTION = "bonus_action"
    REACTION     = "reaction"

class TargetType(Enum):
    SINGLE     = "single"      # 단일 대상
    SELF       = "self"        # 시전자 자신
    AOE_SPHERE = "aoe_sphere"  # 구형 범위 (중심점 기준 반지름 aoe_ft)
    AOE_CONE   = "aoe_cone"    # 원뿔 (시전자로부터)
    AOE_CUBE   = "aoe_cube"    # 정육면체 (시전자 인접)
    AOE_LINE   = "aoe_line"    # 직선
    MULTI      = "multi"       # 복수 단일 대상 (Magic Missile 등)

@dataclass
class SpellComponent:
    """스펠 단일 효과 단위."""
    kind: str = ""             # "damage" | "heal" | "condition" | "push" | "temp_hp" | "dot"

    # damage / heal / dot
    dice: str        = ""      # "8d6", "1d4+1", "1d8+{spellmod}"
    damage_type: str = ""      # "fire","force","thunder","radiant","necrotic","cold",
                               # "lightning","acid","poison","psychic","bludgeoning","piercing","slashing"
    # condition
    effect_key: str  = ""      # must match EffectManager _TEMPLATES key
    duration:   int  = 1       # turns

    # push / pull
    push_ft: int = 0           # positive = push, negative = pull

    # saving throw
    save_ability:    str  = ""    # "str","dex","con","int","wis","cha" / "" = auto-hit / no-save
    half_on_save:    bool = False # damage: half on success
    negate_on_save:  bool = True  # condition/push: cancel on success

    # upcast scaling (per slot level above base)
    upcast_dice: str = ""      # e.g. "1d6" means +1d6 per level above base

@dataclass
class Spell:
    key:          str
    name:         str
    level:        int             # 0 = cantrip
    school:       str
    casting_time: CastingTime
    range_ft:     int             # 0 = touch, -1 = self/aura
    target:       TargetType
    aoe_ft:       int  = 0        # radius or side length
    concentration: bool = False
    components:   list[SpellComponent] = field(default_factory=list)
    n_targets:    int  = 1        # for MULTI target type
    description:  str  = ""


def get_spell_mod(caster: "Entity") -> int:
    """
    Entity에 spell_ability 필드가 있으면 그것 사용,
    없으면 int_mod, wis_mod, cha_mod 중 최고값 반환.
    """
    if hasattr(caster, "spell_ability"):
        return getattr(caster, caster.spell_ability + "_mod")
    return max(caster.int_mod, caster.wis_mod, caster.cha_mod)

def get_spell_dc(caster: "Entity") -> int:
    """D&D 5e spell save DC = 8 + proficiency + spellcasting modifier."""
    prof = getattr(caster, "proficiency_bonus", 2)
    return 8 + prof + get_spell_mod(caster)


SPELL_REGISTRY: dict[str, Spell] = {}

def _reg(spell: Spell) -> None:
    SPELL_REGISTRY[spell.key] = spell

# 예시:
_reg(Spell(
    key="magic_missile", name="Magic Missile",
    level=1, school="evocation",
    casting_time=CastingTime.ACTION,
    range_ft=120, target=TargetType.MULTI, n_targets=3,
    components=[SpellComponent(
        kind="damage", dice="1d4+1", damage_type="force",
        save_ability="",           # no save, always hits
        upcast_dice="1d4+1",       # +1 dart per level above 1st
    )],
    description="3개의 마법 화살 자동 명중, 각 1d4+1 force 피해."
))

_reg(Spell(
    key="fireball", name="Fireball",
    level=3, school="evocation",
    casting_time=CastingTime.ACTION,
    range_ft=150, target=TargetType.AOE_SPHERE, aoe_ft=20,
    components=[SpellComponent(
        kind="damage", dice="8d6", damage_type="fire",
        save_ability="dex", half_on_save=True, negate_on_save=False,
        upcast_dice="1d6",
    )],
    description="20ft 반경 8d6 화염 피해, DEX 세이브 절반."
))

_reg(Spell(
    key="hold_person", name="Hold Person",
    level=2, school="enchantment",
    casting_time=CastingTime.ACTION,
    range_ft=60, target=TargetType.SINGLE,
    concentration=True,
    components=[SpellComponent(
        kind="condition", effect_key="paralyzed", duration=10,
        save_ability="wis", negate_on_save=True,
    )],
    description="인간형 생물 마비. WIS 세이브 매 턴 종료 시 반복."
))

_reg(Spell(
    key="acid_arrow", name="Acid Arrow",
    level=2, school="evocation",
    casting_time=CastingTime.ACTION,
    range_ft=90, target=TargetType.SINGLE,
    components=[
        SpellComponent(
            kind="damage", dice="4d4", damage_type="acid",
            save_ability="", upcast_dice="1d4"
        ),
        SpellComponent(
            kind="dot", dice="2d4", damage_type="acid",
            save_ability="", upcast_dice="1d4"
        )
    ],
    description="산성 화살이 4d4 즉시 피해 및 턴 종료 시 2d4 추가 피해 (단순화: dot 로 구현)."
))

_reg(Spell(
    key="acid_splash", name="Acid Splash",
    level=0, school="conjuration",
    casting_time=CastingTime.ACTION,
    range_ft=60, target=TargetType.SINGLE, # Can target 2 in SRD, simplifying to SINGLE for now
    components=[SpellComponent(
        kind="damage", dice="1d6", damage_type="acid",
        save_ability="dex", negate_on_save=True
    )],
    description="산성 방울, DEX 세이브 실패시 1d6 산성 피해."
))


@dataclass
class SpellResult:
    caster_uid:  str
    spell_key:   str
    success:     bool
    total_damage: int  = 0
    total_heal:  int  = 0
    targets_hit: list[str] = field(default_factory=list)
    log:         str  = ""
    reward:      float = 0.0

class SpellResolver:
    """TurnManager에서 호출하는 스펠 시전 해결사."""

    def resolve(self,
                caster:    "Entity",
                spell_key: str,
                slot_level: int,
                targets:   list["Entity"],
                all_entities: list["Entity"],
                grid_w:    int = 14,
                grid_h:    int = 14) -> SpellResult:
        """
        스펠 시전 전체 흐름:
        1. 스펠 조회 및 슬롯 검증
        2. 집중 처리 (기존 집중 해제 → 새 집중 등록)
        3. 대상 선택 (single/multi/aoe)
        4. 각 컴포넌트 적용
        5. SpellResult 반환
        """
        spell = SPELL_REGISTRY.get(spell_key)
        if spell is None:
            return SpellResult(caster.uid, spell_key, False, log=f"알 수 없는 스펠: {spell_key}")

        # 집중 처리
        if spell.concentration:
            # 기존 집중 효과를 모든 엔티티에서 해제
            for e in all_entities:
                removed = e.effects.break_concentration(source_uid=caster.uid)
                # (removed 목록은 로그용)
            # 시전자에게 집중 마커 부여 (선택적 — 집중 판정용)
            if not hasattr(caster, "_concentrating"):
                caster._concentrating = spell_key

        dc       = get_spell_dc(caster)
        sp_mod   = get_spell_mod(caster)
        # upcast 레벨 차이
        extra_levels = max(0, slot_level - spell.level) if spell.level > 0 else 0

        total_dmg  = 0
        total_heal = 0
        hits       = []
        log_parts  = [f"{caster.name} → {spell.name}"]

        # 대상 목록 결정
        resolved_targets = self._resolve_targets(
            caster, spell, targets, all_entities, grid_w, grid_h
        )

        for target in resolved_targets:
            for comp in spell.components:
                part_log = self._apply_component(
                    caster, target, comp, dc, sp_mod, extra_levels
                )
                log_parts.append(part_log)
                if comp.kind == "damage":
                    total_dmg += target.max_hp - target.hp  # delta (approximation)
                elif comp.kind == "heal":
                    total_heal += 0  # filled below
            if target.uid not in hits:
                hits.append(target.uid)

        reward = total_dmg / max(1, sum(e.max_hp for e in resolved_targets if e in [t for t in resolved_targets])) if total_dmg > 0 else 0.0
        return SpellResult(
            caster_uid=caster.uid, spell_key=spell_key, success=True,
            total_damage=total_dmg, total_heal=total_heal,
            targets_hit=hits, log=" | ".join(log_parts), reward=reward
        )

    def _resolve_targets(self, caster, spell, explicit_targets, all_entities, gw, gh):
        """TargetType에 따라 실제 영향받는 엔티티 목록 반환."""
        if spell.target in (TargetType.SINGLE, TargetType.MULTI):
            return explicit_targets[:spell.n_targets]
        elif spell.target == TargetType.SELF:
            return [caster]
        elif spell.target == TargetType.AOE_SPHERE:
            # explicit_targets[0]를 중심점으로 사용, aoe_ft 반경 내 모든 엔티티
            if not explicit_targets:
                return []
            center = explicit_targets[0]
            radius_tiles = spell.aoe_ft // 5
            return [e for e in all_entities
                    if e.is_alive
                    and abs(e.x - center.x) + abs(e.y - center.y) <= radius_tiles]
        elif spell.target == TargetType.AOE_CONE:
            # 단순화: 시전자 전방 aoe_ft/5 타일 내 모든 엔티티
            radius_tiles = spell.aoe_ft // 5
            return [e for e in all_entities
                    if e.is_alive and e.uid != caster.uid
                    and abs(e.x - caster.x) + abs(e.y - caster.y) <= radius_tiles]
        elif spell.target == TargetType.AOE_CUBE:
            side_tiles = spell.aoe_ft // 5
            return [e for e in all_entities
                    if e.is_alive and e.uid != caster.uid
                    and abs(e.x - caster.x) <= side_tiles
                    and abs(e.y - caster.y) <= side_tiles]
        elif spell.target == TargetType.AOE_LINE:
            # 단순화: 시전자로부터 직선 (x 또는 y축 동일한 엔티티)
            line_tiles = spell.aoe_ft // 5
            return [e for e in all_entities
                    if e.is_alive and e.uid != caster.uid
                    and (e.x == caster.x or e.y == caster.y)
                    and abs(e.x - caster.x) + abs(e.y - caster.y) <= line_tiles]
        return explicit_targets

    def _apply_component(self, caster, target, comp: SpellComponent,
                         dc: int, sp_mod: int, extra_levels: int) -> str:
        """단일 SpellComponent를 대상에게 적용. 로그 문자열 반환."""
        from .dice import roll as dice_roll
        from .dice import roll_save as dice_roll_save
        from .conditions import make_effect, TickOn

        # 주사위 표기에서 {spellmod} 치환
        def resolve_dice(notation: str) -> str:
            return notation.replace("{spellmod}", str(sp_mod))

        # upcast 추가 주사위
        def upcast_dice_str(base: str, extra: str, levels: int) -> str:
            if not extra or levels == 0:
                return base
            # "2d6" + "1d6" * 2levels → "4d6" (단순화: 같은 면 주사위 합산)
            return base + "+" + "+".join([extra] * levels)

        # 세이브 판정
        saved = False
        if comp.save_ability:
            save_bonus = getattr(target, comp.save_ability + "_mod", 0)
            save_q     = target.effects.query_save()
            save_res   = dice_roll_save(save_bonus + save_q.bonus, dc,
                                        adv=save_q.advantage, dis=save_q.disadvantage,
                                        auto_fail=save_q.auto_fail)
            saved = save_res["success"]

        # ── damage ───────────────────────────────────────────────────────
        if comp.kind == "damage":
            notation = upcast_dice_str(resolve_dice(comp.dice), comp.upcast_dice, extra_levels)
            if saved and comp.negate_on_save:
                return f"{target.name} SAVED (no dmg)"
            raw = dice_roll(notation)
            if saved and comp.half_on_save:
                raw = raw // 2
            actual = target.take_damage(raw, comp.damage_type)
            return f"{target.name} {actual} {comp.damage_type} dmg (save={'Y' if saved else 'N'})"

        # ── heal ─────────────────────────────────────────────────────────
        elif comp.kind == "heal":
            notation = upcast_dice_str(resolve_dice(comp.dice), comp.upcast_dice, extra_levels)
            amt = dice_roll(notation)
            actual = target.heal(amt)
            return f"{target.name} +{actual} HP"

        # ── condition ────────────────────────────────────────────────────
        elif comp.kind == "condition":
            if saved and comp.negate_on_save:
                return f"{target.name} SAVED ({comp.effect_key} negated)"
            from .conditions import TickOn as TickOn_
            tick = TickOn_.CONCENTRATION if comp.effect_key in {
                "haste", "bless", "bane", "hex", "hunters_mark", "shield_of_faith",
                "banished", "hold_person_conc",
            } else TickOn_.TURN_END
            target.effects.add(make_effect(
                comp.effect_key, duration=comp.duration,
                source_uid=caster.uid, tick_on=tick
            ))
            return f"{target.name} ← {comp.effect_key} ({comp.duration}턴)"

        # ── push ─────────────────────────────────────────────────────────
        elif comp.kind == "push":
            if saved and comp.negate_on_save:
                return f"{target.name} SAVED (no push)"
            tiles = comp.push_ft // 5
            dx = 1 if target.x >= caster.x else -1
            dy = 1 if target.y >= caster.y else -1
            target.x = max(0, min(13, target.x + dx * tiles))
            target.y = max(0, min(13, target.y + dy * tiles))
            return f"{target.name} pushed {comp.push_ft}ft"

        # ── dot (damage over time) ────────────────────────────────────────
        elif comp.kind == "dot":
            # 간단 구현: 즉시 피해 (RL 단순화)
            if saved and comp.negate_on_save:
                return f"{target.name} SAVED"
            raw = dice_roll(resolve_dice(comp.dice))
            actual = target.take_damage(raw, comp.damage_type)
            return f"{target.name} {actual} {comp.damage_type} DoT"

        return f"[unknown component kind: {comp.kind}]"
