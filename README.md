# ttyd-wrapper

**모바일 친화적인 ttyd 웹 터미널 래퍼** — Windows PowerShell을 웹 브라우저로 중계하고, 모바일에서 불가능했던 폰트 크기 조절과 특수키(방향키, Esc, Tab, Ctrl 조합 등) 입력을 웹 UI로 제공한다.

## 1. 프로젝트 개요

[ttyd](https://github.com/tsl0922/ttyd)는 터미널을 웹으로 중계해주는 도구지만, 기본 웹 페이지는 모바일 환경에서 두 가지 치명적인 한계가 있다:

1. **폰트 크기 조절 불가** — 작은 화면에서 가독성 조절 수단이 없음
2. **특수키 입력 불가** — 모바일 소프트 키보드에는 방향키, Esc, Tab, Ctrl, Home, End 등이 없음

본 프로젝트는 ttyd의 `-I`(커스텀 index) 옵션을 활용해 **단일 HTML 파일**로 위 문제를 해결한다. 별도 웹 서버나 빌드 과정 없이 ttyd가 직접 커스텀 페이지를 서빙하며, 페이지는 ttyd의 WebSocket 프로토콜로 터미널과 직접 통신한다.

## 2. 주요 기능

| 분류 | 기능 |
|------|------|
| 폰트 | A−/A+ 버튼으로 10~32px 실시간 조절 |
| 방향키 | ▲▼◀▶ 터치 버튼 |
| 특수키 | Esc, Tab, Enter, Home, End, PgUp, PgDn, Ins, Del |
| Ctrl 조합 | Ctrl 토글(시각 피드백) + 전용 버튼(C/D/Z/L) + 물리 키보드 조합(Ctrl+A/E/K/W 등 13종) |
| 클립보드 | 선택 복사 / 붙여넣기 버튼 |
| 반응형 | 모바일 우선 CSS, `100dvh` 뷰포트, 툴바 접기(모바일), 다크 테마 |
| 복원력 | WebSocket 자동 재연결(지수 백오프 1~10초) + 연결 상태 표시 |
| 오프라인 | xterm.js 전체 인라인 — 외부 CDN 의존성 0, 망분리 환경 동작 |
| 서비스 | NSSM 기반 윈도우 서비스 등록(부팅 자동 시작, 크래시 복구, 로그 로테이션) |

## 3. 기술 스펙

| 항목 | 내용 |
|------|------|
| 터미널 중계 | ttyd v1.7.7 (포트 33322, PowerShell 릴레이) |
| 터미널 렌더링 | xterm.js 5.3.0 + fit addon 0.8.0 + web-links addon 0.9.0 |
| 프론트엔드 | Vanilla HTML/CSS/JS 단일 파일 (`public/index.html`, 약 305KB, 벤더 인라인) |
| 통신 | ttyd WebSocket 프로토콜 — subprotocol `["tty"]`, 토큰 핸드셰이크, 1바이트 커맨드 prefix |
| 서비스 관리 | NSSM 2.24 |
| 지원 환경 | Windows (호스트), 모던 브라우저 (Chrome 108+ / Safari 15.4+ / Firefox 101+) |

### ttyd WebSocket 프로토콜 요약

```
1. GET /token                        → {"token": ""}
2. new WebSocket(url, ['tty'])       → subprotocol 필수
3. 첫 메시지: {"AuthToken":"","columns":N,"rows":M}  ← PTY 스폰 (생략 시 무반응)
4. 이후: '0'+bytes = 입력, '1'+JSON = 리사이즈  (수신: '0'=출력, '1'=타이틀, '2'=설정)
```

상세는 [docs/feasibility-review.md](docs/feasibility-review.md) §2.2 참조.

## 4. 프로젝트 구조

```
ttyd-wrapper/
├── bin/
│   ├── ttyd.exe               # ttyd 바이너리 (v1.7.7)
│   ├── ttyd.bat               # 수동 실행 스크립트
│   ├── nssm.exe               # 서비스 매니저 (NSSM)
│   ├── install-service.bat    # 윈도우 서비스 등록 (UAC 자동 승격)
│   ├── uninstall-service.bat  # 서비스 제거
│   └── service-launcher.ps1   # 서비스 기동 시 사용자 PATH 재구성 후 ttyd 실행
├── linux/
│   ├── ttyd.sh                # 수동 실행 (bash -l 릴레이)
│   ├── install-service.sh     # systemd 사용자 유닛 설치
│   ├── uninstall-service.sh   # 유닛 제거
│   └── ttyd-wrapper.service   # systemd 유닛 템플릿
├── macos/
│   ├── ttyd.sh                # 수동 실행 (zsh -l 릴레이)
│   ├── install-service.sh     # LaunchAgent 등록
│   ├── uninstall-service.sh   # Agent 제거
│   └── ttyd-wrapper.plist     # LaunchAgent 템플릿
├── public/
│   ├── index.html             # 커스텀 웹 래퍼 (단일 파일, 벤더 인라인)
│   └── vendor/                # xterm.js 원본 (참조용, 런타임 미사용)
├── logs/                      # 서비스 로그 (설치 시 생성, 1MB 로테이션)
├── docs/
│   └── feasibility-review.md  # 기술 검토 및 프로토콜 문서
└── README.md
```

## 5. 설치법

### 방법 A — 윈도우 서비스로 등록 (권장)

```bat
bin\install-service.bat
```

- UAC 프롬프트 자동 표시 (관리자 승격)
- 기존 서비스가 있으면 교체 (멱등)
- 부팅 시 자동 시작, 크래시 시 3초 후 재시작
- 방화벽 인바운드 규칙(TCP 33322) 자동 등록 — 모바일 접속에 필수
- 서비스는 `service-launcher.ps1`을 경유해 기동 — **서비스 시작 시마다** 레지스트리에서 머신+사용자 PATH를 새로 읽어 구성하므로, PATH 변경 후 **서비스 재시작만으로 반영**된다 (재설치 불필요). 설치 시점에는 변하지 않는 값(사용자 SID·프로필 경로)만 기록. 사용자 로그온 전(부팅 직후)에도 NTUSER.DAT를 임시 로드해 처리
- 설치 스크립트는 **본인 데스크톱 세션에서 실행**해야 한다 — 웹 터미널(SYSTEM 계정)에서 실행하면 잘못된 사용자를 캡처하므로 스크립트가 차단함
- 로그: `logs\ttyd.log` (1MB 로테이션)
- 실행될 명령 미리보기: `bin\install-service.bat /dry`

제거:

```bat
bin\uninstall-service.bat
```

### 방법 B — 수동 실행

```bat
bin\ttyd.bat
```

콘솔 창이 열려 있는 동안만 동작한다.

### 설정 변경

포트·쉘·작업 디렉토리는 `bin\install-service.bat` 상단 Configuration 블록에서 수정:

```bat
set "PORT=33322"
set "SHELL_CWD=%USERPROFILE%"
set "SHELL_CMD=powershell.exe"
```

수동 실행용 `bin\ttyd.bat`도 동일하게 맞춰야 한다.

### macOS / Linux

ttyd를 패키지로 설치한 뒤 (`brew install ttyd` / `sudo apt install ttyd`) OS 폴더의 스크립트를 실행한다:

```bash
./linux/install-service.sh     # Linux: systemd 사용자 유닛 (검증: WSL2 실측 통과)
./macos/install-service.sh     # macOS: LaunchAgent (로그인 시 시작)
```

- 서비스가 **사용자 본인 권한**으로 실행되므로 Windows판의 PATH 재구성 런처가 필요 없다 — 로그인 셸(`bash -l`/`zsh -l`)이 사용자 환경을 그대로 로드
- 포트 변경: `TTYD_PORT=8080 ./install-service.sh` 처럼 환경변수로 오버라이드
- 미리보기: `--dry` 플래그 (실행 없이 렌더링된 유닛/plist와 명령 출력)
- Linux 부팅 시 자동 시작: 스크립트가 `loginctl enable-linger`를 시도하며, 실패 시 안내 메시지 출력
- 제거: 각 폴더의 `uninstall-service.sh`
- 상세 분석: [docs/porting-analysis.md](docs/porting-analysis.md)

## 6. 이용방법

1. 같은 네트워크의 브라우저에서 `http://<PC의 IP>:33322/` 접속
2. 터미널 영역 탭 → 소프트 키보드로 일반 입력
3. 하단 툴바:
   - **A− / A+** — 폰트 크기 조절 (현재 크기 표시)
   - **▲▼◀▶** — 방향키 (명령 히스토리, 커서 이동)
   - **Esc / Tab / ⏎** — 특수키
   - **Home / End / PgUp / PgDn / Ins / Del** — 내비게이션 키
   - **Ctrl** — 토글 후 다음 키와 조합 (버튼이 빨간색 = 활성). 옆의 C/D/Z/L은 원터치 Ctrl+C/D/Z/L
   - **Copy / Paste** — 선택 복사 / 붙여넣기
4. 우측 하단 **☰** (모바일) — 툴바 접기/펴기
5. 우측 상단 **●** — 연결 상태 (녹색 = 연결됨, 적색 = 재연결 중)

> **참고 — 세션 동작**: 브라우저 접속마다 **독립된 PowerShell 프로세스**가 스폰된다 (실측 검증: 동시 접속 2개 → 서로 다른 PID). 즉 여러 기기에서 동시에 붙어도 서로 간섭하지 않는다. 단, 연결이 끊기면 해당 프로세스는 종료되므로 **세션은 유지되지 않는다**.
>
> **참고 — Paste 버튼**: Clipboard API는 보안 컨텍스트(HTTPS 또는 localhost)에서만 동작한다. LAN IP로 HTTP 접속 시 Paste 버튼은 브라우저 종류와 무관하게 동작하지 않는다 — 이때는 터미널에 포커스 후 **소프트 키보드의 네이티브 붙여넣기**(길게 눌러 붙여넣기)를 사용하면 된다. Copy는 폴백(`execCommand`)으로 HTTP에서도 동작한다.

## 7. 추후 개발 예정

- [ ] **인증** — ttyd `-c user:pass` 기본 인증 연동 및 서비스 스크립트 옵션화
- [ ] **HTTPS** — `-S/-C/-K` SSL 옵션 지원 (공용망 노출 시 필수). 적용 시 Paste 버튼도 모든 브라우저에서 활성화됨 (iOS Safari는 시스템 확인 팝업 추가)
- [ ] **세션 유지** — 현재 연결이 끊기면 PowerShell 프로세스가 종료됨 (모바일 브라우저 백그라운드 전환 시 작업 유실). 재접속 시 세션 복원을 위한 tmux 유사 레이어 검토
- [ ] **쉘 선택 UI** — PowerShell / cmd / WSL 전환
- [ ] **Alt/Meta 키 토글** — 현재 미지원 (툴바 확장으로 대응 가능)
- [ ] **PWA** — 홈 화면 설치, 전체 화면 모드

**구현 계획 없음**: 파일 전송(trzsz/ZMODEM), 커스텀 키 매크로

## 8. 라이선스 및 크레딧

- [ttyd](https://github.com/tsl0922/ttyd) — MIT License
- [xterm.js](https://github.com/xtermjs/xterm.js) — MIT License
- [NSSM](https://nssm.cc/) — Public Domain
