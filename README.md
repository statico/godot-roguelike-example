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
