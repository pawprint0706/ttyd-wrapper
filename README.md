# ttyd-wrapper

**모바일 브라우저에서 내 PC 터미널을 쓰기 위한 [ttyd](https://github.com/tsl0922/ttyd) 래퍼** — 기본 ttyd 웹 페이지에서는 불가능한 **폰트 크기 조절**과 **특수키 입력**(Esc, Tab, 방향키, Ctrl 조합 등)을 모바일 친화적인 웹 UI로 제공한다.

Windows / Linux / macOS 지원 (전 플랫폼 실측 검증 완료).

## 1. 프로젝트 개요

ttyd는 터미널을 웹 브라우저로 중계해 주는 도구지만, 기본 웹 페이지는 모바일에서 쓰기 어렵다.

- 작은 화면인데 **폰트 크기를 조절할 수 없다**
- 모바일 소프트 키보드에 없는 키 — **Esc, Tab, 방향키, Ctrl 조합 등을 입력할 수 없다**

이 프로젝트는 ttyd의 커스텀 페이지 옵션(`-I`)에 자체 제작 **단일 HTML 파일**(`public/index.html`)을 물려 위 문제를 해결한다. 별도 웹 서버·빌드 과정·외부 CDN 없이 ttyd 혼자 모든 것을 서빙하며, OS별 서비스 등록 스크립트가 동봉되어 부팅(로그인) 시 자동 시작된다.

- **호스트(터미널을 제공하는 PC)**: Windows, Linux, macOS
- **클라이언트(접속하는 기기)**: 모던 브라우저 — Chrome 108+ / Safari 15.4+ / Firefox 101+

## 2. 설치 / 삭제

저장소를 받아 원하는 위치에 두면 준비 끝이다. 설치 후 저장소 폴더를 옮기면 서비스가 참조하는 경로가 깨지므로 재설치해야 한다.

설치가 끝나면 같은 네트워크의 브라우저에서 접속한다 (기본 포트 `33322`):

```
http://<호스트 PC의 IP>:33322/        ← HTTPS를 켰다면 https://
```

### Windows

ttyd·NSSM 바이너리가 동봉되어 있어 **사전 설치할 것이 없다**. 터미널로 PowerShell을 중계한다.

| 작업 | 명령 |
|------|------|
| 서비스 설치 | `bin\install-service.bat` |
| 서비스 삭제 | `bin\uninstall-service.bat` |
| 수동 실행 (서비스 없이) | `bin\ttyd.bat` |

- 설치 스크립트가 관리자 승격(UAC), 방화벽 규칙(TCP 33322) 등록, 부팅 자동 시작·크래시 자동 재시작 설정까지 처리한다.
- 설치 중 **HTTPS / 로그인** 사용 여부를 물어본다 (Enter만 치면 모두 끔).
- 반드시 **본인 데스크톱 세션에서 실행**한다 — 웹 터미널 안에서 실행하면 스크립트가 차단한다.
- 실행될 명령 미리보기: `bin\install-service.bat /dry`
- 포트·셸 등 변경: `bin\install-service.bat` 상단 Configuration 블록 수정 후 재설치.

### Linux

사전 설치: `sudo apt install ttyd` — 세션 유지 기능을 쓰려면 `tmux`도 함께.

| 작업 | 명령 |
|------|------|
| 서비스 설치 | `./linux/install-service.sh` |
| 서비스 삭제 | `./linux/uninstall-service.sh` |
| 수동 실행 (서비스 없이) | `./linux/ttyd.sh` |

- systemd **사용자 유닛**으로 설치된다 — 서비스에 root 권한이 필요 없고, `loginctl enable-linger`로 부팅 시 자동 시작한다.
- 설치 중 **세션 유지(tmux) / HTTPS / 로그인** 사용 여부를 물어본다. 선택한 기능에 필요한 패키지가 없으면 설치를 시작하지 않고 설치 명령을 안내한 뒤 종료한다.
- 실행될 내용 미리보기: `./linux/install-service.sh --dry`

### macOS

사전 설치: `brew install ttyd` — 세션 유지 기능을 쓰려면 `tmux`도 함께.

| 작업 | 명령 |
|------|------|
| 서비스 설치 | `./macos/install-service.sh` |
| 서비스 삭제 | `./macos/uninstall-service.sh` |
| 수동 실행 (서비스 없이) | `./macos/ttyd.sh` |

- **LaunchAgent**로 등록되어 로그인 시 자동 시작, 크래시 시 자동 재시작한다.
- 설치 질문과 미리보기(`--dry`)는 Linux와 동일하다.
- 첫 접속 때 macOS 방화벽 허용 팝업이 뜨면 '허용'을 누른다.

### 설정 변경 (Linux / macOS 공통)

설치·수동 실행 스크립트는 환경변수로 오버라이드한다. 예: `TTYD_PORT=8080 ./linux/install-service.sh`

| 환경변수 | 의미 |
|----------|------|
| `TTYD_PORT` | 포트 (기본 33322) |
| `TTYD_CRED=user:pass` | 로그인(basic auth) 활성화 |
| `TTYD_SSL_CERT` / `TTYD_SSL_KEY` | HTTPS 인증서·키 경로 |
| `TTYD_SESSION` | tmux 세션 이름 (기본 `ttyd`) |
| `TTYD_TMUX=0` | 세션 유지 끄기 (일반 로그인 셸 사용) |

### HTTPS 인증서 준비 — 무료 DDNS + 무료 인증서

> **보안 주의**: 로그인(basic auth)의 자격증명은 사실상 평문으로 전송된다 — **반드시 HTTPS와 함께** 사용한다.

인증서는 고정 IP나 유료 도메인 없이도 무료로 준비할 수 있다. HTTPS를 켜면 통신 암호화 외에 붙여넣기 버튼과 PWA 홈 화면 설치도 활성화된다.

1. **무료 DDNS로 도메인 확보** — [DuckDNS](https://www.duckdns.org/), [No-IP](https://www.noip.com/) 등에서 무료 서브도메인(예: `myhost.duckdns.org`)을 만들어 내 공인 IP에 연결한다. 외부에서 접속하려면 공유기 포트포워딩(기본 33322)도 열어 둔다.
2. **무료 인증서 발급** — [acme.sh](https://github.com/acmesh-official/acme.sh)(또는 certbot)로 위 도메인에 대해 Let's Encrypt 인증서를 발급받는다. 순수 IP 주소로는 발급되지 않으므로 도메인이 필요하며, **DNS-01 챌린지**를 쓰면 포트를 열지 않고도 발급할 수 있다(DuckDNS 등 주요 DDNS가 API를 지원).
3. **설치 시 지정** — 발급된 `fullchain.pem` / `privkey.pem` 경로를 설치 중 HTTPS 질문(또는 환경변수 `TTYD_SSL_CERT`/`TTYD_SSL_KEY`, Windows는 `SSL_CERT`/`SSL_KEY`)에 넣고 `https://<도메인>:33322/`로 접속한다. 인증서가 자동 갱신되면 서비스 재시작으로 반영한다.

## 3. 프로젝트 기능

| 기능 | 설명 |
|------|------|
| 특수키 입력 | Esc · Tab · 방향키 · Home/End/PgUp/PgDn · Del 등 + Fn 레이어(F1~F12) — 모바일 키보드에 없는 키를 화면 하단 툴바 버튼으로 입력 |
| 키 조합 | Ctrl / Alt / Shift / Win 스티키 토글 — 켜고 다음 입력 1회에 자동 조합 (예: Ctrl 켜고 `c` = Ctrl+C) |
| 폰트 크기 조절 | 설정 모드에서 A− / A+ 버튼으로 10~32px 실시간 조절 |
| 텍스트 선택 | 터치 드래그로 선택 + 전체선택 / 복사 / 붙여넣기 버튼 |
| 세션 유지 | **Linux/macOS**: tmux 세션 — 연결이 끊겨도 작업이 유지되고 재접속 시 복원, 여러 기기가 같은 세션을 미러링. **Windows**: 미지원 (접속마다 독립 PowerShell) |
| 보안 옵션 | 로그인(basic auth) + HTTPS — 설치 시 선택 |
| 자동 재연결 | 끊기면 지수 백오프(1~10초)로 재접속, 연결 상태 표시등(●) 제공 |
| 오프라인 완결 | 모든 리소스가 단일 HTML에 인라인 — 외부 CDN 의존 0, 망분리 환경에서도 동작 |
| 서비스 운영 | 부팅(로그인) 자동 시작, 크래시 자동 재시작, 로그 로테이션(1MB) |
| 홈 화면 추가 | PWA 매니페스트·아이콘 내장 — Android Chrome '홈 화면에 추가' 시 전용 아이콘 적용 |

### 기본 조작법

- **일반 입력** — 터미널 영역을 탭하거나 소프트 키보드 보이기/숨기기(**⌨**) 버튼을 누르면 소프트 키보드가 열린다. 키보드에 없는 키만 하단 툴바로 입력하면 된다.
- **툴바 열기/접기** — 터미널 우측 하단 **☰** 버튼. 모바일은 기본 표시, PC는 기본 숨김이다.
- **특수키 입력** — 툴바의 키를 그대로 누른다. **Fn**을 켜면 키들이 F1~F12로 바뀐다.
- **조합키 입력** — **Ctrl / Alt / Shift / Win**은 한 번 누르면 빨갛게 켜지고(스티키), 다음 입력 1회에 조합된 뒤 자동으로 풀린다. 예: **Ctrl**을 켜고 `c`를 입력하면 Ctrl+C.
- **우측 고정 버튼** — 툴바 어느 모드에서나 표시된다:
  - **⌶** 텍스트 선택 모드 — 드래그로 선택 후 전체선택/복사/붙여넣기 (붙여넣기 버튼은 브라우저 정책상 HTTPS 접속에서만 동작)
  - **⚙** 설정 모드 — **A−/A+** 폰트 크기 조절, **⟳** 터미널 재시작
  - **⌨** 소프트 키보드 보이기/숨기기 — 모바일 전용 (PC에서는 표시되지 않음)
  - **●** 연결 상태 — 녹색=연결됨, 적색=재연결 중

## 4. 프로젝트 구조

```
ttyd-wrapper/
├── public/
│   ├── index.html             # 커스텀 웹 터미널 UI — 단일 파일, 모든 리소스 인라인
│   └── vendor/                # xterm.js 원본 (참조용 — 런타임에는 index.html 내 인라인 사본 사용)
├── bin/                       # ── Windows ──
│   ├── ttyd.exe / nssm.exe    # 동봉 바이너리 (ttyd, 서비스 매니저)
│   ├── install-service.bat    # 서비스 설치 (UAC 승격·방화벽·자동 시작)
│   ├── uninstall-service.bat  # 서비스 삭제
│   ├── service-launcher.ps1   # 서비스 기동 시 사용자 PATH 재구성 런처
│   └── ttyd.bat               # 수동 실행
├── linux/                     # ── Linux (systemd 사용자 유닛) ──
│   ├── install-service.sh / uninstall-service.sh
│   ├── ttyd-wrapper.service   # 유닛 템플릿
│   └── ttyd.sh                # 수동 실행
├── macos/                     # ── macOS (LaunchAgent) ──
│   ├── install-service.sh / uninstall-service.sh
│   ├── ttyd-wrapper.plist     # LaunchAgent 템플릿
│   └── ttyd.sh                # 수동 실행
├── docs/                      # ── 상세 문서 ──
│   ├── README-legacy.md       # 구 README (상세 사용법·기술 스펙 아카이브)
│   ├── feasibility-review.md  # 기술 검토 · ttyd WebSocket 프로토콜 분석
│   ├── upgrade-plan.md        # 기능 확장 계획 · 결정 기록 (인증·HTTPS·세션·PWA)
│   ├── porting-analysis.md    # Linux/macOS 포팅 분석
│   └── toolbar-redesign.md    # 툴바 UI 설계
├── logs/                      # 서비스 로그 (1MB 로테이션)
├── icon.png                   # 앱 아이콘 원본 (파비콘·홈 화면 아이콘으로 인라인 임베딩)
└── LICENSE                    # 자체 코드 라이선스 (MIT)
```

## 5. 라이선스

이 저장소의 자체 코드(웹 UI, 설치 스크립트)는 [MIT 라이선스](LICENSE)를 따른다.

또한 아래 외부 소프트웨어를 사용하며, 각 구성 요소는 해당 라이선스를 따른다.

| 구성 요소 | 용도 / 포함 형태 | 라이선스 |
|-----------|------------------|----------|
| [ttyd](https://github.com/tsl0922/ttyd) v1.7.7 | 터미널 웹 중계 서버. Windows용 바이너리 동봉(`bin/ttyd.exe`), Linux/macOS는 패키지로 별도 설치 | [MIT](https://github.com/tsl0922/ttyd/blob/main/LICENSE) |
| [xterm.js](https://github.com/xtermjs/xterm.js) 5.3.0 (+ fit · web-links addon) | 브라우저 터미널 렌더링. `public/index.html`에 인라인 포함, 원본은 `public/vendor/` | [MIT](https://github.com/xtermjs/xterm.js/blob/master/LICENSE) |
| [NSSM](https://nssm.cc/) 2.24 | Windows 서비스 등록. 바이너리 동봉(`bin/nssm.exe`) | Public Domain |
| [tmux](https://github.com/tmux/tmux) | Linux/macOS 세션 유지. 동봉하지 않으며 사용자가 패키지로 설치 | [ISC](https://github.com/tmux/tmux/blob/master/COPYING) |
