# 출처: LET_THERE_BE_OATS/server/engine/actions.py (OAT_PULSE 제거)
from enum import IntEnum
from dataclasses import dataclass
from typing import Optional


class Action(IntEnum):
    MOVE_N  = 0
    MOVE_S  = 1
    MOVE_E  = 2
    MOVE_W  = 3
    ATTACK        = 4
    DODGE         = 5
    WAIT          = 6
    RANGED_ATTACK = 7
    HEAL_ALLY     = 8
    DISENGAGE     = 9
    RAGE          = 10
    DASH          = 11
    SECOND_WIND   = 12   # 파이터 1레벨: 1d10+레벨 회복 (보조 행동)
    HELP          = 13
    GRAPPLE       = 14
    SHOVE         = 15
    ACTION_SURGE  = 16   # 파이터 2레벨+: 이번 턴 주행동 추가 부여 (보조 행동)
    CAST_SPELL    = 17   # 주문 시전

    NORTH = 0
    SOUTH = 1
    EAST  = 2
    WEST  = 3


ACTION_NAMES: dict[Action, str] = {
    Action.MOVE_N:        "북쪽 이동",
    Action.MOVE_S:        "남쪽 이동",
    Action.MOVE_E:        "동쪽 이동",
    Action.MOVE_W:        "서쪽 이동",
    Action.ATTACK:        "근접 공격",
    Action.DODGE:         "회피",
    Action.WAIT:          "대기",
    Action.RANGED_ATTACK: "원거리 공격",
    Action.HEAL_ALLY:     "아군 치료",
    Action.DISENGAGE:     "이탈",
    Action.RAGE:          "분노",
    Action.DASH:          "전력 질주",
    Action.SECOND_WIND:   "[Fighter] 세컨드 윈드 (1d10+레벨 HP 회복)",
    Action.HELP:          "도움",
    Action.GRAPPLE:       "움켜잡기",
    Action.SHOVE:         "밀치기",
    Action.ACTION_SURGE:  "[Fighter] 액션 서지 (주행동 추가 회동)",
    Action.CAST_SPELL:    "주문 시전",
}

MOVE_DELTAS: dict[Action, tuple[int, int]] = {
    Action.MOVE_N: (0, -1),
    Action.MOVE_S: (0, +1),
    Action.MOVE_E: (+1, 0),
    Action.MOVE_W: (-1, 0),
}

MOVE_ACTIONS = {Action.MOVE_N, Action.MOVE_S, Action.MOVE_E, Action.MOVE_W}


@dataclass
class ActionResult:
    entity_uid: str
    action: Action
    success: bool
    reward: float
    log: str
    target_uid: Optional[str] = None
    damage: int = 0
    healed: int = 0
