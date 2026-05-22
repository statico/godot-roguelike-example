# Gemini Task: D&D 5e Spell System Implementation

## 사용법
1. 이 파일 전체를 Gemini에게 붙여넣기
2. 그 다음 아래 "ATTACH FILES" 목록의 파일들을 같이 첨부
3. SRD 스펠 파일들도 첨부 (경로 안내는 아래 참조)

---

## ATTACH THESE FILES (컨텍스트로 첨부할 파일들)

**From `C:\Users\lmcbv\Documents\GitHub\LLM_Crawl_Godot\`:**
- `conditions.py`  ← EffectManager, Effect, TickOn, StackRule, make_effect(), _TEMPLATES
- `entity.py`      ← Entity dataclass
- `turn_manager.py`← TurnManager, combat flow
- `actions.py`     ← Action enum
- `dice.py`        ← roll_attack, roll_save, roll (notation)

**From `C:\Users\lmcbv\Documents\GitHub\LLM_Crawl_Godot\data\srd\07_Spells\Spells_A-Z\`:**
- `Spells_A.md` through `Spells_Z.md` (26 files, all SRD spells)

---

## ROLE

You are implementing the complete D&D 5e spell system for a **Python tactical RPG engine**.
The engine is used for reinforcement learning training (PettingZoo AEC environment),
so all spell logic must be **deterministically executable in Python** — no ambiguous natural language.

---

## EXISTING CODEBASE SUMMARY

The engine already has:

### EffectManager (in `conditions.py`)
Every `Entity` has an `effects: EffectManager` field.
Key API:
```python
entity.effects.add(make_effect("blinded", duration=2, source_uid=caster.uid))
entity.effects.add(make_condition(Condition.PARALYZED, duration=1, source_uid=caster.uid))
entity.effects.break_concentration(source_uid=caster.uid)

entity.effects.query_can_act()          # → bool
entity.effects.query_can_move()         # → bool
entity.effects.query_attack_roll()      # → AttackRollQuery (adv, dis, bonus)
entity.effects.query_attacked_roll()    # → AttackRollQuery
entity.effects.query_damage_out()       # → DamageQuery (bonus, multiplier, auto_crit)
entity.effects.query_damage_in()        # → DamageQuery
entity.effects.query_save()             # → SaveQuery (adv, dis, bonus, auto_fail)
entity.effects.query_ac_bonus()         # → int
```

### Existing effect keys in `_TEMPLATES` (conditions.py)
Standard conditions: `"prone"`, `"stunned"`, `"frightened"`, `"grappled"`,
`"restrained"`, `"poisoned"`, `"charmed"`, `"incapacitated"`, `"unconscious"`,
`"blinded"`, `"deafened"`, `"paralyzed"`, `"petrified"`, `"exhaustion_1"`

Spell buffs already defined: `"bless"`, `"bane"`, `"haste"`, `"hex"`,
`"hunters_mark"`, `"shield_of_faith"`

### Dice API (in `dice.py`)
```python
roll("2d6+3")          # → int
roll_attack(bonus, adv=False, dis=False)  # → dict {total, is_crit, is_fumble, ...}
roll_save(bonus, dc, adv=False, dis=False, auto_fail=False)  # → dict {success, ...}
```

### Entity fields (relevant ones)
```python
entity.uid, entity.name, entity.faction   # identity
entity.hp, entity.max_hp, entity.ac       # stats
entity.str_mod, entity.dex_mod, entity.con_mod,
entity.int_mod, entity.wis_mod, entity.cha_mod  # modifiers
entity.x, entity.y                         # grid position (1 tile = 5ft)
entity.resistances: list[str]              # damage type strings
entity.immunities:  list[str]
entity.vulnerabilities: list[str]
entity.take_damage(amount, dmg_type) → int
entity.heal(amount) → int
```

---

## YOUR TASK

### Output File 1: `engine/spells.py`

Implement the following **in this exact structure**:

#### Part A — Enums & Dataclasses

```python
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
```

#### Part B — Spellcasting Ability Helper

```python
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
```

#### Part C — SPELL_REGISTRY

```python
SPELL_REGISTRY: dict[str, Spell] = {}

def _reg(spell: Spell) -> None:
    SPELL_REGISTRY[spell.key] = spell

# ── 여기서부터 모든 SRD 스펠을 등록 ──────────────────────────────────────
# SRD Spells_A.md ~ Spells_Z.md 를 읽고 모든 스펠 구현
# 전투에 관련없는 의식(ritual) 스펠, 순수 유틸리티(Identify, Prestidigitation 등)도
# 등록하되 components=[] 로 비워두고 description만 채울 것

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

# ... 나머지 모든 SRD 스펠 구현 ...
```

**중요 구현 규칙:**
1. `effect_key`는 반드시 아래 목록 중 하나이거나, Part D에서 새로 _TEMPLATES에 추가한 것이어야 함
   - 기존: `prone, stunned, frightened, grappled, restrained, poisoned, charmed, incapacitated, unconscious, blinded, deafened, paralyzed, petrified, bless, bane, haste, hex, hunters_mark, shield_of_faith`
   - 새로 필요하면 Part D에서 추가
2. `dice` 필드에서 `{spellmod}` 는 실제 숫자로 치환됨 (SpellResolver가 처리)
3. 집중 스펠은 `concentration=True` + `TickOn.CONCENTRATION` effect 사용
4. 캔트립(level=0)은 spell slot 소모 없음
5. 힐링 스펠: `kind="heal"`, `dice="1d8+{spellmod}"`

#### Part D — New Effect Templates (if needed)

If a spell needs an effect_key not in the existing `_TEMPLATES`, define it here
and mention it must be added to `_TEMPLATES` in `conditions.py`:

```python
# 기존 _TEMPLATES에 추가 필요한 새 effect 정의
NEW_EFFECT_TEMPLATES = {
    # 예시 — 실제 필요한 것만 추가
    "banished": dict(
        display="추방",
        tags=frozenset({"banished", "incapacitated"}),
        stack_rule=StackRule.IGNORE, tick_on=TickOn.CONCENTRATION,
        modifiers={"can_act": False, "can_react": False, "can_move": False},
    ),
    "turned": dict(
        display="격퇴",
        tags=frozenset({"turned"}),
        stack_rule=StackRule.IGNORE, tick_on=TickOn.TURN_END,
        modifiers={"attack_dis": True},
    ),
    # ... 필요한 것 모두 추가
}
```

#### Part E — SpellResolver

```python
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

        reward = total_dmg / max(1, sum(e.max_hp for e in resolved_targets if e in [t for t in resolved_targets]))
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
```

---

### Output File 2: Entity additions

At the bottom of `engine/entity.py`, inside the `Entity` dataclass,
add these fields AFTER the `fighter_*` fields:

```python
# ── 주문 시전 (SPELLCASTING) ─────────────────────────────────────────────
spell_slots:       dict = field(default_factory=dict)  # {slot_level(int): slots_remaining(int)}
spell_ability:     str  = "int"   # "int" | "wis" | "cha"
proficiency_bonus: int  = 2       # 캐릭터 레벨 기반 (기본 2)
known_spells:      list = field(default_factory=list)  # [spell_key strings]
_concentrating:    str  = ""      # 현재 집중 중인 spell_key ("" = 없음)
```

Also add this method to Entity:
```python
def use_spell_slot(self, level: int) -> bool:
    """슬롯 소모. 성공 시 True. 캔트립(level=0)은 항상 True."""
    if level == 0:
        return True
    if self.spell_slots.get(level, 0) > 0:
        self.spell_slots[level] -= 1
        return True
    # 상위 슬롯으로 폴백
    for lv in range(level + 1, 10):
        if self.spell_slots.get(lv, 0) > 0:
            self.spell_slots[lv] -= 1
            return True
    return False

def concentration_check(self, damage_taken: int) -> bool:
    """피해 시 집중 판정. DC = max(10, damage//2). CON 세이브."""
    if not self._concentrating:
        return True
    dc = max(10, damage_taken // 2)
    from .dice import roll_save
    save_q = self.effects.query_save()
    result = roll_save(self.con_mod + save_q.bonus, dc,
                       adv=save_q.advantage, dis=save_q.disadvantage)
    if not result["success"]:
        self._concentrating = ""
        # 집중 효과 해제는 TurnManager에서 all_entities 순회로 처리
    return result["success"]
```

---

### Output File 3: `engine/actions.py` additions

Add to the `Action` enum:
```python
CAST_SPELL = auto()
```

---

### Output File 4: Turn Manager additions

In `TurnManager.step()`, add handling for `Action.CAST_SPELL`:

```python
elif action == Action.CAST_SPELL:
    # target_uid can be a string of comma-separated UIDs for multi-target
    # spell_key and slot_level come from extra kwargs (extend step signature)
    result = self._do_cast_spell(actor, target_uid, **kwargs)
```

Add this method to TurnManager:
```python
def _do_cast_spell(self, actor: Entity, target_uid: Optional[str],
                   spell_key: str = "", slot_level: int = 1) -> ActionResult:
    from .spells import SpellResolver, SPELL_REGISTRY, CastingTime
    if actor.action_used:
        return ActionResult(actor.uid, Action.CAST_SPELL, False, 0.0,
                            f"{actor.name} 이미 행동 사용")
    spell = SPELL_REGISTRY.get(spell_key)
    if spell is None:
        return ActionResult(actor.uid, Action.CAST_SPELL, False, 0.0,
                            f"알 수 없는 스펠: {spell_key}")
    if not actor.use_spell_slot(spell.level if slot_level < spell.level else slot_level):
        return ActionResult(actor.uid, Action.CAST_SPELL, False, 0.0,
                            f"{actor.name} 슬롯 부족")

    # 대상 목록 구성
    targets = []
    if target_uid:
        for uid in target_uid.split(","):
            t = self.state.get_by_uid(uid.strip())
            if t:
                targets.append(t)

    resolver = SpellResolver()
    spell_result = resolver.resolve(
        caster=actor, spell_key=spell_key,
        slot_level=slot_level,
        targets=targets,
        all_entities=self.state.combatants,
    )

    # 집중 실패 전파: 피해가 있는 경우 각 피해받은 엔티티의 집중 체크
    for e in self.state.combatants:
        if e.is_alive and e._concentrating:
            hp_after = e.hp
            # 피해를 받은 시전자가 집중 체크 필요한 경우 (간단히: spell_result.total_damage 기준)
            pass  # 정밀 구현은 _apply_component 내에서 take_damage 후 호출

    if spell.casting_time == CastingTime.ACTION:
        actor.action_used = True
    elif spell.casting_time == CastingTime.BONUS_ACTION:
        actor.bonus_action_used = True

    return ActionResult(
        actor.uid, Action.CAST_SPELL,
        spell_result.success, spell_result.reward,
        spell_result.log, target_uid, spell_result.total_damage
    )
```

---

## IMPLEMENTATION GUIDELINES

### Priority (implement these first):
1. **Damage spells** — Fireball, Magic Missile, Thunderwave, Lightning Bolt, Ice Storm, etc.
2. **Condition spells** — Hold Person, Hold Monster, Blindness/Deafness, Web, Entangle, etc.
3. **Healing spells** — Cure Wounds, Healing Word, Mass Cure Wounds, etc.
4. **Buff/Debuff** — Bless, Bane, Haste, Slow, etc.
5. **Concentration control** — Concentration already handled by `break_concentration()`

### Simplification rules (RL 환경 단순화):
- 복잡한 스펠 상호작용은 가장 핵심 효과만 구현 (피해 + 메인 컨디션)
- "까지 X피트 이동" 같은 이동 효과는 push 컴포넌트로 단순화
- 소환 스펠 (Summon Undead 등)은 `components=[]`로 비워두고 description만 채움
- 지속시간 "집중, 최대 1분" → `concentration=True`, `duration=10` (10턴)
- "1분" = 10턴, "1시간" = 600턴, "8시간" = 4800턴

### Spell DC formula:
```
DC = 8 + proficiency_bonus + spellcasting_modifier
```
→ `get_spell_dc(caster)` 함수가 이미 구현되어 있음

### Damage type strings (use exactly these):
`"fire"`, `"cold"`, `"lightning"`, `"thunder"`, `"acid"`, `"poison"`,
`"necrotic"`, `"radiant"`, `"force"`, `"psychic"`,
`"bludgeoning"`, `"piercing"`, `"slashing"`

---

## EXPECTED OUTPUT

1. `engine/spells.py` — 완성된 전체 파일 (모든 SRD 스펠 포함)
2. `engine/entity.py` — spell 관련 필드/메서드 추가된 전체 파일
3. `engine/actions.py` — CAST_SPELL 추가된 전체 파일
4. `engine/turn_manager.py` — _do_cast_spell 추가된 전체 파일
5. `engine/conditions.py` — NEW_EFFECT_TEMPLATES의 항목들이 _TEMPLATES에 추가된 전체 파일

**각 파일은 전체 내용(full file)으로 출력할 것. diff나 일부 발췌 금지.**

---

## FINAL NOTE

The codebase is for a reinforcement learning training environment.
Correctness > Completeness > Performance.
When in doubt, implement the most common/impactful interpretation of a spell.
Every implemented spell must be runnable Python without errors.
