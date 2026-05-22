"""
engine/conditions.py  ·  D&D 5e Condition & Effect Manager

버프/디버프/컨디션 통합 관리.
  지속시간 타이밍 : TURN_START, TURN_END, ROUND_END, CONCENTRATION, PERMANENT
  중복/갱신 규칙  : IGNORE, REFRESH, STACK, REPLACE
  판정 훅         : 공격 굴림 / 피해 / 세이브 / 이동
"""
from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum, auto
from typing import Optional


# ── 1. 지속시간 타이밍 ────────────────────────────────────────────────────

class TickOn(Enum):
    PERMANENT     = auto()  # 수동 제거만 (세이브·이탈 등)
    TURN_START    = auto()  # 이 엔티티의 턴 시작 시 감소
    TURN_END      = auto()  # 이 엔티티의 턴 종료 시 감소
    ROUND_END     = auto()  # 전원 행동 후 라운드 종료 시 감소
    CONCENTRATION = auto()  # 집중 유지 중 — 피해 시 CON 체크로 해제


# ── 2. 중복/갱신 규칙 ─────────────────────────────────────────────────────

class StackRule(Enum):
    IGNORE   = auto()  # 이미 있으면 새 적용 무시
    REFRESH  = auto()  # duration 갱신 (더 긴 쪽 유지)
    STACK    = auto()  # source가 다르면 별도 인스턴스 허용
    REPLACE  = auto()  # 항상 새것으로 교체


# ── 3. 판정 쿼리 컨텍스트 ─────────────────────────────────────────────────

@dataclass
class AttackRollQuery:
    """공격 굴림 수정자 (아웃고잉 또는 인커밍)."""
    advantage:    bool = False
    disadvantage: bool = False
    bonus:        int  = 0

    def mode(self) -> str:
        """'adv' | 'dis' | 'normal' — adv·dis 상쇄 규칙 적용."""
        if self.advantage and not self.disadvantage:
            return "adv"
        if self.disadvantage and not self.advantage:
            return "dis"
        return "normal"


@dataclass
class DamageQuery:
    """피해 수정자."""
    bonus:      int   = 0
    multiplier: float = 1.0
    auto_crit:  bool  = False  # Unconscious·Paralyzed: 근접 명중 자동 크리티컬


@dataclass
class SaveQuery:
    """내성 굴림 수정자."""
    advantage:    bool = False
    disadvantage: bool = False
    bonus:        int  = 0
    auto_fail:    bool = False  # Stunned·Paralyzed·Unconscious: STR/DEX 자동 실패


@dataclass
class MovementQuery:
    """이동 수정자."""
    blocked:    bool  = False  # True = 속도 0
    speed_mult: float = 1.0


# ── 4. Effect 데이터 ──────────────────────────────────────────────────────

@dataclass
class Effect:
    """단일 버프/디버프/컨디션 인스턴스.

    modifiers 키 규약
    ─────────────────
    bool flags : can_act, can_react, can_move
                 attack_adv, attack_dis
                 attacked_adv, attacked_dis
                 save_adv, save_dis, save_auto_fail
                 auto_crit
    int/float  : attack_bonus, ac_bonus
                 damage_bonus, damage_mult
                 speed_mult
    """
    key:        str
    display:    str
    source_uid: str        = ""
    duration:   int        = -1              # -1 = 무한
    tick_on:    TickOn     = TickOn.TURN_END
    stack_rule: StackRule  = StackRule.REFRESH
    tags:       frozenset  = field(default_factory=frozenset)
    modifiers:  dict       = field(default_factory=dict)

    def has_tag(self, tag: str) -> bool:
        return tag in self.tags

    def tick(self) -> bool:
        """duration 1 감소. True = 만료됨."""
        if self.duration < 0:
            return False
        self.duration -= 1
        return self.duration <= 0

    def refresh_from(self, other: "Effect") -> None:
        """REFRESH: 더 긴 duration으로 갱신. source_uid는 원본 소유자 유지."""
        if other.duration < 0 or (self.duration >= 0 and other.duration > self.duration):
            self.duration = other.duration


# ── 5. EffectManager ─────────────────────────────────────────────────────

class EffectManager:
    """Entity에 부착된 모든 Effect 통합 관리자."""

    __slots__ = ("_effects",)

    def __init__(self) -> None:
        self._effects: list[Effect] = []

    # ── CRUD ────────────────────────────────────────────────────────────

    def add(self, effect: Effect) -> None:
        """Effect 추가. stack_rule에 따라 중복 처리."""
        rule = effect.stack_rule

        if rule == StackRule.STACK:
            # 같은 key + 같은 source → 갱신, 다른 source → 별도 추가
            same_src = self._find(effect.key, effect.source_uid)
            if same_src:
                same_src.refresh_from(effect)
            else:
                self._effects.append(effect)
            return

        existing = self._find(effect.key, None)

        if existing is None:
            self._effects.append(effect)
            return

        if   rule == StackRule.IGNORE:  return
        elif rule == StackRule.REFRESH: existing.refresh_from(effect)
        elif rule == StackRule.REPLACE:
            self._effects.remove(existing)
            self._effects.append(effect)

    def remove(self, key: str, source_uid: str = "") -> None:
        """key (+ 선택적 source_uid) 로 effect 제거."""
        if source_uid:
            self._effects = [e for e in self._effects
                             if not (e.key == key and e.source_uid == source_uid)]
        else:
            self._effects = [e for e in self._effects if e.key != key]

    def clear(self) -> None:
        self._effects.clear()

    def has(self, key: str) -> bool:
        return any(e.key == key for e in self._effects)

    def has_tag(self, tag: str) -> bool:
        return any(e.has_tag(tag) for e in self._effects)

    def all_effects(self) -> list[Effect]:
        return list(self._effects)

    def _find(self, key: str, source_uid: Optional[str]) -> Optional[Effect]:
        for e in self._effects:
            if e.key == key:
                if source_uid is None or e.source_uid == source_uid:
                    return e
        return None

    # ── 틱 처리 ─────────────────────────────────────────────────────────

    def _tick(self, timing: TickOn) -> list[str]:
        """지정 타이밍의 duration 감소. 만료된 display명 목록 반환."""
        expired, remaining = [], []
        for e in self._effects:
            if e.tick_on == timing:
                if e.tick():
                    expired.append(e.display or e.key)
                else:
                    remaining.append(e)
            else:
                remaining.append(e)
        self._effects = remaining
        return expired

    def tick_turn_start(self) -> list[str]:
        """이 엔티티 턴 시작 시 호출."""
        return self._tick(TickOn.TURN_START)

    def tick_turn_end(self) -> list[str]:
        """이 엔티티 턴 종료 시 호출."""
        return self._tick(TickOn.TURN_END)

    def tick_round_end(self) -> list[str]:
        """라운드 종료 시 호출."""
        return self._tick(TickOn.ROUND_END)

    # ── 판정 훅 ─────────────────────────────────────────────────────────

    def query_can_act(self) -> bool:
        return all(e.modifiers.get("can_act", True) for e in self._effects)

    def query_can_react(self) -> bool:
        return all(e.modifiers.get("can_react", True) for e in self._effects)

    def query_can_move(self) -> bool:
        return not self.query_movement().blocked

    def query_attack_roll(self) -> AttackRollQuery:
        """아웃고잉 공격 굴림 수정자."""
        q = AttackRollQuery()
        for e in self._effects:
            m = e.modifiers
            if m.get("attack_adv"): q.advantage    = True
            if m.get("attack_dis"): q.disadvantage = True
            q.bonus += int(m.get("attack_bonus", 0))
        return q

    def query_attacked_roll(self) -> AttackRollQuery:
        """인커밍 공격 굴림 수정자 (이 엔티티가 공격받을 때)."""
        q = AttackRollQuery()
        for e in self._effects:
            m = e.modifiers
            if m.get("attacked_adv"): q.advantage    = True
            if m.get("attacked_dis"): q.disadvantage = True
        return q

    def query_damage_out(self) -> DamageQuery:
        """아웃고잉 피해 수정자."""
        q = DamageQuery()
        for e in self._effects:
            m = e.modifiers
            q.bonus      += int(m.get("damage_bonus", 0))
            q.multiplier *= float(m.get("damage_mult", 1.0))
        return q

    def query_damage_in(self) -> DamageQuery:
        """인커밍 피해 수정자 (자동 크리티컬 등)."""
        q = DamageQuery()
        for e in self._effects:
            if e.modifiers.get("auto_crit"):
                q.auto_crit = True
        return q

    def query_save(self) -> SaveQuery:
        """내성 굴림 수정자."""
        q = SaveQuery()
        for e in self._effects:
            m = e.modifiers
            if m.get("save_adv"):       q.advantage    = True
            if m.get("save_dis"):       q.disadvantage = True
            if m.get("save_auto_fail"): q.auto_fail    = True
            q.bonus += int(m.get("save_bonus", 0))
        return q

    def query_movement(self) -> MovementQuery:
        """이동 수정자."""
        q = MovementQuery()
        for e in self._effects:
            m = e.modifiers
            if not m.get("can_move", True):
                q.blocked = True
            mult = float(m.get("speed_mult", 1.0))
            if mult < q.speed_mult:
                q.speed_mult = mult
        return q

    def query_ac_bonus(self) -> int:
        return sum(int(e.modifiers.get("ac_bonus", 0)) for e in self._effects)

    # ── 집중 관련 ────────────────────────────────────────────────────────

    def break_concentration(self, source_uid: str = "") -> list[str]:
        """집중 해제: CONCENTRATION effect 제거. 제거된 key 목록 반환."""
        to_remove = [e for e in self._effects
                     if e.tick_on == TickOn.CONCENTRATION
                     and (not source_uid or e.source_uid == source_uid)]
        for e in to_remove:
            self._effects.remove(e)
        return [e.key for e in to_remove]

    # ── 직렬화 ──────────────────────────────────────────────────────────

    def to_list(self) -> list[str]:
        """RL 관측 직렬화 (effect key 목록)."""
        return [e.key for e in self._effects]


# ── 6. D&D 5e 컨디션 / 버프 템플릿 ──────────────────────────────────────

class Condition(Enum):
    """D&D 5e 표준 컨디션 열거형."""
    PRONE         = "prone"
    STUNNED       = "stunned"
    FRIGHTENED    = "frightened"
    GRAPPLED      = "grappled"
    RESTRAINED    = "restrained"
    POISONED      = "poisoned"
    CHARMED       = "charmed"
    INCAPACITATED = "incapacitated"
    UNCONSCIOUS   = "unconscious"
    BLINDED       = "blinded"
    DEAFENED      = "deafened"
    PARALYZED     = "paralyzed"
    PETRIFIED     = "petrified"
    EXHAUSTION    = "exhaustion"


_TEMPLATES: dict[str, dict] = {

    # ── D&D 5e 표준 컨디션 ────────────────────────────────────────────────
    "prone": dict(
        display="엎드림",
        tags=frozenset({"prone"}),
        stack_rule=StackRule.IGNORE, tick_on=TickOn.PERMANENT,
        modifiers={"attack_dis": True, "attacked_adv": True},
    ),
    "stunned": dict(
        display="기절",
        tags=frozenset({"stunned", "incapacitated"}),
        stack_rule=StackRule.IGNORE, tick_on=TickOn.TURN_END,
        modifiers={"can_act": False, "can_react": False,
                   "attacked_adv": True, "save_dis": True},
    ),
    "frightened": dict(
        display="공포",
        tags=frozenset({"frightened"}),
        stack_rule=StackRule.STACK, tick_on=TickOn.TURN_END,
        modifiers={"attack_dis": True},
    ),
    "grappled": dict(
        display="움켜잡힘",
        tags=frozenset({"grappled"}),
        stack_rule=StackRule.STACK, tick_on=TickOn.PERMANENT,
        modifiers={"can_move": False},
    ),
    "restrained": dict(
        display="속박",
        tags=frozenset({"restrained"}),
        stack_rule=StackRule.IGNORE, tick_on=TickOn.PERMANENT,
        modifiers={"can_move": False, "attack_dis": True,
                   "attacked_adv": True, "save_dis": True},
    ),
    "poisoned": dict(
        display="중독",
        tags=frozenset({"poisoned"}),
        stack_rule=StackRule.IGNORE, tick_on=TickOn.TURN_END,
        modifiers={"attack_dis": True},
    ),
    "charmed": dict(
        display="매료",
        tags=frozenset({"charmed"}),
        stack_rule=StackRule.STACK, tick_on=TickOn.TURN_END,
        modifiers={},
    ),
    "incapacitated": dict(
        display="무력화",
        tags=frozenset({"incapacitated"}),
        stack_rule=StackRule.IGNORE, tick_on=TickOn.TURN_END,
        modifiers={"can_act": False, "can_react": False},
    ),
    "unconscious": dict(
        display="의식불명",
        tags=frozenset({"unconscious", "incapacitated", "prone"}),
        stack_rule=StackRule.IGNORE, tick_on=TickOn.PERMANENT,
        modifiers={"can_act": False, "can_react": False, "can_move": False,
                   "attacked_adv": True, "auto_crit": True, "save_auto_fail": True},
    ),
    "blinded": dict(
        display="실명",
        tags=frozenset({"blinded"}),
        stack_rule=StackRule.IGNORE, tick_on=TickOn.TURN_END,
        modifiers={"attack_dis": True, "attacked_adv": True},
    ),
    "deafened": dict(
        display="청각 장애",
        tags=frozenset({"deafened"}),
        stack_rule=StackRule.IGNORE, tick_on=TickOn.TURN_END,
        modifiers={},
    ),
    "paralyzed": dict(
        display="마비",
        tags=frozenset({"paralyzed", "incapacitated"}),
        stack_rule=StackRule.IGNORE, tick_on=TickOn.TURN_END,
        modifiers={"can_act": False, "can_react": False, "can_move": False,
                   "attacked_adv": True, "auto_crit": True, "save_auto_fail": True},
    ),
    "petrified": dict(
        display="석화",
        tags=frozenset({"petrified", "incapacitated"}),
        stack_rule=StackRule.IGNORE, tick_on=TickOn.PERMANENT,
        modifiers={"can_act": False, "can_react": False, "can_move": False,
                   "attacked_adv": True, "auto_crit": True},
    ),
    "exhaustion_1": dict(
        display="탈진 1단계",
        tags=frozenset({"exhaustion"}),
        stack_rule=StackRule.REPLACE, tick_on=TickOn.PERMANENT,
        modifiers={"attack_dis": True},
    ),

    # ── 전투 액션 부산물 ──────────────────────────────────────────────────
    "dodge_stance": dict(
        # Dodge 액션: 다음 자신의 턴 시작 전까지 incoming 공격에 dis, DEX 세이브에 adv
        display="회피 태세",
        tags=frozenset({"dodge"}),
        stack_rule=StackRule.REPLACE, tick_on=TickOn.TURN_START,
        modifiers={"attacked_dis": True, "save_adv": True},
    ),
    "help_advantage": dict(
        # Help 액션: 대상의 다음 공격에 어드밴티지
        display="도움 (어드밴티지)",
        tags=frozenset({"help"}),
        stack_rule=StackRule.IGNORE, tick_on=TickOn.TURN_START,
        modifiers={"attack_adv": True},
    ),

    # ── 주문/버프 예시 (집중) ─────────────────────────────────────────────
    "bless": dict(
        display="축복 (Bless)",
        tags=frozenset({"bless", "buff"}),
        stack_rule=StackRule.REFRESH, tick_on=TickOn.CONCENTRATION,
        modifiers={"attack_bonus": 2, "save_bonus": 2},   # 1d4 평균 ≈ 2
    ),
    "bane": dict(
        display="저주 (Bane)",
        tags=frozenset({"bane", "debuff"}),
        stack_rule=StackRule.REFRESH, tick_on=TickOn.CONCENTRATION,
        modifiers={"attack_bonus": -2, "save_bonus": -2},
    ),
    "haste": dict(
        display="신속 (Haste)",
        tags=frozenset({"haste", "buff"}),
        stack_rule=StackRule.REFRESH, tick_on=TickOn.CONCENTRATION,
        modifiers={"speed_mult": 2.0, "ac_bonus": 2, "attack_adv": True},
    ),
    "hex": dict(
        display="저주 (Hex)",
        tags=frozenset({"hex", "curse"}),
        stack_rule=StackRule.STACK, tick_on=TickOn.CONCENTRATION,
        modifiers={"damage_bonus": 3},   # 1d6 평균
    ),
    "hunters_mark": dict(
        display="사냥꾼의 표식",
        tags=frozenset({"hunters_mark"}),
        stack_rule=StackRule.REPLACE, tick_on=TickOn.CONCENTRATION,
        modifiers={"damage_bonus": 3},
    ),
    "shield_of_faith": dict(
        display="믿음의 방패",
        tags=frozenset({"buff"}),
        stack_rule=StackRule.REFRESH, tick_on=TickOn.CONCENTRATION,
        modifiers={"ac_bonus": 2},
    ),
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
}


def make_effect(key: str,
                duration: int = -1,
                source_uid: str = "",
                tick_on: Optional[TickOn] = None) -> Effect:
    """등록된 템플릿으로 Effect 인스턴스 생성."""
    tmpl = _TEMPLATES.get(key)
    if tmpl is None:
        raise KeyError(f"알 수 없는 effect 키: '{key}'")
    t = dict(tmpl)
    effective_tick = tick_on if tick_on is not None else t.pop("tick_on", TickOn.TURN_END)
    return Effect(key=key, duration=duration, source_uid=source_uid,
                  tick_on=effective_tick, **t)


def make_condition(condition: Condition,
                   duration: int = -1,
                   source_uid: str = "") -> Effect:
    """D&D 표준 컨디션 Effect 생성 편의 함수."""
    return make_effect(condition.value, duration=duration, source_uid=source_uid)
