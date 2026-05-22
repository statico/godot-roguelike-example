"""
IGO-UGO 턴 매니저 (I Go, You Go)

흐름:
  1. 전투 시작 → 이니셔티브 굴림 → 순서 확정
  2. 매 턴: 현재 유닛 행동 (이동 / 공격 / 특수)
  3. 행동 완료 → 다음 유닛으로
  4. 모든 유닛 완료 → 라운드 종료 → 컨디션 틱
  5. 한 팩션 전멸 → 전투 종료
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Optional

from .entity import Entity, FightingStyle
from .actions import Action, ActionResult, MOVE_DELTAS, MOVE_ACTIONS
from .conditions import Condition, make_condition, make_effect
from .combat_log import AttackDetail, CombatLog
from .dice import roll_attack, roll_save, roll_initiative
from .dice import roll as dice_roll
from .spells import SpellResolver, SPELL_REGISTRY, CastingTime


# ==========================================
# 📋 [구역 1] 전투 상태 (COMBAT STATE)
# ==========================================

@dataclass
class CombatState:
    combatants: list[Entity]
    round_num:  int = 0
    turn_index: int = 0        # 현재 이니셔티브 순서 인덱스
    done:       bool = False
    winner:     Optional[str] = None   # "player" | "enemy" | "draw"
    log:        CombatLog = field(default_factory=CombatLog)

    @property
    def current(self) -> Entity:
        return self.combatants[self.turn_index]

    @property
    def players(self) -> list[Entity]:
        return [e for e in self.combatants if e.faction == "player" and e.is_alive]

    @property
    def enemies(self) -> list[Entity]:
        return [e for e in self.combatants if e.faction == "enemy" and e.is_alive]

    def get_by_uid(self, uid: str) -> Optional[Entity]:
        return next((e for e in self.combatants if e.uid == uid), None)

    def to_obs(self) -> dict:
        """RL observation 직렬화."""
        return {
            "round": self.round_num,
            "turn_uid": self.current.uid if not self.done else "",
            "done": self.done,
            "winner": self.winner,
            "combatants": [
                {
                    "uid": e.uid, "faction": e.faction,
                    "hp": e.hp, "max_hp": e.max_hp, "ac": e.ac,
                    "x": e.x, "y": e.y,
                    "action_used": e.action_used,
                    "movement_remaining": e.movement_remaining,
                    "conditions": e.effects.to_list(),
                    # 파이터 상태 직렬화
                    "fighter_second_wind_used":  e.fighter_second_wind_used,
                    "fighter_action_surge_used": e.fighter_action_surge_used,
                    "fighter_indomitable_uses":  e.fighter_indomitable_uses,
                }
                for e in self.combatants
            ],
        }


# ==========================================
# ⚙️ [구역 2] 턴 매니저 (TURN MANAGER)
# ==========================================

class TurnManager:
    MAX_ROUNDS = 50

    def __init__(self, players: list[Entity], enemies: list[Entity],
                 grid_w: int = 14, grid_h: int = 14):
        self.grid_w = grid_w
        self.grid_h = grid_h
        self.state  = self._init_combat(players, enemies)

    # ── 초기화 ──────────────────────────────────────────────────────────────
    def _init_combat(self, players: list[Entity], enemies: list[Entity]) -> CombatState:
        all_units = players + enemies
        order = sorted(all_units, key=lambda e: -roll_initiative(e.dex_mod)["total"])
        for e in order:
            e.reset_turn()
        state = CombatState(combatants=order)
        state.round_num = 1
        state.log.add_msg(f"=== 전투 시작 (라운드 {state.round_num}) ===")
        state.log.add_msg("이니셔티브: " + " → ".join(e.name for e in order))
        return state

    # ── 외부 인터페이스 ──────────────────────────────────────────────────────
    def step(self, action: Action, target_uid: Optional[str] = None, **kwargs) -> ActionResult:
        """
        현재 유닛의 액션을 실행하고 ActionResult를 반환한다.
        이동 액션은 target_uid 불필요.
        공격/특수 액션은 target_uid 필요 (없으면 가장 가까운 적 자동 선택).
        """
        s     = self.state
        actor = s.current

        if s.done:
            return ActionResult(actor.uid, action, False, 0.0, "전투 종료됨")

        if not actor.effects.query_can_act() and action not in MOVE_ACTIONS:
            result = ActionResult(actor.uid, action, False, 0.0,
                                  f"{actor.name} 행동 불가 (컨디션)")
            self._advance_turn()
            return result

        if action in MOVE_ACTIONS:
            result = self._do_move(actor, action)
        elif action == Action.ATTACK:
            target = s.get_by_uid(target_uid) if target_uid else self._nearest_enemy(actor)
            result = self._do_attack(actor, target) if target else \
                     ActionResult(actor.uid, action, False, 0.0, "대상 없음")
        elif action == Action.CAST_SPELL:
            # target_uid can be a string of comma-separated UIDs for multi-target
            # spell_key and slot_level come from extra kwargs (extend step signature)
            result = self._do_cast_spell(actor, target_uid, **kwargs)
        elif action == Action.DODGE:
            result = self._do_dodge(actor)
        elif action == Action.DASH:
            result = self._do_dash(actor)
        elif action == Action.DISENGAGE:
            result = self._do_disengage(actor)
        elif action == Action.HELP:
            target = s.get_by_uid(target_uid) if target_uid else None
            result = self._do_help(actor, target)
        elif action == Action.SHOVE:
            target = s.get_by_uid(target_uid) if target_uid else self._nearest_enemy(actor)
            result = self._do_shove(actor, target) if target else \
                     ActionResult(actor.uid, action, False, 0.0, "대상 없음")
        elif action == Action.SECOND_WIND:
            result = self._do_fighter_second_wind(actor)
        elif action == Action.ACTION_SURGE:
            result = self._do_fighter_action_surge(actor)
        elif action == Action.WAIT:
            result = ActionResult(actor.uid, action, True, 0.0, f"{actor.name} 대기")
            actor.action_used = True
        else:
            result = ActionResult(actor.uid, action, False, 0.0, "미구현 액션")

        s.log.add_msg(result.log)

        # 행동 소비 후 턴 진행 여부 판단
        # SECOND_WIND / ACTION_SURGE 는 보조 행동(bonus action)이므로 주행동 소비 안 함
        if actor.action_used:
            self._advance_turn()

        self._check_victory()
        return result

    def end_turn(self) -> None:
        """플레이어가 명시적으로 턴 종료."""
        self.state.current.action_used = True
        self.state.current.movement_remaining = 0
        self._advance_turn()
        self._check_victory()

    # ==========================================
    # ⚔️ [구역 3] 기본 액션 (BASE ACTIONS)
    # ==========================================

    def _do_move(self, actor: Entity, action: Action) -> ActionResult:
        if not actor.effects.query_can_move():
            return ActionResult(actor.uid, action, False, 0.0,
                                f"{actor.name} 이동 불가 (컨디션)")
        if actor.movement_remaining <= 0:
            return ActionResult(actor.uid, action, False, 0.0,
                                f"{actor.name} 이동력 소진")
        dx, dy = MOVE_DELTAS[action]
        nx, ny = actor.x + dx, actor.y + dy
        if not (0 <= nx < self.grid_w and 0 <= ny < self.grid_h):
            return ActionResult(actor.uid, action, False, 0.0, "맵 경계")
        actor.x, actor.y = nx, ny
        actor.movement_remaining -= 1
        return ActionResult(actor.uid, action, True, 0.0,
                            f"{actor.name} → ({nx},{ny}) 이동")

    def _do_dodge(self, actor: Entity) -> ActionResult:
        # dodge_stance: 다음 자신의 턴 시작까지 incoming 공격에 dis, DEX 세이브에 adv
        actor.effects.add(make_effect("dodge_stance", duration=1, source_uid=actor.uid))
        actor.action_used = True
        return ActionResult(actor.uid, Action.DODGE, True, 0.0,
                            f"{actor.name} 회피 태세 (공격자 디스어드밴티지 / DEX 세이브 어드밴티지)")

    def _do_dash(self, actor: Entity) -> ActionResult:
        actor.movement_remaining += actor.speed // 5
        actor.action_used = True
        return ActionResult(actor.uid, Action.DASH, True, 0.0,
                            f"{actor.name} 전력 질주 (이동력 +{actor.speed//5})")

    def _do_disengage(self, actor: Entity) -> ActionResult:
        actor.action_used = True
        return ActionResult(actor.uid, Action.DISENGAGE, True, 0.0,
                            f"{actor.name} 이탈 (기회 공격 없이 이동 가능)")

    def _do_help(self, actor: Entity, target: Optional[Entity]) -> ActionResult:
        actor.action_used = True
        if not target:
            return ActionResult(actor.uid, Action.HELP, False, 0.0, "대상 없음")
        target.effects.add(make_effect("help_advantage", duration=1, source_uid=actor.uid))
        return ActionResult(actor.uid, Action.HELP, True, 0.0,
                            f"{actor.name} → {target.name} 도움 (다음 공격 어드밴티지)")

    def _do_shove(self, actor: Entity, target: Entity) -> ActionResult:
        """
        Shove: STR (Athletics) vs STR or DEX (Acrobatics) 대립.
        성공 시 Prone 또는 5ft 밀어냄 선택.
        현재: Prone 으로 단순화 구현.
        """
        shove_dc = 8 + actor.str_mod
        save_q   = target.effects.query_save()
        save     = roll_save(max(target.str_mod, target.dex_mod), shove_dc,
                             adv=save_q.advantage, dis=save_q.disadvantage,
                             auto_fail=save_q.auto_fail)
        actor.action_used = True
        if not save["success"]:
            target.effects.add(make_condition(Condition.PRONE, duration=-1))
            return ActionResult(actor.uid, Action.SHOVE, True, 0.0,
                                f"{actor.name} → {target.name} Shove 성공! Prone. | {save['log']}")
        return ActionResult(actor.uid, Action.SHOVE, False, 0.0,
                            f"{actor.name} → {target.name} Shove 실패. | {save['log']}")

    # ==========================================
    # ⚔️ [구역 4] 공격 판정 (ATTACK RESOLUTION)
    # ==========================================

    def _do_attack(self, actor: Entity, target: Entity) -> ActionResult:
        """
        D&D 5e 공격 액션.
        파이터인 경우:
          - Extra Attack: 레벨에 따라 한 번의 Attack 액션으로 다중 공격 판정.
          - Fighting Style 보정:
            * Archery : 원거리 공격 굴림 +2
            * Defense : 방어구 착용한 파이터를 공격할 때 대상 AC +1 (자신이 Defense 시)
            * Dueling : 한손 근접무기 피해 +2
            * Great Weapon Fighting: 피해 다이스 1,2 리롤
        """
        if actor.action_used:
            return ActionResult(actor.uid, Action.ATTACK, False, 0.0,
                                f"{actor.name} 이미 행동 사용")
        if not actor.attacks:
            return ActionResult(actor.uid, Action.ATTACK, False, 0.0,
                                f"{actor.name} 공격 정보 없음")

        atk_data    = actor.attacks[0]
        max_attacks = actor.fighter_get_extra_attack_count()

        if actor.dnd_class == "Fighter" and max_attacks > 1:
            print(f"[Fighter Debug] {actor.name} (Lv.{actor.level}) - "
                  f"Extra Attack: 이번 턴 최대 {max_attacks}회 공격 가능")

        total_dmg    = 0
        last_detail  = None
        any_hit      = False

        for atk_idx in range(max_attacks):
            # 대상 사망 시 나머지 공격 중단
            if not target.is_alive:
                if actor.dnd_class == "Fighter":
                    print(f"[Fighter Debug] {actor.name} - "
                          f"공격 #{atk_idx+1} 전 대상 사망, 나머지 공격 중단")
                break

            # ── 판정 훅: 공격 굴림 ───────────────────────────────────────
            atk_q   = actor.effects.query_attack_roll()
            atked_q = target.effects.query_attacked_roll()
            adv = atk_q.advantage    or atked_q.advantage
            dis = atk_q.disadvantage or atked_q.disadvantage

            hit_bonus = atk_data["hit_bonus"] + atk_q.bonus
            if atk_data.get("type") == "ranged":
                hit_bonus += actor.fighter_get_ranged_attack_bonus()

            # ── Defense: 대상이 Defense 스타일 보유 시 AC +1 ──────────────
            effective_ac = target.ac + target.fighter_get_ac_bonus() + target.effects.query_ac_bonus()

            roll         = roll_attack(hit_bonus, adv=adv, dis=dis)
            # auto_crit: Unconscious·Paralyzed 대상은 근접 명중 시 자동 크리티컬
            dmg_in_q = target.effects.query_damage_in()
            is_crit  = roll["is_crit"] or dmg_in_q.auto_crit
            hit      = is_crit or (
                not roll["is_fumble"] and roll["total"] >= effective_ac
            )

            hp_before    = target.hp
            dmg_this_hit = 0

            if hit:

                raw_dmg = self._roll_damage_with_style(actor, atk_data, is_crit)

                dmg_out_q     = actor.effects.query_damage_out()
                dueling_bonus = (actor.fighter_get_melee_damage_bonus()
                                 if atk_data.get("type") != "ranged" else 0)

                final_dmg = max(1, int(raw_dmg * dmg_out_q.multiplier)
                                + dueling_bonus + dmg_out_q.bonus)
                dmg_this_hit = target.take_damage(final_dmg, atk_data.get("damage_type", ""))
                total_dmg   += dmg_this_hit
                any_hit      = True

                if actor.dnd_class == "Fighter":
                    print(f"[Fighter Debug] 공격 #{atk_idx+1}: "
                          f"Roll={roll['total']} vs AC {effective_ac} - *HIT!* "
                          f"피해={dmg_this_hit} (Dueling+{dueling_bonus}) | "
                          f"{target.name} HP: {hp_before} -> {target.hp}")
            else:
                if actor.dnd_class == "Fighter":
                    print(f"[Fighter Debug] 공격 #{atk_idx+1}: "
                          f"Roll={roll['total']} vs AC {effective_ac} - MISS")

            last_detail = AttackDetail(
                round_num=self.state.round_num,
                attacker=actor.name, defender=target.name,
                action_type="attack",
                attack_roll=roll["total"], attack_bonus=hit_bonus,
                target_ac=effective_ac, hit=hit, is_crit=is_crit,
                dmg_dice=atk_data["damage_dice"] if hit else None,
                dmg_total=dmg_this_hit, hp_before=hp_before, hp_after=target.hp,
            )
            self.state.log.add(last_detail)

        actor.action_used = True
        actor.fighter_attacks_this_turn = max_attacks

        total_reward = total_dmg / max(target.max_hp, 1)
        if not target.is_alive:
            total_reward += 1.0

        log_str = last_detail.summary() if last_detail else \
            f"{actor.name} 공격 완료 (총 {total_dmg} 피해)"
        return ActionResult(actor.uid, Action.ATTACK, any_hit, total_reward,
                            log_str, target.uid, total_dmg)

    def _roll_damage_with_style(self, actor: Entity, atk_data: dict,
                                is_crit: bool) -> int:
        """
        Fighting Style 을 반영한 피해 주사위 굴림.
        Great Weapon Fighting: 1 또는 2가 나온 다이스를 1회 리롤.
        나머지 스타일은 표준 굴림 (Dueling/Archery 보정은 호출부에서).
        """
        notation = atk_data["damage_dice"]
        style    = actor.fighter_fighting_style

        if is_crit:
            parts = notation.split("d")
            if len(parts) == 2 and parts[0].isdigit():
                notation = f"{int(parts[0]) * 2}d{parts[1]}"

        if style == FightingStyle.GREAT_WEAPON:
            parts   = notation.split("d")
            n_dice  = int(parts[0])
            n_sides = int(parts[1])
            total   = 0
            for _ in range(n_dice):
                r = dice_roll(f"1d{n_sides}")
                if r <= 2:
                    r2 = dice_roll(f"1d{n_sides}")
                    print(f"[Fighter Debug] Great Weapon Fighting: 리롤 {r} → {r2}")
                    r = r2
                total += r
            return total

        return dice_roll(notation)

    # ==========================================
    # 🪄 [구역 4.5] 마법 시전 (SPELLCASTING)
    # ==========================================

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
                # 피해를 받은 시전자가 집중 체크 필요한 경우 (간단히: spell_result.total_damage 기준)
                # 정밀 구현은 _apply_component 내에서 take_damage 후 호출되는 훅에서 처리되거나 여기서 호출.
                pass

        if spell.casting_time == CastingTime.ACTION:
            actor.action_used = True
        elif spell.casting_time == CastingTime.BONUS_ACTION:
            actor.bonus_action_used = True

        return ActionResult(
            actor.uid, Action.CAST_SPELL,
            spell_result.success, spell_result.reward,
            spell_result.log, target_uid, spell_result.total_damage
        )

    # ==========================================
    # 🛡️ [구역 5] 파이터 클래스 특성 (FIGHTER FEATURES)
    # ==========================================

    def _do_fighter_second_wind(self, actor: Entity) -> ActionResult:
        """
        [D&D 5e] Second Wind — 보조 행동(Bonus Action)
        회복량: 1d10 + Fighter 레벨
        충전: Short Rest or Long Rest
        """
        if actor.dnd_class != "Fighter":
            return ActionResult(actor.uid, Action.SECOND_WIND, False, 0.0,
                                f"{actor.name} 은(는) Fighter 가 아님 — Second Wind 불가")
        if actor.fighter_second_wind_used:
            return ActionResult(actor.uid, Action.SECOND_WIND, False, 0.0,
                                f"{actor.name} Second Wind 이미 사용됨 (Short Rest 필요)")
        if actor.bonus_action_used:
            return ActionResult(actor.uid, Action.SECOND_WIND, False, 0.0,
                                f"{actor.name} 이번 턴 보조 행동 소진")

        roll_val  = dice_roll("1d10")
        healed    = roll_val + actor.level
        hp_before = actor.hp
        actor.heal(healed)
        actor.fighter_second_wind_used = True
        actor.bonus_action_used        = True

        print(f"[Fighter Debug] {actor.name} - Second Wind! "
              f"1d10({roll_val})+{actor.level}lv = +{healed}HP | "
              f"HP: {hp_before} -> {actor.hp}/{actor.max_hp}")

        return ActionResult(
            actor.uid, Action.SECOND_WIND, True,
            healed / max(actor.max_hp, 1),
            f"{actor.name} Second Wind! +{healed} HP 회복 ({actor.hp}/{actor.max_hp})"
        )

    def _do_fighter_action_surge(self, actor: Entity) -> ActionResult:
        """
        [D&D 5e] Action Surge — 보조 행동(Bonus Action)
        2레벨+ 파이터만 사용 가능.
        이번 턴 주행동 1회 추가 부여 (Extra Attack 포함).
        충전: Short Rest or Long Rest
        """
        if actor.dnd_class != "Fighter":
            return ActionResult(actor.uid, Action.ACTION_SURGE, False, 0.0,
                                f"{actor.name} 은(는) Fighter 가 아님 — Action Surge 불가")
        if actor.level < 2:
            return ActionResult(actor.uid, Action.ACTION_SURGE, False, 0.0,
                                f"{actor.name} Lv.2 미만 — Action Surge 불가")
        if actor.fighter_action_surge_used:
            return ActionResult(actor.uid, Action.ACTION_SURGE, False, 0.0,
                                f"{actor.name} Action Surge 이미 사용됨 (Short Rest 필요)")
        if actor.bonus_action_used:
            return ActionResult(actor.uid, Action.ACTION_SURGE, False, 0.0,
                                f"{actor.name} 이번 턴 보조 행동 소진")
        if actor.fighter_action_surged:
            return ActionResult(actor.uid, Action.ACTION_SURGE, False, 0.0,
                                f"{actor.name} 이번 턴 이미 Action Surge 발동함")

        actor.action_used               = False   # 주행동 충전
        actor.bonus_action_used         = True
        actor.fighter_action_surge_used = True
        actor.fighter_action_surged     = True

        print(f"[Fighter Debug] {actor.name} (Lv.{actor.level}) - Action Surge! "
              f"주행동 충전됨. Extra Attack 포함 추가 공격 가능.")

        return ActionResult(
            actor.uid, Action.ACTION_SURGE, True, 0.0,
            f"{actor.name} Action Surge! 주행동 충전 — 이번 턴 추가 공격 가능"
        )

    def fighter_try_indomitable(self, actor: Entity, save_result: dict) -> dict:
        """
        [D&D 5e] Indomitable — 9레벨+ 파이터의 내성 굴림 리롤.
        실패한 내성 굴림에 호출하면 리롤 후 더 나은 결과를 돌려줌.
        충전: Long Rest.
        최대 횟수: 9레벨=1회, 13레벨=2회, 17레벨=3회
        """
        if not actor.fighter_can_use_indomitable():
            return save_result

        save_bonus = save_result["total"] - save_result["die"]
        new_save   = roll_save(save_bonus, save_result["dc"])

        actor.fighter_indomitable_uses += 1
        print(f"[Fighter Debug] {actor.name} - Indomitable 발동! "
              f"({actor.fighter_indomitable_uses}/{actor.fighter_get_indomitable_max()}) "
              f"| 기존: {save_result['log']} -> 재도전: {new_save['log']}")

        if new_save["success"]:
            return new_save
        return save_result

    # ==========================================
    # 🔄 [구역 6] 턴 진행 (TURN FLOW)
    # ==========================================

    def _advance_turn(self) -> None:
        s     = self.state
        alive = [e for e in s.combatants if e.is_alive]
        if not alive:
            return

        # 현재 유닛 턴 종료 틱
        actor   = s.current
        expired = actor.effects.tick_turn_end()
        if expired:
            s.log.add_msg(f"{actor.name} 효과 만료: {', '.join(expired)}")

        # 다음 살아있는 유닛으로
        idx = s.turn_index
        for _ in range(len(s.combatants)):
            idx = (idx + 1) % len(s.combatants)
            if s.combatants[idx].is_alive:
                break

        # 라운드 경계: 인덱스가 처음으로 돌아오거나 더 앞으로
        if idx <= s.turn_index:
            s.round_num += 1
            s.log.add_msg(f"\n=== 라운드 {s.round_num} ===")
            if s.round_num > self.MAX_ROUNDS:
                s.done   = True
                s.winner = "draw"
                return
            for e in alive:
                e.reset_turn()
                round_exp = e.effects.tick_round_end()
                if round_exp:
                    s.log.add_msg(f"{e.name} 효과 만료: {', '.join(round_exp)}")

        s.turn_index = idx

        # 다음 유닛 턴 시작 틱
        next_actor = s.combatants[idx]
        if next_actor.is_alive:
            turn_start_exp = next_actor.effects.tick_turn_start()
            if turn_start_exp:
                s.log.add_msg(f"{next_actor.name} 효과 만료: {', '.join(turn_start_exp)}")

    def _check_victory(self) -> None:
        s = self.state
        if not s.players:
            s.done, s.winner = True, "enemy"
            s.log.add_msg("=== 적 승리 ===")
        elif not s.enemies:
            s.done, s.winner = True, "player"
            s.log.add_msg("=== 플레이어 승리 ===")

    def _nearest_enemy(self, actor: Entity) -> Optional[Entity]:
        opponents = self.state.enemies if actor.faction == "player" else self.state.players
        if not opponents:
            return None
        return min(opponents, key=lambda e: abs(e.x - actor.x) + abs(e.y - actor.y))
