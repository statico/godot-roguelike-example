# ⚔️ LLM Crawl

> **4인 파티 AI 동료와 함께하는 던전 크롤러.**
> Godot 4 + DnD 5e SRD + 강화학습 AI (BT → RL 점진적 교체)

---

## 🎮 컨셉

- 플레이어 1명 + AI 파티원 3명이 절차적 생성 던전을 탐험
- 전투는 타일맵 위에서 즉시 발생 (별도 전투씬 없음)
- 파티원 AI와 몬스터 AI 모두 비헤이비어 트리 → 강화학습으로 점진적 교체
- DnD 5e SRD 기반 전투 룰 및 용어 통일

---

## 🗂️ 폴더 구조

```
LLM_Crawl_Godot/
├── autoload/           # 🔴 싱글턴 (GameState)
├── data/
│   ├── srd/            # DnD 5e SRD 원문 (마크다운)
│   ├── narrative/      # 하드코딩 텍스트 풀 (JSON)
│   ├── dnd_schemas.json
│   └── master_dnd_schema.json
├── scripts/
│   ├── dnd/            # 🩵 DnD 룰 엔진 (주사위, 캐릭터시트, 전투)
│   ├── combat/         # 🩵 전투 루프
│   ├── ai/
│   │   ├── bt/         # 비헤이비어 트리 (Phase A)
│   │   └── rl/         # ONNX 강화학습 추론 (Phase C)
│   ├── party/          # 파티 팔로우, 역할 관리
│   ├── generation/     # BSP 던전 생성
│   └── narrative/      # 텍스트 풀 유틸
├── scenes/
│   ├── world/          # 🟣 던전 타일맵
│   ├── ui/             # 🟣 HUD, 인벤토리, 전투 로그
│   └── entities/       # 🟣 Player, PartyMember, Monster
├── assets/sprites/     # 🟡 RogueLite OGA 스프라이트
├── ai_models/          # 🩷 학습된 ONNX 모델
├── src/                # 🩵 기존 템플릿 소스 (참고용)
└── combat_sim/         # Python RL 학습 환경 (별도 프로젝트)
```

---

## 📖 DnD 5e 용어집 (전 파일 통일 기준)

> 이 용어집은 코드 변수명, 텍스트, 데이터 키 전반에 걸쳐 통일 적용됩니다.
> 새 용어 추가 시 이 표에 반드시 추가하세요.

### 핵심 전투 용어

| 한국어 개념 | **공식 용어 (코드/텍스트 통일)** | 설명 |
|---|---|---|
| 체력 | **Hit Points (HP)** | `current_hp`, `max_hp` |
| 방어력 | **Armor Class (AC)** | `armor_class` |
| 선공 순서 | **Initiative** | `d20 + DEX modifier` |
| 공격 굴림 | **Attack Roll** | `d20 + attack_bonus vs AC` |
| 피해 굴림 | **Damage Roll** | 무기 주사위 + 능력치 수식어 |
| 내성 굴림 | **Saving Throw** | `d20 + ability_modifier vs DC` |
| 전문화 보너스 | **Proficiency Bonus** | 레벨 기반, `proficiency_bonus` |
| 유리한 굴림 | **Advantage** | d20 두 번, 높은 값 |
| 불리한 굴림 | **Disadvantage** | d20 두 번, 낮은 값 |
| 치명타 | **Critical Hit** | 자연 20, 데미지 주사위 2배 |
| 행동 | **Action** | 턴당 1회 |
| 추가 행동 | **Bonus Action** | 턴당 1회 |
| 반응 | **Reaction** | 조건 발생 시 1회 |

### 6대 능력치

| 약어 | 전체 이름 | 코드 변수 |
|---|---|---|
| STR | Strength | `score_str`, `get_str_mod()` |
| DEX | Dexterity | `score_dex`, `get_dex_mod()` |
| CON | Constitution | `score_con`, `get_con_mod()` |
| INT | Intelligence | `score_int`, `get_int_mod()` |
| WIS | Wisdom | `score_wis`, `get_wis_mod()` |
| CHA | Charisma | `score_cha`, `get_cha_mod()` |

### 상태이상 (Condition)

| 한국어 | **Condition** | 코드 키 |
|---|---|---|
| 기절 | **Stunned** | `"stunned"` |
| 중독 | **Poisoned** | `"poisoned"` |
| 실명 | **Blinded** | `"blinded"` |
| 마비 | **Paralyzed** | `"paralyzed"` |
| 공포 | **Frightened** | `"frightened"` |
| 넘어짐 | **Prone** | `"prone"` |
| 속박 | **Restrained** | `"restrained"` |

### 캐릭터/파티 용어

| 한국어 | **공식 용어** | 코드 / 비고 |
|---|---|---|
| 직업 | **Class** | `char_class` |
| 종족 | **Species** | `char_species` (5e 2024 기준) |
| 레벨 | **Level** | `char_level` |
| 적 강도 | **Challenge Rating (CR)** | 몬스터 난이도 |
| 대형 | **Marching Order** | 던전 이동 시 파티 포지션 |
| 파티 | **Party** | 최대 4명 |
| 파티 매니저 | **Party Manager** | `PartyManager` (파티원 등록, 이동 경로 및 맵 이동 관리) |
| 파티 AI | **Party AI** | `PartyAI` (클래스별 행동 트리 및 추적 알고리즘) |

### 파티 역할 (Role)

| 포지션 | **Role** | 코드 값 | 행동 우선순위 |
|---|---|---|---|
| 탱커/근접 | **Fighter** | `Type.FIGHTER` | 어그로 유지, 최전방 근접 전투 |
| 히트앤런 | **Rogue** | `Type.ROGUE` | 배후 침투, 기습/치명타 딜링 |
| 서포터 | **Cleric** | `Type.CLERIC` | 아군 버프 및 힐링, 후방 지원 |
| 원거리 | **Ranger** | `Type.RANGER` | 최적 거리 유지, 원거리 카이팅 |

### 던전 용어

| 한국어 | **공식 용어** | 비고 |
|---|---|---|
| 던전 층 | **Floor** | `current_floor` |
| 방 | **Room** | |
| 방 유형 | **Room Type** | Combat / Treasure / Rest / Event / Boss |
| 시야 | **Field of View (FOV)** | |
| 안개전쟁 | **Fog of War** | |
| 기습 | **Surprise** | |
| 계단 (내려가기) | **Descend** | |
| 계단 (올라가기) | **Ascend** | |

### 레인저 특화 용어 (Ranger Features)

| 한국어 | **공식 용어** | 코드 / 키 | 설명 |
|---|---|---|---|
| 굿베리 | **Goodberry** | `goodberry` | 10개의 베리를 소환하여 인벤토리에 추가 (포만감 100 및 1 HP 회복) |
| 사냥꾼의 표식 | **Hunter's Mark** | `hunters_mark` | 가장 가까운 대상에게 표식을 남겨 공격 시 1d6 추가 피해 |
| 원시의 자각 | **Primeval Awareness** | `primeval_awareness` | 맵 전체에 언데드가 있는지 탐지 |
| 자연 위장 | **Hide in Plain Sight** | `hide_in_plain_sight` | 행동하기 전까지 적들의 시야에 감지되지 않는 은신(위장) 상태 돌입 |
| 소실 | **Vanish** | `vanish` | 위장을 보너스 액션으로 수행할 수 있게 하는 특성 (14레벨+) |
| 궁술 전투 스타일 | **Archery Fighting Style** | `Archery` | 원거리 공격 굴림에 +2 보너스 부여 |
| 거인 학살자 | **Colossus Slayer** | `colossus_slayer` | 체력이 최대치 미만인 적에게 턴당 1회 1d8 추가 피해 |
| 숙적 | **Favored Enemy** | `favored_enemy` | 레벨별 지정된 숙적(언데드, 파충류, 거미류)을 대상으로 하는 보너스 |
| 자연 탐험가 | **Natural Explorer** | `natural_explorer` | 시야 범위 확장 보너스 (+2) |
| 야수의 감각 | **Feral Senses** | `feral_senses` | 18레벨 이상에서 시야 범위를 추가 확장 (+4) |
| 숙적 파괴자 | **Foe Slayer** | `foe_slayer` | 20레벨 이상에서 숙적 대상 공격/피해에 지혜 수정치 보너스 추가 |

### 바바리안 특화 용어 (Barbarian Features)

| 한국어 | **공식 용어** | 코드 / 키 | 설명 |
|---|---|---|---|
| 분노 | **Rage** | `barbarian_rage` | 보조 행동 소모: 물리 피해 저항(Bludgeoning/Piercing/Slashing 절반) 및 추가 공격력 획득. 중장갑 착용 시 활성화 불가. |
| 광폭화 분노 | **Frenzied Rage** | `barbarian_frenzied_rage` | 보조 행동 소모: 버서커 하위클래스 격노. 격노 종료 시 탈진(`STIM_RECOVERY`) 15턴 적용. |
| 광폭화 공격 | **Frenzy Attack** | `barbarian_frenzy_attack` | 보조 행동 소모: 광폭화 분노 중 인접한 적에게 강력한 추가 근접 공격 가함. |
| 무모한 공격 | **Reckless Attack** | `barbarian_reckless` | 이번 턴 자신의 근접 무기 공격 굴림에 이점을 주나 다음 턴까지 적들의 공격 굴림도 이점을 가짐. |
| 비무장 방어 | **Unarmored Defense** | - | 갑옷 상/하의를 입지 않았을 때 AC가 10 + Dex 수정치 + Con 수정치로 적용. |
| 빠른 이동 | **Fast Movement** | - | 5레벨 이상에서 중장갑 미착용 시 이동 속도 +2 증가. |
| 위험 감지 | **Danger Sense** | - | 2레벨 이상에서 실명/마비 상태가 아닐 때 민첩 내성 굴림에 이점. |
| 야성적 본능 | **Feral Instinct** | - | 7레벨 이상에서 선공 굴림(Initiative roll)에 이점. |
| 야만적 치명타 | **Brutal Critical** | - | 9레벨 이상에서 치명타 성공 시 레벨별 무기 피해 주사위 추가 롤 (+1~+3). |
| 끈질긴 분노 | **Relentless Rage** | - | 11레벨 이상에서 격노 중 체력이 0이 될 때 CON 내성 성공 시 1 HP로 생존 (DC 10부터 5씩 상승). |
| 보복 | **Retaliation** | - | 14레벨 이상에서 격노 중 리액션을 사용하여 인접한 공격 대상에게 근접 보복 공격 실행. |
| 태고의 인도자 | **Primal Champion** | - | 20레벨 이상에서 힘(STR)과 건강(CON) 스탯 +4 보너스 부여. |

---

## 🤖 AI 모드 전환

```gdscript
# 런타임 전환 (디버그 콘솔 or 설정 메뉴)
GameState.set_ai_mode("behavior_tree")  # 안정적
GameState.set_ai_mode("rl_model")       # 실험적
```

---

## 📜 라이선스

- 게임 코드: MIT
- 스프라이트: OGA-BY 3.0 (Credit: Lucid Design Art)
- DnD 5e SRD: CC-BY 4.0 (Credit: Wizards of the Coast)
- 베이스 템플릿: MIT (statico/godot-roguelike-example)
