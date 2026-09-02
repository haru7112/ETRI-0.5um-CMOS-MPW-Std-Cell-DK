# SNAKE — ETRI 0.5um MPW 단독 동작 스네이크 게임 칩

MCU 없이 **칩 하나 + SSD1315 OLED + 5방향 조이스틱 + 25MHz 오실레이터 + 전원**
만으로 동작하는 스네이크 게임입니다. 아두이노도, 프레임버퍼도, SRAM 매크로도
쓰지 않습니다.

```
   25MHz OSC ──► CLK                  ┌──────────────┐
   RC reset  ──► RST_N   snake_chip   │ SSD1315 OLED │
   5-way SW  ──► JS_*    ETRI 0.5um   │   128 x 64   │
                          SCL/SDA ────┤  I2C  0x3C   │
                          RES# ───────┤              │
                          LED  ──►    └──────────────┘
```

---

## 1. 핵심 아이디어 — 왜 메모리 없이 되는가

ETRI 0.5um 셀 라이브러리에는 RAM 매크로가 없고, DFF 하나가 **36 x 36 um**
입니다. 128x64 프레임버퍼(8192 bit)를 플립플롭으로 만들면 그것만으로 10.6 mm²,
28핀 다이 전체(약 3.6 mm²)보다도 큽니다. 그래서 이 설계는 두 가지를 포기합니다.

**(1) 프레임버퍼를 만들지 않는다 — racing the beam**

SSD1315를 horizontal addressing 모드로 두면 패널이 1024바이트를 정해진 순서로
요구합니다. n번째 바이트는 page `n[9:7]`, column `n[6:0]` 의 세로 8픽셀입니다.
칩은 그 바이트를 **요구받는 순간에 계산해서** 내보냅니다. I2C가 이전 바이트를
밀어내는 약 22us 동안 다음 바이트를 만들면 되므로 시간은 남아돕니다.

**(2) 몸통을 배열이 아니라 원형 시프트 레지스터로 둔다**

`snake_body.v` 가 이 설계의 전부입니다. MAXLEN개의 좌표를 담은 순환
시프트 레지스터 하나뿐이고, 두 동작이 **같은 시프트 경로**를 공유합니다.

| 동작 | 시프트 입력 | 의미 |
|---|---|---|
| `move` | 새 머리 좌표 | `seg[i] <= seg[i-1]`, 꼬리는 유효구간 `[0, len)` 밖으로 밀려나며 자동 삭제 |
| `scan` | `seg[MAXLEN-1]` (되먹임) | MAXLEN번 돌면 레지스터는 원래대로, 그 사이 모든 마디가 한 번씩 출력 |

먹이를 먹는 것은 `len <= len+1` 한 줄입니다. 방금 밀려났던 옛 꼬리 칸이 다시
유효해지므로 꼬리를 되살리는 로직이 따로 없습니다.

그리고 **11비트 비교기 딱 하나**를 시분할해서 세 가지 질문에 모두 답합니다.

* 이 칸이 뱀의 일부인가? → 렌더링
* 새 머리가 몸통에 닿는가? → 자기 충돌
* 이 칸이 비어 있는가? → 먹이 배치

스캔 1회는 MAXLEN 클럭(48개 기준 1.9us @25MHz)이라 I2C 바이트 시간 안에
완전히 숨습니다. 즉 **뱀 길이는 화면 성능에 전혀 영향을 주지 않습니다.**

부수 효과로, 몸통 플립플롭은 시프트 경로로만 쓰이므로 리셋이 필요 없습니다.
덕분에 값비싼 `DFFSR`(72x36um) 대신 `DFFPOSX1`(36x36um)에 매핑됩니다.
같은 이유로 코어 전체를 **동기 리셋**으로 바꿔 DFFSR을 0개로 만들었고,
셀 면적이 3.09 → 2.77 mm² 로 줄었습니다.
(비동기 리셋 플립플롭은 `reset_sync.v` 안의 4개뿐입니다.)

---

## 2. 화면 구성

```
 page 0  (y 0..7)    SCORE 00               상태바
 page 1..7 (y 8..63) ##################     플레이 필드
                     ##              ##      - 셀 2x2 px, 64 x 32 그리드
                     ##    ■■        ##      - 바깥 한 줄은 벽
                     ##  ■■■■        ##      - 먹이는 약 4Hz로 깜빡임
                     ##################
```

* 타이틀 화면: `SNAKE` / `PUSH OK`
* 게임 오버: 필드를 그대로 둔 채 가운데에 `GAME OVER`
* 속도: 200ms/스텝에서 시작해 길어질수록 88ms/스텝까지 빨라짐
* 180도 되꺾기는 **현재 진행 방향** 기준으로 거부되므로, 한 스텝 안에
  위→왼쪽→아래를 연타해도 자기 목을 물지 않습니다
  (방향 인코딩을 `opposite(d) = d ^ 2'b10` 이 되도록 잡아서 게이트 2개로 처리)

---

## 3. 파일 구성

```
snake_game/
├── rtl/
│   ├── snake_params.vh    CELL_SH 로부터 그리드/좌표폭 파생
│   ├── snake_chip.v       ASIC 코어 top (qflow 대상, tri-state 없음)
│   ├── snake_chip_pads.v  패드링까지 포함한 칩 전체 넷리스트(문서/검증용)
│   ├── snake_top.v        코어 top (ms 시간축, 서브블록 결선)
│   ├── snake_body.v       ★ 순환 시프트 레지스터 + 시분할 비교기
│   ├── game_ctrl.v        게임 규칙 FSM, 점수, 먹이, 속도
│   ├── pixel_gen.v        1024바이트 절차적 생성
│   ├── font_rom.v         5x7 글리프 (숫자 + UI에 쓰는 14글자)
│   ├── oled_ctrl.v        SSD1315 init + 프레임 시퀀서 + NACK 복구
│   ├── i2c_master.v       write-only I2C, open-drain
│   ├── debounce.v         5입력 디바운스 (1ms 3샘플)
│   ├── lfsr11.v           먹이 난수
│   └── reset_sync.v       비동기 assert / 동기 release
├── sim/                   iverilog 검증 (SSD1315 모델 포함)
├── fpga/zybo_z7_20/       Zybo Z7-20 래퍼 + XDC + Vivado 스크립트
├── ETRI050/               qflow RTL-to-GDS 프로젝트
├── syn/                   yosys 면적 측정 스크립트
└── docs/                  결선도, 면적 리포트, 캡처된 화면
```

---

## 4. 검증

```bash
cd sim
make          # 전체 (약 2분)
make system   # 칩 + SSD1315 모델 + 스크립트 플레이어
make pixel    # 렌더러 단위 검증, CELL_SH = 1/2/3 전부
make lint     # ASIC top / 패드링 / Zybo 래퍼 elaboration
```

`sim/ssd1315_model.v` 는 진짜 I2C 슬레이브처럼 동작합니다. START/STOP,
주소 매칭, ACK, control byte(0x00/0x40), `0x21`/`0x22` 윈도우 명령,
horizontal addressing 랩어라운드까지 구현하고 1024바이트 GDDRAM을 유지하며,
프레임을 ASCII 아트로 덤프합니다 (`docs/frames.txt` 에 실제 캡처가 있습니다).

`make system` 이 확인하는 것 (19개 항목 전부 PASS):

* 전원 인가 → RES# 펄스 → init 26바이트 → `display ON`, NACK 0회
* 프레임 스트리밍, 윈도우가 128x64로 설정됨
* 타이틀 → OK → 길이 3, 먹이 배치, 오른쪽 진행
* 방향 전환, **180도 되꺾기 거부**
* 먹이 섭취 → 길이 증가 + 점수 증가
* 벽 충돌 → GAME OVER 렌더링
* OK → 재시작 (길이/점수 초기화)
* 길이 6까지 키운 뒤 아래/왼쪽/위로 접어 **자기 충돌 사망** (벽이 아닌 필드 한가운데)

`make pixel` 은 몸통 레지스터 내용과 실제 출력 이미지를 셀 단위로 대조하고,
테두리가 사방으로 닫혀 있는지까지 확인합니다.

---

## 5. FPGA (Zybo Z7-20) 먼저 올리기

```bash
cd fpga/zybo_z7_20
vivado -mode batch -source build.tcl      # build/snake_zybo.bit
```

125MHz를 5분주해 25MHz를 만들고 코어는 그대로 씁니다.
결선은 `docs/hw_connection.md` 를 보세요. 요약:

| 보드 | 신호 |
|---|---|
| Pmod JE1 / JE2 / JE3 | OLED SCL / SDA / RES# (JE5=GND, JE6=3V3) |
| Pmod JC1..JC4, JC7 | 조이스틱 UP/DOWN/LEFT/RIGHT/OK (JC5=GND) |
| SW3 | 리셋 |
| BTN0 | 조이스틱 없이도 시작할 수 있는 예비 OK |
| LD0 | 하트비트. 패널이 ACK 하기 전에는 빠르게 깜빡임 |

LD0가 계속 빠르게 깜빡이면 I2C가 ACK를 못 받고 있다는 뜻입니다
(주소 0x3C/0x3D, 풀업, 전원 순서를 확인하세요).

---

## 6. ASIC (ETRI 0.5um)

```bash
cd ETRI050
make config_m2f
make synthesize && make place && make sta && make route
make migrate && make lvs && make size
cd chip_top && make          # 패드 프레임 스티칭
```

### 면적 — **현재 28핀 패키지 예산을 초과합니다**

2026년 3차 내 칩 제작 서비스 공고 기준으로 **패키지 칩은 `MPW_PAD_28pin` 표준
배치만 가능**하고, 그보다 크게 설계하면 사전 협의 후 **bare die만** 받습니다.

예산과 현재 상태 (근거는 전부 `docs/area.md`, DK 안의 실제 테이프아웃
`pong_pt1_MPW2025_STD-II` 레이아웃과 DEF에서 실측):

```
코어 창  (핀 라우팅 링 안쪽 441.0~1459.0um)  1018 x 1018 um = 1.036 mm2
utilisation (실측)                                            82.3 %
--------------------------------------------------------------------
예산                                                        0.853 mm2 의 셀

4x4 px 32x16, MAXLEN 32, 점수+텍스트                        1.423 mm2  -> 1.67 배
8x8 px 16x8,  MAXLEN 16, 문자 제외 (최소)                   1.116 mm2  -> 1.31 배
```

동일 기능 기준으로 처음 2.769 mm²에서 **1.423 mm² (-49%)** 까지 줄였습니다
(동기 리셋, 방향 큐 몸통, 위치 연산을 snake_body로 이동, 중복 레지스터 제거).
그래도 가장 극단적으로 깎은 설정이 예산의 1.31배라, **현 구조로는 28핀 패키지에
들어가지 않습니다.** 측정 근거와 남은 선택지는 `docs/area.md` 4~5절에 있습니다.

### 핀 (신호 11개)

```
CLK  RST_N  JS_UP  JS_DOWN  JS_LEFT  JS_RIGHT  JS_OK      입력 7
OLED_RES_N  LED                                            출력 2
SCL  SDA                                                   양방향 2 (open-drain)
```

코어 자체는 tri-state를 쓰지 않습니다. `SCL_OE`/`SDA_OE`/`SDA_I` 로 나오고
`PADINOUT`(DO는 GND 고정, OEN에 *_OE) 로 open-drain을 구성합니다.
DK의 다른 게임들과 마찬가지로 패드링은 chip_top에서 magic으로 붙입니다.

---

## 7. 파라미터

`snake_chip.v` / `snake_zybo_top.v` 에서 바꿉니다.

| 파라미터 | 기본 | 설명 |
|---|---|---|
| `CELL_SH` | 1 | 셀 크기 `2^CELL_SH` px. 1=2x2(64x32), 2=4x4(32x16), 3=8x8(16x8) |
| `MAXLEN` | 48 | 몸통 최대 길이. 면적의 가장 큰 축 |
| `LEN_W` | 6 | `MAXLEN`을 담을 수 있어야 함 |
| `INIT_LEN` | 3 | 시작 길이 |
| `EN_TEXT` | 1 | 0이면 폰트에서 알파벳을 빼고 점수 숫자만 남김 |
| `SCL_HZ` | 400k | 1MHz까지 올리면 프레임레이트가 40 → 100fps 이상 |
| `RES_MS` | 20 | RES# 펄스/안정화 시간 |

`CELL_SH` 1/2/3 모두 `make pixel` 로 렌더링이 검증되어 있습니다.

---

## 8. 알려진 전기적 주의사항

* ETRI 0.5um은 **5V** 공정입니다(liberty `nom_voltage: 5`). Zybo Pmod는 3.3V이니
  실칩과 FPGA를 같은 보드에 섞지 마세요.
* I2C 라인은 칩이 **끌어내리기만** 합니다. 풀업을 3.3V로 올리면 5V 칩이
  3.3V 패널을 그대로 구동할 수 있습니다. 풀업을 5V로 올리면 패널이 5V를
  받게 되니, 모듈 데이터시트를 확인하기 전에는 3.3V 풀업을 쓰세요.
* 조이스틱 5핀에는 **외부 10k 풀업**이 필요합니다. `PADINC` 에는 풀업이 없습니다.
