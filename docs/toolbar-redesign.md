# 하단 툴바 재설계 계획

대상: `public/index.html` (툴바 마크업 + CSS + JS 전면 교체) + 런처 6곳
상태: **구현 완료** (2026-07-03, 실기기 검증: 터치 스크롤/드래그 선택 확인)

## 1. 목표

- 하단바를 **3개 모드(페이지)** 로 재구성: **특수키(기본) / 설정 / 텍스트 선택**
- 우측에 상시 노출되는 클러스터: **키보드 열기/닫기, 설정, 텍스트 선택, 접속 상태 표시등(맨 우측)**
- 클러스터 왼쪽 영역에 현재 모드의 버튼들이 표시됨
- 모바일 기준 **최대 3줄** (특수키 모드 3줄, 설정/선택 모드 1줄)
- 필수 특수키 전부 수용: Esc, `` ` ``, Tab, Shift(좌), Ctrl(좌), Alt(좌), Win(좌),
  Backspace, `\`, Enter, F1~F12, Ins, Del, Home, End, PgUp, PgDn, 방향키 4개 (총 32키)

## 2. 전체 구조

하단바 = 위쪽 가변 영역(모드별 0~2줄) + **하단 고정줄 1줄**.
하단 고정줄 = 좌측 모드 콘텐츠 영역(flex) + 우측 상시 클러스터.

```
┌──────────────────────────────────────────────┐
│  (모드별 상단 줄 — 특수키 모드에서만 2줄 존재)     │
├──────────────────────────────┬───────────────┤
│  모드 콘텐츠 (좌측, flex:1)     │ ⌨ ⚙ ⬚선택 ●  │  ← 하단 고정줄
└──────────────────────────────┴───────────────┘
```

우측 클러스터 (항상 표시, 순서 고정):

| 항목 | 동작 |
|---|---|
| `⌨` 키보드 | `term.textarea.focus()` ↔ `blur()` 로 모바일 IME 열기/닫기. 열림 상태는 `visualViewport` 높이로 추적해 active 표시 |
| `⚙` 설정 | 설정 모드 토글. 활성 시 highlight, 다시 누르면 특수키 모드 복귀 |
| `⬚` 선택 | 텍스트 선택 모드 토글. 동작 동일 |
| `●` 상태등 | 기존 `#status` 이전. connected 초록 / disconnected 빨강. 맨 우측 끝 |

모드 전환 = 클러스터 버튼 자체가 담당하므로 별도 탭 UI 불필요.
설정/선택 버튼 둘 다 꺼진 상태 = 특수키 모드(기본).
모드 전환 시 `fitAddon.fit()` 호출 (바 높이가 3줄↔1줄로 변함).

기존 플로팅 `#toggle-btn`(툴바 전체 접기 ☰)은 그대로 유지 — 클러스터의 ⌨는 IME 전용.

## 3. 특수키 모드 (기본, 3줄)

32키를 3줄에 넣기 위해 **Fn 레이어** 사용: F1~F12는 `Fn` 토글을 켰을 때
1~2번째 줄이 통째로 교체되어 나타난다. 실제 노트북 키보드와 같은 멘탈 모델.

### 기본 레이어

```
줄1 │ Esc   `   Tab   \   /   ⌫   Ins  Del   ⏎       (9키)
줄2 │ Fn  Ctrl  Alt  Shift  Win  Home  End  PgUp  PgDn (9키)
줄3 │ ◀   ▲   ▼   ▶        │        ⌨  ⚙  ⬚  ●      (4키 + 클러스터)
```

### Fn 레이어 (Fn 활성 시 줄1·줄2만 교체, 줄3 유지)

```
줄1 │ F1  F2  F3  F4  F5  F6                          (6키)
줄2 │ Fn* F7  F8  F9  F10  F11  F12                   (7키)
줄3 │ ◀   ▲   ▼   ▶        │        ⌨  ⚙  ⬚  ●
```

- `Fn`은 토글(누르면 레이어 유지, 다시 누르면 복귀). F키 입력 후 자동 복귀 안 함 —
  F5 연타(새로고침 등) 시나리오 때문에 유지가 낫다.
- 폭 검증: 360px 뷰포트, 좌우 패딩 16px, gap 3px 기준 최대 9키 줄 →
  키당 약 35px. 현재 `@media (max-width:400px)` 최소폭 28px보다 넉넉. 버튼은
  `flex:1; min-width:0` 로 균등 분배.
- `⏎`(Enter)는 `accent`, `⌫`는 시각적으로 약간 넓게(`flex:1.2`).

### 모디파이어 (Ctrl / Alt·Opt / Shift / Win·Cmd) — 스티키 원샷

기존 Ctrl 토글 로직을 4개 모디파이어로 일반화:

- 탭 → 활성(highlight), **다음 키 입력 1회에 적용 후 자동 해제**.
- 더블탭 → 락(계속 유지), 다시 탭 → 해제. (선택 구현, 1차에서는 원샷만 가능)
- 조합 대상 두 종류:
  1. **온스크린 특수키**: CSI 모디파이어 코드로 합성 (아래 표)
  2. **타이핑 문자** (물리 키보드 keydown + IME `term.onData` 1글자):
     - Ctrl+문자 → `code & 0x1f` (예: c → `\x03`)
     - Alt+문자 → `\x1b` + 문자
     - Ctrl+Alt+문자 → `\x1b` + ctrl code
     - Shift+문자 → 대문자 (물리 키보드는 xterm이 자체 처리하므로 IME 경로만)
- 모디파이어 코드: `m = 1 + Shift(1) + Alt(2) + Ctrl(4) + Meta(8)`
- Win/Cmd 키: 단독 전송 불가(터미널에 대응 시퀀스 없음). **Meta 비트(8)로만**
  조합에 참여. Mac의 Command와 동일 개념이므로 유지 확정. 단독 탭은 스티키 토글만 수행.
- **서버 OS 적응 라벨** (구현 확정): 모디파이어는 서버 셸이 받는 개념이므로
  라벨 기준은 클라이언트 브라우저가 아니라 **터미널이 실행 중인 서버 OS**.
  (리눅스 서버를 아이폰으로 볼 때 ⌘가 나오면 안 됨)
  - 전달 경로: ttyd `-t platform=<os>` (client option, 번들 1.7.7 지원 확인).
    접속 직후 `'2'`(SVR_PREFERENCES) 메시지의 JSON에 실려 오며, `index.html`이
    이미 이 메시지를 파싱 중(`prefs.fontSize` 처리부)이라 `prefs.platform` 한 줄 추가.
  - 라벨 매핑 (확정): `windows` → `Alt`/`Win`, `macos` → `⌥`(옵션 로고)/`⌘`(커맨드 로고),
    `linux` → `Alt`/`Super`. 미전달(플래그 없이 수동 실행) 시 기본 `Alt`/`Win`.
  - 타이밍: preferences는 WS 핸드셰이크 후 도착 → 최초 접속에서 라벨이 잠깐
    기본값으로 보일 수 있음. `localStorage`에 마지막 platform을 캐시해 재방문
    플리커 제거.
  - 전송 시퀀스는 라벨과 무관하게 동일(Alt=비트2, Meta=비트8). `textContent`
    교체만 — 마크업 분기 불필요.
  - **런처 수정 필요 (6곳)**: 각 실행 지점에 `-t platform=…` 추가
    - `bin/ttyd.bat` (수동, windows)
    - `bin/install-service.bat` — NSSM `AppParameters` 2곳 (안내 echo + 실제 set, windows)
    - `macos/ttyd.sh` + `macos/ttyd-wrapper.plist` `ProgramArguments` (macos)
    - `linux/ttyd.sh` + `linux/ttyd-wrapper.service` `ExecStart` (linux)
- 인터셉트 지점:
  - 물리 키보드: `term.attachCustomKeyEventHandler` (기존 로직 확장)
  - 모바일 IME: Android는 keydown이 keyCode 229로 불완전 → `term.onData` 앞단에서
    변환. **한글 IME 다글자 가드 (구현 확정)**: 스티키 활성 시 "정확히 1글자 &&
    코드포인트 < 0x80(ASCII)"일 때만 변환하고 스티키를 소모. 한글 조합 문자·자동완성
    다글자·붙여넣기는 원본 그대로 통과시키되 스티키는 유지(오소모 방지).
- 스티키 상태는 모드 전환·Fn 토글 시 전부 해제.

### 키 시퀀스 표

| 키 | 기본 | 모디파이어 적용 시 |
|---|---|---|
| Esc | `\x1b` | — |
| `` ` `` | `` ` `` | Shift → `~` (문자 치환) |
| `\` | `\` | Shift → `\|` (문자 치환) |
| Tab | `\x09` | Shift → `\x1b[Z` |
| ⌫ | `\x7f` | Alt → `\x1b\x7f`, Ctrl → `\x08` |
| ⏎ | `\x0d` | — |
| ◀▲▼▶ | `\x1b[D/A/B/C` | `\x1b[1;{m}D/A/B/C` |
| Home / End | `\x1b[H` / `\x1b[F` | `\x1b[1;{m}H` / `\x1b[1;{m}F` |
| Ins / Del | `\x1b[2~` / `\x1b[3~` | `\x1b[2;{m}~` / `\x1b[3;{m}~` |
| PgUp / PgDn | `\x1b[5~` / `\x1b[6~` | `\x1b[5;{m}~` / `\x1b[6;{m}~` |
| F1~F4 | `\x1bOP` `\x1bOQ` `\x1bOR` `\x1bOS` | `\x1b[1;{m}P/Q/R/S` |
| F5~F12 | `\x1b[15~` `[17~` `[18~` `[19~` `[20~` `[21~` `[23~` `[24~` | `~` 앞에 `;{m}` 삽입 |

기존 전용 Ctrl+C/D/Z/L 버튼은 제거 확정 — 스티키 Ctrl + IME/물리 키보드로 대체.
전용 `^C` 버튼도 두지 않는다.

## 4. 설정 모드 (1줄)

하단 고정줄의 좌측 영역만 사용. 상단 줄 없음 → 바 전체가 1줄로 축소.

```
줄1 │ A−  [14]  A+   │   ⟳ 재시작        │  ⌨  ⚙*  ⬚  ●
```

- **폰트 크기**: 기존 `FONT_SIZES` / `adjustFont` / localStorage 로직 재사용.
- **터미널 재시작** (`danger` 스타일):
  - ttyd는 접속마다 새 프로세스를 스폰하므로 소켓 재연결 = 셸 재시작.
  - 구현: `reconnectDelay` 백오프를 타지 않도록 전용 경로 —
    `socket.close()` → `term.reset()` → 즉시 `connect()`.
  - 오조작 방지: 1회 탭 시 버튼이 "확인?"으로 바뀌고 2초 내 재탭 시 실행.
- 향후 항목(테마, 폰트 패밀리 등)은 이 줄에 추가하되 1줄 초과 시 가로 스크롤
  (`overflow-x:auto`)로 처리 — 세로 3줄 제약은 특수키 모드에만 해당하나 일관 유지.

## 5. 텍스트 선택 모드 (1줄)

```
줄1 │ 전체  복사  붙여넣기  해제   │   ⌨  ⚙  ⬚*  ●
```

- **터치 제스처 컨트롤러** (구현 반영 — 초기 touch-이벤트 방식에서 교체):
  - 문제: xterm 자체 터치 스크롤은 `.xterm-viewport`에만 붙어 있어 글자 레이어
    위 터치는 스크롤이 안 되고, touch 이벤트 기반 선택은 브라우저 long-press
    제스처 중재에 뺏겨 한 글자 선택으로 끝남.
  - 해결: 컨테이너 캡처 단계의 **Pointer Events + `setPointerCapture`** 통합
    컨트롤러가 터미널 위 모든 터치를 소유 (mouse 포인터는 제외 — 데스크톱은
    xterm 네이티브 동작 유지).
    - 일반 모드: 1지 드래그 = 셀 높이 단위 라인 스크롤(잔여분 누적), 탭 = 포커스
    - 선택 모드: 1지 드래그 = 셀 선택, 두 번째 손가락 = 선택 고정 후 스크롤 전환
  - raw `touchstart/move`는 캡처 단계에서 `stopPropagation + preventDefault`로
    차단해 xterm 내부 핸들러/브라우저 폴백과의 이중 처리를 방지.
  - 셀 좌표는 `.xterm-screen` rect ÷ cols/rows 근사 (프라이빗 API 의존 없음).
  - 스크롤백 선택은 1차 범위 제외(현재 뷰포트만). 필요 시 후속.
- 버튼:
  - `전체` → `term.selectAll()`
  - `복사` → 기존 clip-copy 로직 이전 (clipboard API + execCommand 폴백)
  - `붙여넣기` → 기존 clip-paste 로직 이전
  - `해제` → `term.clearSelection()`
- 선택 완료(touchend) 시 자동 복사 옵션은 1차 제외 — 명시적 복사 버튼 우선.
- 모드 이탈 시 터치 핸들러 해제 + `clearSelection()`.

## 6. DOM / CSS 골격

```html
<div id="toolbar" data-mode="keys">
  <!-- 특수키 모드 전용 상단 2줄 (레이어별 줄 세트) -->
  <div class="mode-rows" id="keys-rows">
    <div class="toolbar-row layer-base">…줄1…</div>
    <div class="toolbar-row layer-base">…줄2…</div>
    <div class="toolbar-row layer-fn hidden">…F1~F6…</div>
    <div class="toolbar-row layer-fn hidden">…Fn F7~F12…</div>
  </div>
  <!-- 하단 고정줄 -->
  <div class="toolbar-row" id="row-bottom">
    <div id="mode-area">
      <div class="mode-pane" data-pane="keys">◀ ▲ ▼ ▶</div>
      <div class="mode-pane" data-pane="settings">A− 14 A+ | ⟳ 재시작</div>
      <div class="mode-pane" data-pane="select">전체 복사 붙여넣기 해제</div>
    </div>
    <div id="cluster">⌨ ⚙ ⬚ ●</div>
  </div>
</div>
```

- 표시 제어는 전부 CSS: `#toolbar[data-mode="keys"] …` 선택자로 해당 pane/rows만 노출.
  JS는 `data-mode` 속성과 `fn-layer` 클래스만 토글.
- 버튼: `flex:1; min-width:0; height:40px` (≤400px에서 34px), `touch-action:manipulation`.
- 기존 `@media (min-width:768px)` 가로 배치 특례는 제거하고 동일 레이아웃 사용
  (데스크톱은 물리 키보드가 있어 툴바 의존도가 낮음).
- 키 시퀀스는 전부 `data-seq` / `data-key` 속성 + 단일 위임 리스너로 처리 —
  현재의 id별 개별 `addEventListener` 나열 제거.

## 7. 상태 모델

```
mode      ∈ { keys, settings, select }   // 기본 keys
fnLayer   : bool                          // keys 모드에서만 유효
sticky    : { ctrl, alt, shift, meta }    // keys 모드에서만 유효
kbOpen    : bool                          // visualViewport로 추적
```

전이 규칙: 모드 변경 → `fnLayer=false`, `sticky` 전부 해제, `fit()` 재실행.
선택 모드 진입/이탈 → 터치 핸들러 부착/해제.

## 8. 구현 순서

1. 마크업/CSS 교체: 3모드 골격 + 클러스터 + Fn 레이어 (기능 없이 배치 확인)
2. 키 시퀀스 테이블(`data-seq`) + 위임 리스너 + Fn 레이어 토글
3. 스티키 모디파이어 (CSI 합성 + onData/keydown 인터셉트)
4. 설정 모드 (폰트 이전 + 재시작)
5. 선택 모드 (터치 선택 + 클립보드 버튼 이전)
6. 키보드 열기/닫기 버튼 + visualViewport 연동
7. 런처 6곳에 `-t platform=…` 추가 + `prefs.platform` 라벨 스왑 배선
8. 구식 코드 제거: 기존 Row1/Row2, `KEYS`/`CTRL_KEYS` id 배선, 전용 Ctrl 버튼

## 9. 검증 (수용 기준)

- 360px 폭 모바일에서 특수키 모드가 정확히 3줄, 가로 스크롤/줄바꿈 없음
- 필수 32키 전부 도달 가능 (F키는 Fn 레이어 경유 — 탭 2회 이내)
- `vim`에서: Esc, 방향키, Ctrl+w(스티키), Shift+Tab 동작 확인
- `less`/`htop`에서: F키, PgUp/PgDn, Home/End 확인
- 재시작 버튼 → 새 셸 프롬프트, 상태등 깜빡임 후 복귀
- 선택 모드에서 드래그 선택 → 복사 → 붙여넣기 왕복 확인
- 설정/선택 모드에서 바가 1줄로 줄고 터미널이 `fit()`으로 확장됨
- **macOS 서버**에 접속 시 (클라이언트 OS 무관) 모디파이어 라벨이
  `⌥`/`⌘`(로고만)로 표시됨; 리눅스 서버 → `Alt`/`Super`; 윈도우 서버·플래그 없는
  수동 실행 → `Alt`/`Win`
- 스티키 Ctrl 활성 상태에서 한글 입력 시: 한글은 그대로 출력, 스티키 유지;
  이후 ASCII 1글자 입력 시 Ctrl 조합으로 변환·소모

## 10. 확정 사항 / 잔여 리스크

확정 (결정 완료):

- 전용 `^C` 버튼 없음 — 스티키 Ctrl 경로로 통일.
- 한글 IME 다글자 입력 가드 구현 (§3 인터셉트 규칙 참고).
- 터치 선택은 1차 근사(`clientWidth/cols` 셀 좌표)로 진행. 오차 불만 시 후속 개선.
- Win/Cmd 키 유지 — Mac Command 동등 개념, Meta 비트(8) 조합.
- 서버 OS 적응 라벨 구현 — ttyd `-t platform=…`으로 서버가 통지.
  `windows`/미전달 → `Alt`/`Win`, `linux` → `Alt`/`Super`,
  `macos` → `⌥`/`⌘` (옵션·커맨드 로고만, 텍스트 없음).
  클라이언트 브라우저 판별은 사용하지 않음 (서버 셸 기준 개념이므로).
- Fn 레이어 힌트 기능은 미구현 (라벨은 `Fn` 그대로).

잔여 리스크:

- **터치 선택 정밀도**: letter-spacing·소수점 셀 폭에서 근사 오차 가능 — 수용하고 진행.
- **Win/Meta 조합**: 대부분의 TUI가 무시함. 시퀀스는 표준(비트 8)대로 보내되
  실효성은 앱에 달려 있음을 인지.
