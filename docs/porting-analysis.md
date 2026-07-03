# macOS / Linux 포팅 분석

> 전제: Linux는 systemd 기반 배포판, macOS는 로그인 후 기동(LaunchAgent)을 대상으로 한다.

## 1. 결론

**동일한 경험 제공 가능하며, 구현은 Windows판보다 단순하다.**

이 프로젝트의 복잡도 대부분(NSSM, SYSTEM 계정, 레지스트리 PATH 재구성, UAC 승격)은 **Windows 특유의 문제를 우회하는 코드**다. macOS/Linux에서는 그 문제 자체가 존재하지 않는다. ttyd는 원래 유닉스 태생 도구로, Windows 쪽이 오히려 포팅판이다.

## 2. 컴포넌트별 포팅 작업

| 컴포넌트 | 포팅 작업 | 비용 |
|----------|----------|------|
| `public/index.html` (302KB) | **수정 0** — 순수 프론트엔드. ttyd 프로토콜·xterm.js·툴바·폰트 저장 전부 서버 OS 무관 | 없음 |
| ttyd 바이너리 | `brew install ttyd` (mac) / `apt install ttyd` 또는 GitHub 릴리즈 (linux). 바이너리 동봉 불필요 — 멀티아치(x64/arm64) 배포 부담 소멸 | 없음 |
| 셸 | `powershell.exe` → `zsh -l`(mac) / `bash -l`(linux). 로그인 셸로 띄우면 `.zprofile`/`.bashrc`가 로드되어 사용자 PATH가 자연히 잡힘 | 인자 1개 |
| `ttyd.bat` | 3줄짜리 `ttyd.sh` | 10분 |
| 서비스 등록 | §3 참조 | 플랫폼당 반나절 |
| `service-launcher.ps1` | **삭제** — 존재 이유가 사라짐 (§3) | 음수 비용 |

## 3. 서비스 계층 — 복잡도가 사라지는 지점

| Windows에서 했던 일 | Linux (systemd) | macOS (launchd, LaunchAgent) |
|--------------------|-----------------|------------------------------|
| NSSM으로 서비스화 | 유닛 파일 ~15줄 | plist ~30줄 |
| SYSTEM 계정 → 사용자 PATH를 레지스트리에서 재구성하는 런처 | **불필요** — `User=<user>` 지정으로 서비스가 사용자 본인으로 실행 | **불필요** — LaunchAgent는 원래 사용자 권한으로 실행 |
| NTUSER.DAT 하이브 로드 (로그온 전 대응) | `loginctl enable-linger` 한 줄 | 해당 없음 (로그인 후 기동) |
| UAC 자동 승격 | user 서비스면 sudo조차 불필요 | 불필요 |
| netsh 방화벽 규칙 | `ufw allow 33322` 한 줄 (호스트 방화벽 없는 환경 다수) | 최초 접속 시 시스템 프롬프트 1회 |
| git `safe.directory` 문제 | **발생 안 함** — 서비스 실행자 = 폴더 소유자 | 동일 |
| 크래시 재시작 / 로그 로테이션 | `Restart=on-failure` + journald 내장 | `KeepAlive` + 로그 파일 지정 |

Windows판의 `install-service.bat`(약 120줄) + `service-launcher.ps1`(약 60줄)이 **유닛/plist 파일 하나 + 설치 셸 스크립트 ~50줄**로 줄어든다.

## 4. 경험 차이 (사용자 관점)

| 항목 | 동일 여부 |
|------|----------|
| 모바일 UI (툴바, 폰트, 특수키, Ctrl 토글, 키보드 회피) | **100% 동일** — 같은 HTML 파일 |
| 클립보드 제약 (HTTP에서 Paste 버튼 불가) | 동일 — 브라우저 보안 컨텍스트 제약이지 서버 문제가 아님 |
| 세션 비영속 (연결 끊기면 프로세스 종료) | 동일. 단 유닉스에선 `tmux`가 기본 제공되어 세션 유지 로드맵이 훨씬 쉬워짐 |
| 터미널 품질 | **개선** — ConPTY 대신 네이티브 pty (이스케이프/색상 처리 우수) |
| 폰트 | CSS 스택에 Menlo(mac)/DejaVu Sans Mono(linux) 추가 권장 — 1줄. 미적용 시에도 `monospace` 폴백으로 동작 |

## 5. 구현 비용 총계

| 작업 | 비용 |
|------|------|
| Linux: systemd 유닛 + install/uninstall.sh | 0.5일 |
| macOS: LaunchAgent plist + install/uninstall.sh | 0.5일 |
| 실기기 테스트 (양 플랫폼 × 모바일 접속) | 0.5일 |
| **합계** | **약 1.5일** |

## 6. 예상 산출물 구성

OS별 스크립트는 `bin/`(Windows 전용, 기존 그대로)과 **형제 경로인 `linux/`, `macos/` 폴더**에 분리한다. 리눅스/맥은 ttyd를 패키지로 설치하고 서비스 매니저(systemd/launchd)가 OS 내장이므로, 산출물은 순수 스크립트뿐이다.

```
ttyd-wrapper/
├── bin/                       # Windows 전용 (변경 없음)
├── linux/
│   ├── ttyd.sh                # 수동 실행 (bash -l 릴레이)
│   ├── install-service.sh     # systemd 유닛 설치 + enable-linger + ufw
│   ├── uninstall-service.sh   # 유닛 제거 + 방화벽 규칙 삭제
│   └── ttyd-wrapper.service   # systemd 유닛 템플릿 (~15줄)
├── macos/
│   ├── ttyd.sh                # 수동 실행 (zsh -l 릴레이)
│   ├── install-service.sh     # LaunchAgent 등록 + launchctl load
│   ├── uninstall-service.sh   # launchctl unload + plist 삭제
│   └── ttyd-wrapper.plist     # LaunchAgent 템플릿 (~30줄)
├── public/                    # 공통 (수정 없음)
└── docs/
```

**Windows 산출물과의 대응:**

| 역할 | Windows (`bin/`) | Linux (`linux/`) | macOS (`macos/`) |
|------|------------------|-------------------|-------------------|
| 수동 실행 | `ttyd.bat` | `ttyd.sh` | `ttyd.sh` |
| 서비스 설치 | `install-service.bat` | `install-service.sh` | `install-service.sh` |
| 서비스 제거 | `uninstall-service.bat` | `uninstall-service.sh` | `uninstall-service.sh` |
| 서비스 정의 | (NSSM 레지스트리 내장) | `ttyd-wrapper.service` | `ttyd-wrapper.plist` |
| 환경 재구성 런처 | `service-launcher.ps1` | 없음 | 없음 |
| 서비스 매니저 | `nssm.exe` 동봉 | systemd 내장 | launchd 내장 |
| ttyd 바이너리 | `ttyd.exe` 동봉 | 미동봉 (`apt`/릴리즈) | 미동봉 (`brew`) |

> 레포 내 파일명은 접미어 없이 폴더로 구분하며, 설치 시 시스템 규약 위치·명칭으로 복사된다 — systemd: `~/.config/systemd/user/ttyd-wrapper.service`, launchd: `~/Library/LaunchAgents/com.pawprint0706.ttyd-wrapper.plist` (역도메인 규약).

## 7. 요약

코어 자산(`public/index.html`)이 이미 OS 중립이므로 포팅의 본질은 **서비스 래핑 재작성**뿐이며, 그마저 Windows판보다 얇다. 동일한 모바일 경험을 보장하면서 총 1.5일 규모로 완료 가능하다.
