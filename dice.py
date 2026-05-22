# 출처: LET_THERE_BE_OATS/server/engine/dice.py (정리)
# d20 라이브러리 기반 D&D 5e 주사위 시스템
import d20
import torch
import torch.nn.functional as F


def roll_attack(attack_bonus: int, adv: bool = False, dis: bool = False) -> dict:
    if adv and not dis:
        r1, r2 = d20.roll("1d20").total, d20.roll("1d20").total
        die, mode = max(r1, r2), f"ADV({r1},{r2})"
    elif dis and not adv:
        r1, r2 = d20.roll("1d20").total, d20.roll("1d20").total
        die, mode = min(r1, r2), f"DIS({r1},{r2})"
    else:
        die, mode = d20.roll("1d20").total, "STD"

    total = die + attack_bonus
    sign = f"+{attack_bonus}" if attack_bonus >= 0 else str(attack_bonus)
    crit, fumble = die == 20, die == 1
    suffix = " *CRIT*" if crit else (" *FUMBLE*" if fumble else "")
    return {
        "die": die, "bonus": attack_bonus, "total": total,
        "is_crit": crit, "is_fumble": fumble,
        "log": f"Attack[{mode}]: 1d20{sign}={total}{suffix}",
    }


def roll_damage(notation: str, bonus: int = 0, is_crit: bool = False) -> dict:
    if is_crit:
        parts = notation.split("d")
        if len(parts) == 2 and parts[0].isdigit():
            notation = f"{int(parts[0]) * 2}d{parts[1]}"
    r = d20.roll(notation)
    total = max(1, r.total + bonus)
    sign = f"+{bonus}" if bonus >= 0 else str(bonus)
    return {
        "notation": notation, "roll": r.total, "bonus": bonus, "total": total,
        "log": f"{'[CRIT] ' if is_crit else ''}Damage: {notation}{sign} → {total}",
    }


def roll_save(save_bonus: int, dc: int,
              adv: bool = False, dis: bool = False,
              auto_fail: bool = False) -> dict:
    if auto_fail:
        return {"die": 1, "total": 1, "dc": dc, "success": False,
                "log": f"Save: 자동 실패 (auto_fail) vs DC{dc}"}
    if adv and not dis:
        r1, r2 = d20.roll("1d20").total, d20.roll("1d20").total
        die, mode = max(r1, r2), f"ADV({r1},{r2})"
    elif dis and not adv:
        r1, r2 = d20.roll("1d20").total, d20.roll("1d20").total
        die, mode = min(r1, r2), f"DIS({r1},{r2})"
    else:
        die, mode = d20.roll("1d20").total, "STD"
    total = die + save_bonus
    success = total >= dc
    sign = f"+{save_bonus}" if save_bonus >= 0 else str(save_bonus)
    return {
        "die": die, "total": total, "dc": dc, "success": success,
        "log": f"Save[{mode}]: 1d20{sign}={total} vs DC{dc} → {'SUCCESS' if success else 'FAIL'}",
    }


def roll_initiative(dex_mod: int) -> dict:
    die = d20.roll("1d20").total
    total = die + dex_mod
    sign = f"+{dex_mod}" if dex_mod >= 0 else str(dex_mod)
    return {"die": die, "total": total, "log": f"Initiative: 1d20{sign}={total}"}


def roll(notation: str) -> int:
    return d20.roll(notation).total


# ── 미분 가능한 주사위 (RL 역전파용) ───────────────────────────────────────

def _gumbel_softmax(logits: torch.Tensor, temp: float) -> torch.Tensor:
    u = torch.rand_like(logits)
    g = -torch.log(-torch.log(u + 1e-20) + 1e-20)
    return F.softmax((logits + g) / temp, dim=-1)


def diff_roll_d20(temp: float = 0.5, adv: bool = False, dis: bool = False) -> torch.Tensor:
    sides = torch.arange(1.0, 21.0)
    logits = torch.zeros(20)
    if adv and not dis:
        logits = torch.log((2 * sides - 1) / 400 + 1e-20)
    elif dis and not adv:
        logits = torch.log((41 - 2 * sides) / 400 + 1e-20)
    return torch.sum(_gumbel_softmax(logits, temp) * sides)


def diff_attack_check(atk_bonus: torch.Tensor, ac: torch.Tensor,
                      adv: bool = False, dis: bool = False,
                      temp: float = 0.5) -> torch.Tensor:
    die = diff_roll_d20(temp=temp, adv=adv, dis=dis)
    return torch.sigmoid((die + atk_bonus - ac) / temp)


def diff_roll_damage(notation: str, dmg_bonus: torch.Tensor,
                     is_crit: bool = False, temp: float = 0.5) -> torch.Tensor:
    n, s = (int(x) for x in notation.split("d"))
    if is_crit:
        n *= 2
    sides = torch.arange(1.0, s + 1.0)
    logits = torch.zeros(s)
    total = sum(torch.sum(_gumbel_softmax(logits, temp) * sides) for _ in range(n))
    return F.softplus(total + dmg_bonus - 1.0) + 1.0
