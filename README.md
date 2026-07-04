# ttyd-wrapper

**모바일 친화적인 ttyd 웹 터미널 래퍼** — Windows PowerShell을 웹 브라우저로 중계하고, 모바일에서 불가능했던 폰트 크기 조절과 특수키(방향키, Esc, Tab, Ctrl 조합 등) 입력을 웹 UI로 제공한다.

**다양한 플랫폼 지원** — Windows, Linux, macOS 지원. (전 플랫폼 실측 검증 완료)

## 1. 프로젝트 개요

[ttyd](https://github.com/tsl0922/ttyd)는 터미널을 웹으로 중계해주는 도구지만, 기본 웹 페이지는 모바일 환경에서 두 가지 치명적인 한계가 있다:

1. **폰트 크기 조절 불가** — 작은 화면에서 가독성 조절 수단이 없음
2. **특수키 입력 불가** — 모바일 소프트 키보드에는 방향키, Esc, Tab, Ctrl, Home, End 등이 없음

본 프로젝트는 ttyd의 `-I`(커스텀 index) 옵션을 활용해 **단일 HTML 파일**로 위 문제를 해결한다. 별도 웹 서버나 빌드 과정 없이 ttyd가 직접 커스텀 페이지를 서빙하며, 페이지는 ttyd의 WebSocket 프로토콜로 터미널과 직접 통신한다.

## 2. 주요 기능

| 분류 | 기능 |
|------|------|
| 모드 UI | 하단바 3모드 — 특수키(기본) / 설정 / 텍스트 선택. 우측 클러스터(선택·설정·키보드·상태등)로 전환 |
| 특수키 | Esc, Tab, `` ` ``, `-`, `\`, `'`, `/`, Del, Enter, Home, End, PgUp, PgDn, ▲▼◀▶ + Fn 레이어로 F1~F12. 기호키는 Shift 조합 시 `~ _ \| " ?` |
| 모디파이어 | Ctrl / Alt / Shift / Win 스티키 원샷 토글 — 온스크린 특수키(CSI 조합) 및 타이핑 문자(IME·물리 키보드)와 조합. 한글 등 다글자 입력은 그대로 통과 |
| 서버 OS 라벨 | ttyd `-t platform=…` 통지로 Alt/Win ↔ ⌥/⌘ ↔ Alt/Super 자동 표기 |
| 설정 모드 | A−/A+ 폰트 10~32px 실시간 조절 + 터미널 재시작(2탭 확인) |
| 텍스트 선택 | 터치 드래그 셀 선택 + 전체선택/복사/붙여넣기/해제 |
| 반응형 | 모바일 우선 CSS(3줄 고정 레이아웃), `100dvh` 뷰포트, 툴바 접기, 다크 테마 |
| 복원력 | WebSocket 자동 재연결(지수 백오프 1~10초) + 연결 상태 표시 |
| 오프라인 | xterm.js 전체 인라인 — 외부 CDN 의존성 0, 망분리 환경 동작 |
| 아이콘 | 루트 `icon.png` 기반 파비콘(16/32px) + 홈 화면 아이콘(180/192px) 전부 data URI 인라인 — Android Chrome '홈 화면에 추가' 시 전용 아이콘 적용 |
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
├── icon.png                   # 앱 아이콘 원본 (파비콘·홈 화면 아이콘으로 인라인 임베딩)
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
./macos/install-service.sh     # macOS: LaunchAgent (로그인 시 시작, 검증: 실기 맥 통과)
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
3. 하단 툴바 — **특수키 모드** (기본):
   - 줄1: **Esc · Tab · ` · - · \ · ' · / · Del · ⏎** — 기호키는 Shift 무장 시 버튼 라벨이 `~ _ | " ?` 로 바뀌어 표시됨
   - 줄2: **Fn · Shift · Ctrl · Win · Alt · Home · End · PgUp · PgDn** — 모디파이어 순서는 서버 OS의 물리 키보드를 따름 (Windows/Linux: Ctrl·Win·Alt, macOS: Ctrl·⌥·⌘)
     - **Fn** — 줄1·줄2가 F1~F12로 교체 (다시 누르면 복귀)
     - **Ctrl/Alt/Shift/Win** — 스티키 원샷: 켜면 빨간색, 다음 키 입력 1회에 조합 후 자동 해제. 소프트 키보드 문자와도 조합됨 (예: Ctrl 켜고 `c` 입력 = Ctrl+C). 한글 입력은 조합하지 않고 그대로 통과. Shift 무장 중에는 기호키 라벨이 Shift 기호로 프리뷰됨
   - 줄3: **▲▼◀▶** 방향키 + 우측 클러스터
4. 우측 클러스터 (항상 표시):
   - **⌶** — 텍스트 선택 모드 토글: 터미널을 터치 드래그로 선택, **전체/복사/붙여넣기/해제** 버튼
   - **⚙** — 설정 모드 토글: **A−/A+** 폰트 조절, **⟳ 재시작** (한 번 더 눌러 확인 시 새 셸 스폰)
   - **⌨** — 소프트 키보드 열기/닫기 (모바일 전용 — PC에서는 숨김)
   - **●** — 연결 상태 (녹색 = 연결됨, 적색 = 재연결 중)
5. 터미널 우측 하단 **☰** — 툴바 접기/펴기. **모바일**(Android/iOS/iPadOS)은 툴바가 기본 표시, **PC**는 기본 숨김(☰로 열기)

> **참고 — 세션 동작**: 브라우저 접속마다 **독립된 PowerShell 프로세스**가 스폰된다 (실측 검증: 동시 접속 2개 → 서로 다른 PID). 즉 여러 기기에서 동시에 붙어도 서로 간섭하지 않는다. 단, 연결이 끊기면 해당 프로세스는 종료되므로 **세션은 유지되지 않는다**.
>
> **참고 — Paste 버튼**: Clipboard API는 보안 컨텍스트(HTTPS 또는 localhost)에서만 동작한다. LAN IP로 HTTP 접속 시 Paste 버튼은 브라우저 종류와 무관하게 동작하지 않는다 — 이때는 터미널에 포커스 후 **소프트 키보드의 네이티브 붙여넣기**(길게 눌러 붙여넣기)를 사용하면 된다. Copy는 폴백(`execCommand`)으로 HTTP에서도 동작한다.
>
> **참고 — 홈 화면 바로가기 아이콘**: 파비콘과 홈 화면 아이콘은 모두 `index.html`에 data URI로 인라인되어 있다 (ttyd `-I`는 단일 파일만 서빙하므로 별도 아이콘 파일을 제공할 수 없음). **Android Chrome**은 data URI 아이콘을 지원하므로 '홈 화면에 추가' 시 전용 아이콘이 적용된다 — 아이콘은 투명 배경이라 런처가 자체 배경 플레이트(원형/스쿼클) 위에 원형 배지를 올린다. **iOS Safari**는 WebKit이 `apple-touch-icon`의 data URI를 무시하고 실제 URL만 허용하므로 홈 화면 추가 시 페이지 스크린샷이 아이콘이 된다 — HTTPS 여부와 무관한, ttyd 단일 파일 서빙의 구조적 한계다. iOS에서 깨끗한 아이콘이 필요하면 **단축어(Shortcuts)** 앱에서 'URL 열기' 바로가기를 만들고 커스텀 아이콘으로 루트의 `icon.png`를 지정하면 된다.

## 7. 추후 개발 예정

- [ ] **인증** — ttyd `-c user:pass` 기본 인증 연동 및 서비스 스크립트 옵션화
- [ ] **HTTPS** — `-S/-C/-K` SSL 옵션 지원 (공용망 노출 시 필수). 적용 시 Paste 버튼도 모든 브라우저에서 활성화됨 (iOS Safari는 시스템 확인 팝업 추가)
- [ ] **세션 유지** — 현재 연결이 끊기면 PowerShell 프로세스가 종료됨 (모바일 브라우저 백그라운드 전환 시 작업 유실). 재접속 시 세션 복원을 위한 tmux 유사 레이어 검토
- [ ] **쉘 선택 UI** — PowerShell / cmd / WSL 전환
- [ ] **PWA** — 홈 화면 설치, 전체 화면 모드

상세 실현성 판정·구현 경로·미결 결정사항: [docs/upgrade-plan.md](docs/upgrade-plan.md)

**구현 계획 없음**: 파일 전송(trzsz/ZMODEM), 커스텀 키 매크로

## 8. 라이선스 및 크레딧

- [ttyd](https://github.com/tsl0922/ttyd) — MIT License
- [xterm.js](https://github.com/xtermjs/xterm.js) — MIT License
- [NSSM](https://nssm.cc/) — Public Domain
