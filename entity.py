# 출처: LET_THERE_BE_OATS/server/engine/entity.py (버섯/WeaponEntity 의존성 제거)
from __future__ import annotations

import json
from dataclasses import dataclass, field
from enum import Enum, auto
from pathlib import Path
from typing import Optional

from .conditions import EffectManager


# ==========================================
# 🛡️ [구역 0] 파이터 클래스 열거형 (FIGHTER ENUMS)
# ==========================================

class FightingStyle(Enum):
    """D&D 5e Fighter 전투 스타일 선택지."""
    NONE           = auto()  # 선택 없음
    ARCHERY        = auto()  # 원거리 공격 굴림 +2
    DEFENSE        = auto()  # 방어구 착용 시 AC +1
    DUELING        = auto()  # 한손 무기 피해 +2
    GREAT_WEAPON   = auto()  # 양손 무기 1,2 굴림 리롤
    PROTECTION     = auto()  # 반응으로 인접 아군 공격에 디스어드밴티지 부여 (단순화: 패시브 DR 1)
    TWO_WEAPON     = auto()  # 양손 무기: 두 번째 공격에 능력치 modifier 적용

SRD_SIZE_TILES = {
    "tiny": 1, "small": 1, "medium": 1,
    "large": 2, "huge": 3, "gargantuan": 4,
}

_UNITS_PATH = Path(__file__).parent.parent / "data" / "units.json"
_UNITS_BY_NAME: dict[str, dict] = {}

def _load_units() -> None:
    if _UNITS_BY_NAME:
        return
    units = json.loads(_UNITS_PATH.read_text(encoding="utf-8"))
    for u in units:
        _UNITS_BY_NAME[u["name"].lower()] = u

def mod(score: int) -> int:
    return (score - 10) // 2


@dataclass
class Entity:
    uid:     str
    name:    str
    faction: str   # "player" | "enemy"

    max_hp: int
    hp:     int
    ac:     int
    speed:  int
    cr:     float

    str_score: int
    dex_score: int
    con_score: int
    int_score: int
    wis_score: int
    cha_score: int

    attacks: list = field(default_factory=list)

    size:       str = "medium"
    size_tiles: int = 1
    unit_type:  str = "humanoid"

    x: int = 0
    y: int = 0

    movement_remaining: int = 0
    action_used:        bool = False
    bonus_action_used:  bool = False

    effects: EffectManager = field(default_factory=EffectManager)

    resistances:    list[str] = field(default_factory=list)
    immunities:     list[str] = field(default_factory=list)
    vulnerabilities: list[str] = field(default_factory=list)
    death_saves:    dict = field(default_factory=lambda: {"success": 0, "fail": 0})

    dnd_class: str = "monster"
    level:     int = 1

    # ==========================================
    # 🛡️ [구역 - 파이터 클래스 특성] FIGHTER FEATURES
    # ==========================================
    # D&D 5e 파이터 전용 상태 변수 (fighter_ 접두사 강제)
    # 전투 시작 시 초기화, 단/장휴식 시 reset 훅으로 리셋
    fighter_fighting_style:     FightingStyle = field(default=FightingStyle.NONE)
    fighter_second_wind_used:   bool = False   # 단휴식 충전
    fighter_action_surge_used:  bool = False   # 단휴식 충전 (17레벨: 2회 → 단순화: 1회)
    fighter_indomitable_uses:   int  = 0       # 장휴식 충전. 9레벨+에서 사용 가능
    fighter_attacks_this_turn:  int  = 0       # 이번 턴 공격 횟수 추적 (Extra Attack용)
    fighter_action_surged:      bool = False   # 이번 턴 액션 서지 이미 소모했는지

    # ── 주문 시전 (SPELLCASTING) ─────────────────────────────────────────────
    spell_slots:       dict = field(default_factory=dict)  # {slot_level(int): slots_remaining(int)}
    spell_ability:     str  = "int"   # "int" | "wis" | "cha"
    proficiency_bonus: int  = 2       # 캐릭터 레벨 기반 (기본 2)
    known_spells:      list = field(default_factory=list)  # [spell_key strings]
    _concentrating:    str  = ""      # 현재 집중 중인 spell_key ("" = 없음)

    # ── 파생 속성 ──────────────────────────────────────────────────────────
    @property
    def is_alive(self) -> bool:
        return self.hp > 0

    @property
    def str_mod(self) -> int: return mod(self.str_score)
    @property
    def dex_mod(self) -> int: return mod(self.dex_score)
    @property
    def con_mod(self) -> int: return mod(self.con_score)
    @property
    def int_mod(self) -> int: return mod(self.int_score)
    @property
    def wis_mod(self) -> int: return mod(self.wis_score)
    @property
    def cha_mod(self) -> int: return mod(self.cha_score)

    def take_damage(self, amount: int, dmg_type: str = "") -> int:
        if dmg_type and dmg_type in self.immunities:
            return 0
        if dmg_type and dmg_type in self.resistances:
            amount = amount // 2
        if dmg_type and dmg_type in self.vulnerabilities:
            amount = amount * 2
        actual = min(self.hp, amount)
        self.hp = max(0, self.hp - amount)
        return actual

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

    def heal(self, amount: int) -> int:
        actual = min(amount, self.max_hp - self.hp)
        self.hp += actual
        return actual

    def reset_turn(self) -> None:
        self.movement_remaining = self.speed // 5   # ft → 타일 (1타일=5ft)
        self.action_used       = False
        self.bonus_action_used = False
        # 파이터 턴 단위 상태 초기화
        self.fighter_attacks_this_turn = 0
        self.fighter_action_surged     = False

    def fighter_on_short_rest(self) -> None:
        """단휴식(Short Rest): Second Wind, Action Surge 충전."""
        if self.dnd_class == "Fighter":
            self.fighter_second_wind_used  = False
            self.fighter_action_surge_used = False
            print(f"[Fighter Debug] {self.name} — Short Rest 완료: Second Wind, Action Surge 충전됨")

    def fighter_on_long_rest(self) -> None:
        """장휴식(Long Rest): 모든 파이터 특성 완전 충전."""
        if self.dnd_class == "Fighter":
            self.fighter_second_wind_used  = False
            self.fighter_action_surge_used = False
            self.fighter_indomitable_uses  = 0
            print(f"[Fighter Debug] {self.name} — Long Rest 완료: 모든 파이터 특성 충전됨")

    def fighter_get_extra_attack_count(self) -> int:
        """레벨에 따른 1회 Attack 액션당 최대 공격 횟수."""
        if self.dnd_class != "Fighter":
            return 1
        if   self.level >= 20: return 4
        elif self.level >= 11: return 3
        elif self.level >= 5:  return 2
        return 1

    def fighter_get_indomitable_max(self) -> int:
        """Indomitable 최대 사용 횟수 (레벨별)."""
        if self.dnd_class != "Fighter" or self.level < 9:
            return 0
        if   self.level >= 17: return 3
        elif self.level >= 13: return 2
        return 1

    def fighter_can_use_indomitable(self) -> bool:
        return self.fighter_indomitable_uses < self.fighter_get_indomitable_max()

    def fighter_get_ac_bonus(self) -> int:
        """Defense 전투 스타일: 방어구 착용 시 AC +1."""
        if self.fighter_fighting_style == FightingStyle.DEFENSE:
            return 1
        return 0

    def fighter_get_ranged_attack_bonus(self) -> int:
        """Archery 전투 스타일: 원거리 공격 +2."""
        if self.fighter_fighting_style == FightingStyle.ARCHERY:
            return 2
        return 0

    def fighter_get_melee_damage_bonus(self) -> int:
        """Dueling 전투 스타일: 한손 무기 피해 +2."""
        if self.fighter_fighting_style == FightingStyle.DUELING:
            return 2
        return 0

    # ── 생성자 ─────────────────────────────────────────────────────────────
    @classmethod
    def from_unit_data(cls, uid: str, unit: dict, faction: str,
                       x: int = 0, y: int = 0) -> "Entity":
        size = unit.get("size", "Medium").lower()
        return cls(
            uid=uid, name=unit["name"], faction=faction,
            max_hp=unit["hp_avg"], hp=unit["hp_avg"],
            ac=unit["ac"], speed=unit["speed_ft"], cr=unit["cr"],
            str_score=unit["str"], dex_score=unit["dex"], con_score=unit["con"],
            int_score=unit["int"], wis_score=unit["wis"], cha_score=unit["cha"],
            attacks=unit.get("actions", []),
            size=size, size_tiles=SRD_SIZE_TILES.get(size, 1),
            unit_type=unit.get("type", "humanoid"),
            resistances=unit.get("damage_resistances", []),
            immunities=unit.get("damage_immunities", []),
            vulnerabilities=unit.get("damage_vulnerabilities", []),
            x=x, y=y,
        )

    @classmethod
    def from_srd_name(cls, uid: str, name: str, faction: str,
                      x: int = 0, y: int = 0) -> "Entity":
        _load_units()
        unit = _UNITS_BY_NAME.get(name.lower())
        if unit is None:
            raise KeyError(f"SRD에서 '{name}' 유닛을 찾을 수 없음")
        return cls.from_unit_data(uid, unit, faction, x, y)
