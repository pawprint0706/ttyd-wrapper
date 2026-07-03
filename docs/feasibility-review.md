# ttyd Web Wrapper Feasibility Review

## 1. 현황 분석

### 1.1 현재 구성

| 항목 | 내용 |
|------|------|
| 실행 파일 | `bin/ttyd.exe` (v1.7.7) |
| 실행 스크립트 | `bin/ttyd.bat` |
| 명령 | `ttyd.exe --writable -p 33322 --cwd %USERPROFILE% powershell.exe` |
| 접속 방식 | 브라우저에서 `http://<host>:33322` 접속 → xterm.js 기반 터미널 |
| WebSocket | ttyd가 `/ws` 엔드포인트로 터미널 I/O 중계 |

### 1.2 문제점 (모바일 환경)

| 문제 | 원인 |
|------|------|
| 폰트 크기 조절 불가 | 기본 index.html에 폰트 크기 컨트롤 UI 없음. `--client-option fontSize=NN`으로 서버측 고정은 가능하나 클라이언트 동적 조절 미지원 |
| 특수키 입력 불가 | 모바일 소프트 키보드는 방향키, Esc, Tab, Ctrl, Home, End 등의 물리키 미제공. xterm.js 자체는 해당 키 입력을 처리할 수 있으나 입력 수단이 없음 |

---

## 2. 기술 검토

### 2.1 ttyd의 커스텀 index.html 지원 (`-I` / `--index`)

ttyd v1.7.7은 `-I <path>` 옵션으로 **기본 index.html을 사용자 정의 HTML로 교체**할 수 있다. 이 커스텀 페이지에서 ttyd의 WebSocket에 직접 연결하여 터미널 UI를 완전히 제어할 수 있다.

```
ttyd.exe --writable -p 33322 -I ./public/index.html --cwd %USERPROFILE% powershell.exe
```

### 2.2 WebSocket 프로토콜 (실측 검증됨)

ttyd의 WebSocket (`ws://host:33322/ws`)은 **subprotocol `["tty"]`** 필수, 바이너리 프레임에 **1바이트 커맨드 prefix**를 사용한다.

**연결 핸드셰이크 (필수):**

1. `GET /token` → `{"token": ""}` 수신 (인증 미설정 시 빈 문자열)
2. `new WebSocket(url, ['tty'])` 로 연결
3. **첫 메시지로 raw JSON 전송** — 이 메시지가 서버측 PTY 프로세스를 스폰한다. 생략 시 커서만 뜨고 입출력이 전혀 동작하지 않는다:

```json
{"AuthToken": "", "columns": 80, "rows": 24}
```

**이후 메시지 (Client → Server, 1바이트 prefix):**

| Prefix | 의미 | 페이로드 |
|--------|------|----------|
| `'0'` (0x30) | INPUT | UTF-8 키 입력 (escape sequence 포함: `\x1b[A`=↑, `\x03`=Ctrl+C, `\x09`=Tab, …) |
| `'1'` (0x31) | RESIZE_TERMINAL | JSON `{"columns":N,"rows":M}` |
| `'2'` (0x32) | PAUSE | (flow control) |
| `'3'` (0x33) | RESUME | (flow control) |

**Server → Client (1바이트 prefix):**

| Prefix | 의미 | 페이로드 |
|--------|------|----------|
| `'0'` (0x30) | OUTPUT | PTY 출력 → `term.write(payload)` |
| `'1'` (0x31) | SET_WINDOW_TITLE | UTF-8 타이틀 문자열 |
| `'2'` (0x32) | SET_PREFERENCES | JSON 클라이언트 옵션 (`fontSize` 등) |

### 2.3 xterm.js API

ttyd 내장 페이지와 동일하게 xterm.js를 사용한다. 주요 제어 API:

```javascript
const encoder = new TextEncoder();

// 1. 토큰 취득 후 WebSocket 연결 (subprotocol 'tty' 필수)
const token = (await (await fetch('token')).json()).token || '';
const socket = new WebSocket(`ws://${location.host}/ws`, ['tty']);
socket.binaryType = 'arraybuffer';

// 2. 핸드셰이크 — 첫 메시지가 PTY 프로세스를 스폰
socket.onopen = () => {
  socket.send(encoder.encode(JSON.stringify(
    { AuthToken: token, columns: term.cols, rows: term.rows })));
};

// 3. 서버 출력: 1바이트 prefix 파싱 후 렌더링
socket.onmessage = (event) => {
  const bytes = new Uint8Array(event.data);
  if (bytes[0] === 0x30) term.write(bytes.subarray(1)); // '0' = OUTPUT
};

// 4. 키 입력: '0' prefix 붙여 전송
function sendInput(data) {
  const enc = encoder.encode(data);
  const msg = new Uint8Array(1 + enc.length);
  msg[0] = 0x30; // '0' = INPUT
  msg.set(enc, 1);
  socket.send(msg);
}
term.onData(sendInput);
sendInput('\x1b[A');           // ↑ 방향키 (특수키 시뮬레이션)

// 5. 리사이즈: '1' + JSON
socket.send(encoder.encode('1' + JSON.stringify(
  { columns: term.cols, rows: term.rows })));

// 폰트 크기 동적 변경
term.options.fontSize = 18;    // 실시간 적용
```

---

## 3. 아키텍처 설계

### 3.1 개요

```
┌──────────────────────────────────────────────────┐
│ 모바일 브라우저                                    │
│ ┌──────────────────────────────────────────────┐ │
│ │              Toolbar (커스텀 UI)               │ │
│ │  [A-] [A+] │ [Esc] [Tab] [Ctrl] [Home] [End] │ │
│ │  ▲ ▼ ◀ ▶  │ [PgUp] [PgDn] [Del] [Ins]       │ │
│ ├──────────────────────────────────────────────┤ │
│ │                                              │ │
│ │         xterm.js 터미널 (ttyd 릴레이)          │ │
│ │         WebSocket ws://host:33322/ws         │ │
│ │                                              │ │
│ └──────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────┘
         │
         │ WebSocket (바이너리)
         ▼
┌──────────────────────────────────────────────────┐
│ ttyd.exe :33322                                   │
│   └─ PowerShell.exe (PTY)                         │
└──────────────────────────────────────────────────┘
```

### 3.2 컴포넌트 구성

| 컴포넌트 | 역할 | 기술 |
|----------|------|------|
| `index.html` | 진입점. ttyd `-I`로 지정 | 단일 HTML 파일 |
| xterm.js | 터미널 렌더링 엔진 | npm CDN (5.x) |
| xterm-addon-fit | 화면 크기에 맞춰 자동 리사이즈 | npm CDN |
| xterm-addon-web-links | URL 링크 감지 | npm CDN |
| xterm-addon-webgl | WebGL 가속 렌더링 (선택) | npm CDN |
| Toolbar UI | 폰트 크기, 특수키 버튼 | Vanilla JS + CSS |
| WebSocket 클라이언트 | ttyd 연결 | 브라우저 내장 WebSocket |

### 3.3 폰트 크기 조절

```javascript
// 버튼 클릭으로 폰트 크기 변경
const FONT_SIZES = [10, 12, 14, 16, 18, 20, 24, 28];
let currentFontIdx = 2; // 기본 14px

function increaseFont() {
  if (currentFontIdx < FONT_SIZES.length - 1) {
    currentFontIdx++;
    term.options.fontSize = FONT_SIZES[currentFontIdx];
    fitAddon.fit(); // 리사이즈 재적용
  }
}
```

### 3.4 특수키 입력

```javascript
const KEY_MAP = {
  'ArrowUp':    '\x1b[A',
  'ArrowDown':  '\x1b[B',
  'ArrowRight': '\x1b[C',
  'ArrowLeft':  '\x1b[D',
  'Escape':     '\x1b',
  'Tab':        '\x09',
  'Home':       '\x1b[H',
  'End':        '\x1b[F',
  'PageUp':     '\x1b[5~',
  'PageDown':   '\x1b[6~',
  'Delete':     '\x1b[3~',
  'Insert':     '\x1b[2~',
  'Backspace':  '\x7f',
  'Enter':      '\x0d',
  // Ctrl 조합
  'CtrlC':      '\x03',
  'CtrlD':      '\x04',
  'CtrlZ':      '\x1a',
  'CtrlL':      '\x0c',
};

function sendKey(name) {
  socket.send(KEY_MAP[name]);
}
```

---

## 4. 기술 스택

| 계층 | 선택 | 근거 |
|------|------|------|
| 런타임 | **Vanilla HTML/CSS/JS** (단일 파일) | ttyd `-I`는 정적 파일 하나만 지정 가능. 번들러 불필요. 간결함이 최우선 |
| 터미널 | **xterm.js 5.x** (CDN) | ttyd 자체가 사용하는 라이브러리. 안정성과 호환성 보장 |
| Addons | `fit`, `web-links` (CDN) | 최소한의 addon으로 필요한 기능만 |
| CSS | **Raw CSS + CSS Variables** | 프레임워크 불필요. 다크 테마, 모바일 우선 |
| 아이콘 | **SVG inline** | 외부 의존성 제로 |
| 번들링 | **없음** (CDN + 단일 HTML) | 복잡도 최소화. ttyd가 정적 파일을 직접 서빙 |

### 4.1 CDN 리소스

```
xterm@5.3.0        https://cdn.jsdelivr.net/npm/xterm@5.3.0/lib/xterm.js
xterm.css           https://cdn.jsdelivr.net/npm/xterm@5.3.0/css/xterm.css
fit-addon@0.8.0     https://cdn.jsdelivr.net/npm/xterm-addon-fit@0.8.0/lib/xterm-addon-fit.js
web-links@0.9.0     https://cdn.jsdelivr.net/npm/xterm-addon-web-links@0.9.0/lib/xterm-addon-web-links.js
```

> **참고**: 오프라인 환경이 필요하다면 CDN 파일을 로컬에 다운로드하여 ttyd의 정적 파일 서빙 경로에 배치 가능. 필요 시 `public/vendor/` 경로 구성 검토.

---

## 5. 실현 가능성 평가

### 5.1 확실히 가능 ✅

| 기능 | 구현 난이도 | 설명 |
|------|-----------|------|
| 폰트 크기 +/- 버튼 | **하** | `term.options.fontSize` 실시간 변경 + `fit()` 호출 |
| 방향키 (↑↓←→) | **하** | ANSI escape sequence WebSocket 전송 |
| Esc, Tab | **하** | `\x1b`, `\x09` 전송 |
| Home, End, PageUp/Down, Del | **하** | 표준 VT escape sequence |
| Ctrl+C, Ctrl+D, Ctrl+Z, Ctrl+L | **하** | ASCII 제어 문자 전송 |
| 터미널 자동 리사이즈 | **하** | `fitAddon.fit()` + `ResizeObserver` |
| 다크 테마 | **하** | xterm.js theme 옵션 |
| 가로/세로 화면 대응 | **중** | CSS media query + fit addon |
| 툴바 접기/펴기 | **중** | CSS transition |

### 5.2 가능하지만 주의 필요 ⚠️

| 기능 | 설명 | 대응 방안 |
|------|------|-----------|
| Ctrl 키 조합 (Ctrl+A, Ctrl+E 등) | 모바일에서 Ctrl 토글 상태를 UI로 구현해야 함 | 토글 버튼: "Ctrl" 활성화 후 다음 입력과 조합 |
| 복사/붙여넣기 | Clipboard API는 보안 컨텍스트(HTTPS/localhost) 전용 — LAN HTTP 접속 시 모든 브라우저에서 `navigator.clipboard` 미노출 | 복사: `execCommand('copy')` 폴백으로 HTTP에서도 동작. 붙여넣기 버튼: HTTPS 적용 시 활성화(iOS는 시스템 확인 팝업). HTTP에서는 소프트 키보드 네이티브 붙여넣기로 대체 |
| 멀티터치 제스처 | 핀치 줌, 두 손가락 스크롤과 충돌 | `touch-action: none`으로 xterm 영역 내 브라우저 제스처 억제 |
| 소프트 키보드와의 공존 | 툴바가 키보드를 가리지 않도록 | `visualViewport` API로 키보드 높이 감지, 툴바 위치 조정 |
| WebSocket 재연결 | 네트워크 불안정 시 세션 유지 | 자동 재연결 로직 + UI 표시 |

### 5.3 제한 사항 ❌

| 제한 | 이유 | 우회책 |
|------|------|--------|
| 세션 비영속 | 접속마다 **독립 PowerShell 프로세스** 스폰 (실측: 동시 2접속 → PID 27180/16784 상이). 연결 종료 시 ttyd가 SIGHUP으로 프로세스 종료 → 모바일 백그라운드 전환 시 작업 유실 | 재접속 세션 복원이 필요하면 tmux 유사 레이어 검토 (추후 과제) |
| Shift+키 조합 (대문자 외) | 모바일 키보드에서 Shift+방향키 등 지원 불가 | 필요 키는 툴바에 개별 버튼으로 추가 |
| Alt/Meta 키 | 모바일 OS 레벨에서 Alt 키 미제공 | 툴바에 토글 버튼 추가로 대응 가능하나 사용성 낮음 |
| 파일 업로드/다운로드 | ttyd 기본 기능에 없음 | **구현 계획 없음** (프로젝트 범위 외) |
| 푸시 알림 | 브라우저 백그라운드에서 WebSocket 연결 불안정 | PWA + Service Worker 검토 가능하나 복잡도 높음 |

---

## 6. 개발 계획

### 6.1 Phase 1 — 코어 래퍼 (MVP)

| 순서 | 작업 | 산출물 |
|------|------|--------|
| 1 | xterm.js + fit addon을 사용한 커스텀 `index.html` 생성 | `public/index.html` |
| 2 | ttyd WebSocket 연결 및 터미널 렌더링 | 기본 터미널 동작 확인 |
| 3 | 폰트 크기 조절 UI (+, - 버튼) | 툴바 상단 고정 |
| 4 | 방향키, Esc, Tab, Enter 버튼 | 기본 특수키 입력 가능 |
| 5 | `ttyd.bat`에 `-I public/index.html` 옵션 추가 | 통합 실행 |

### 6.2 Phase 2 — 특수키 확장

| 순서 | 작업 | 산출물 |
|------|------|--------|
| 6 | Home, End, PgUp, PgDn, Del, Ins 버튼 | 전체 특수키 커버 |
| 7 | Ctrl 토글 + 주요 Ctrl 조합 (C, D, Z, L, A, E) | Ctrl 키 기능 |
| 8 | 복사/붙여넣기 버튼 | 클립보드 연동 |

### 6.3 Phase 3 — 모바일 최적화

| 순서 | 작업 | 산출물 |
|------|------|--------|
| 9 | 반응형 CSS (모바일/태블릿/데스크톱) | 모든 화면 크기 대응 |
| 10 | 툴바 접기/펴기 (터미널 공간 확보) | 화면 공간 활용 |
| 11 | `visualViewport` API로 키보드 회피 | 소프트 키보드 가림 방지 |
| 12 | WebSocket 재연결 + 상태 표시 | 네트워크 복원력 |

### 6.4 디렉토리 구조 (최종)

```
ttyd-wrapper/
├── bin/
│   ├── ttyd.exe               # ttyd 바이너리 (v1.7.7)
│   ├── ttyd.bat               # 수동 실행 스크립트
│   ├── nssm.exe               # 서비스 매니저 (NSSM)
│   ├── install-service.bat    # 윈도우 서비스 등록 (관리자 자동 승격)
│   ├── uninstall-service.bat  # 서비스 제거
│   └── service-launcher.ps1   # 기동 시 레지스트리에서 사용자 PATH 재구성 후 ttyd 실행
├── linux/                     # Linux 포팅 (systemd 사용자 유닛, WSL2 테스트 완료)
├── macos/                     # macOS 포팅 (LaunchAgent, 실기 맥 테스트 완료)
├── public/
│   ├── index.html             # 커스텀 웹 래퍼 (단일 파일, 벤더 인라인)
│   └── vendor/                # xterm.js 원본 (참조용, 런타임 미사용)
├── logs/                      # 서비스 로그 (설치 시 생성, 1MB 로테이션)
└── docs/
    └── feasibility-review.md  # 본 문서
```

### 6.5 윈도우 서비스 등록 (NSSM)

| 항목 | 값 |
|------|-----|
| 서비스 이름 | `ttyd-wrapper` |
| 시작 유형 | 자동 (부팅 시 시작) |
| 크래시 복구 | 3초 후 자동 재시작 |
| 로그 | `logs\ttyd.log` (1MB 로테이션) |
| 방화벽 | 설치 시 TCP 33322 인바운드 규칙 자동 등록 |

- **설치**: `bin\install-service.bat` 실행 (UAC 자동 승격, 기존 서비스 있으면 교체)
- **제거**: `bin\uninstall-service.bat` (서비스 + 방화벽 규칙 삭제)
- **검증**: `bin\install-service.bat /dry` — 실행될 명령을 출력만 함
- 포트·쉘·작업 디렉토리 변경은 `install-service.bat` 상단 Configuration 블록에서 수정

---

## 7. 결론

### 종합 판정: **실현 가능 (Feasible)**

- ttyd의 `--index` 옵션으로 **커스텀 HTML을 서빙**할 수 있으므로, 별도 웹 서버 없이 **단일 HTML 파일**로 모든 요구사항을 구현 가능
- xterm.js API는 폰트 크기 동적 변경과 터미널 데이터 주입을 완벽히 지원
- 모든 특수키는 표준 ANSI/VT escape sequence로 전송 가능하며, xterm.js가 이를 WebSocket 바이너리 프레임으로 ttyd에 전달
- **개발 난이도: 중하** — 복잡한 백엔드 로직 없이 프론트엔드 단일 파일로 완결

### 권장 접근 방식

1. **단일 `index.html` 파일**로 모든 UI와 로직을 구현
2. xterm.js + addons는 CDN에서 로드 (오프라인 필요 시 로컬 벤더링)
3. ttyd.bat에 `-I` 옵션만 추가하여 기존 실행 방식을 그대로 유지
4. 모바일 우선 CSS로 설계하고, 데스크톱도 자연스럽게 지원
