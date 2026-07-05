# ttyd-wrapper

[한국어](README.md) | **English**

**A [ttyd](https://github.com/tsl0922/ttyd) wrapper for using your PC's terminal from a mobile browser** — adds what the stock ttyd web page can't do: **font size control** and **special key input** (Esc, Tab, arrow keys, Ctrl combos, etc.) through a mobile-friendly web UI.

Supports Windows / Linux / macOS (verified on real hardware on every platform).

## 1. Overview

ttyd relays a terminal to a web browser, but its stock web page is hard to use on mobile.

- The screen is small, yet **the font size can't be adjusted**
- Keys missing from mobile soft keyboards — **Esc, Tab, arrow keys, Ctrl combos, etc. — can't be typed**

This project solves both by feeding a self-made **single HTML file** (`public/index.html`) to ttyd's custom page option (`-I`). There is no separate web server, build step, or external CDN — ttyd alone serves everything, and bundled per-OS service scripts make it start automatically at boot (login).

- **Host (the PC serving the terminal)**: Windows, Linux, macOS
- **Client (the connecting device)**: modern browsers — Chrome 108+ / Safari 15.4+ / Firefox 101+

## 2. Install / Uninstall

Download the repository and put it anywhere you like — that's all the preparation. If you move the repository folder after installing, the paths the service references break, so reinstall.

Once installed, connect from a browser on the same network (default port `33322`):

```
http://<host PC's IP>:33322/        ← use https:// if you enabled HTTPS
```

### Windows

The ttyd and NSSM binaries are bundled — **nothing to preinstall**. PowerShell is served as the terminal.

| Task | Command |
|------|---------|
| Install service | `bin\install-service.bat` |
| Uninstall service | `bin\uninstall-service.bat` |
| Run manually (without the service) | `bin\ttyd.bat` |

- The install script handles admin elevation (UAC), firewall rule registration (TCP 33322), auto start at boot, and auto restart on crash.
- During install it asks whether to enable **HTTPS / login** (just press Enter to leave both off).
- Be sure to **run it from your own desktop session** — the script blocks itself if run inside the web terminal.
- Preview the commands to be executed: `bin\install-service.bat /dry`
- To change the port, shell, etc.: edit the Configuration block at the top of `bin\install-service.bat` and reinstall.

### Linux

Prerequisite: `sudo apt install ttyd` — add `tmux` if you want session persistence.

| Task | Command |
|------|---------|
| Install service | `./linux/install-service.sh` |
| Uninstall service | `./linux/uninstall-service.sh` |
| Run manually (without the service) | `./linux/ttyd.sh` |

- Installed as a systemd **user unit** — the service needs no root privileges, and `loginctl enable-linger` makes it start at boot.
- During install it asks whether to enable **session persistence (tmux) / HTTPS / login**. If a package required by a selected feature is missing, the installer stops before making any changes and prints the install command instead.
- Preview what will be done: `./linux/install-service.sh --dry`

### macOS

Prerequisite: `brew install ttyd` — add `tmux` if you want session persistence.

| Task | Command |
|------|---------|
| Install service | `./macos/install-service.sh` |
| Uninstall service | `./macos/uninstall-service.sh` |
| Run manually (without the service) | `./macos/ttyd.sh` |

- Registered as a **LaunchAgent** — starts automatically at login and restarts on crash.
- The install questions and preview (`--dry`) are the same as on Linux.
- If the macOS firewall popup appears on first connection, click 'Allow'.

### Changing settings (Linux / macOS)

The install and manual-run scripts are overridden via environment variables. Example: `TTYD_PORT=8080 ./linux/install-service.sh`

| Variable | Meaning |
|----------|---------|
| `TTYD_PORT` | Port (default 33322) |
| `TTYD_CRED=user:pass` | Enable login (basic auth) |
| `TTYD_SSL_CERT` / `TTYD_SSL_KEY` | HTTPS certificate / key paths |
| `TTYD_SESSION` | tmux session name (default `ttyd`) |
| `TTYD_TMUX=0` | Disable session persistence (use a plain login shell) |

### Getting an HTTPS certificate — free DDNS + free certificate

> **Security note**: basic-auth credentials are effectively transmitted in plaintext — **always use login together with HTTPS**.

A certificate can be obtained for free, with no static IP or paid domain. Besides encrypting traffic, enabling HTTPS also unlocks the paste button and PWA home-screen install.

1. **Get a domain via free DDNS** — create a free subdomain (e.g. `myhost.duckdns.org`) at [DuckDNS](https://www.duckdns.org/), [No-IP](https://www.noip.com/), etc., and point it at your public IP. To connect from outside your network, also set up port forwarding on your router (default 33322).
2. **Issue a free certificate** — use [acme.sh](https://github.com/acmesh-official/acme.sh) (or certbot) to issue a Let's Encrypt certificate for that domain. Certificates are not issued for bare IP addresses, so a domain is required; with the **DNS-01 challenge** you can issue one without opening any port (major DDNS providers such as DuckDNS support the required API).
3. **Point the installer at it** — enter the issued `fullchain.pem` / `privkey.pem` paths at the HTTPS prompt during install (or via the env vars `TTYD_SSL_CERT`/`TTYD_SSL_KEY`; on Windows `SSL_CERT`/`SSL_KEY`) and connect to `https://<domain>:33322/`. When the certificate auto-renews, restart the service to pick it up.

## 3. Features

| Feature | Description |
|---------|-------------|
| Special keys | Esc · Tab · arrows · Home/End/PgUp/PgDn · Del, plus an Fn layer (F1–F12) — type keys missing from mobile keyboards via the bottom toolbar |
| Key combos | Ctrl / Alt / Shift / Win sticky toggles — turn one on and it combines with the next single input (e.g. Ctrl on + `c` = Ctrl+C) |
| Font size | A− / A+ buttons in settings mode — live adjustment from 10 to 32 px |
| Text selection | Touch-drag selection + Select All / Copy / Paste buttons |
| Session persistence | **Linux/macOS**: tmux session — work survives disconnects and is restored on reconnect; multiple devices mirror the same session. **Windows**: not supported (each connection gets an independent PowerShell) |
| Security options | Login (basic auth) + HTTPS — chosen at install time |
| Auto reconnect | Reconnects with exponential backoff (1–10 s) after a drop; connection status dot (●) |
| Fully offline | Every resource is inlined in a single HTML file — zero external CDN dependencies, works on air-gapped networks |
| Service operation | Auto start at boot (login), auto restart on crash, log rotation (1 MB) |
| Add to home screen | Built-in PWA manifest and icon — Android Chrome 'Add to Home screen' installs with a dedicated icon |

### Basic usage

- **Regular typing** — tap the terminal area or press the soft-keyboard show/hide (**⌨**) button to open the soft keyboard. Use the bottom toolbar only for keys the keyboard lacks.
- **Open/collapse the toolbar** — the **☰** button at the bottom right of the terminal. Shown by default on mobile, hidden by default on PC.
- **Special keys** — press toolbar keys as they are. Turn on **Fn** to switch the keys to F1–F12.
- **Key combos** — **Ctrl / Alt / Shift / Win** light up red once pressed (sticky), combine with the next single input, then release automatically. Example: turn on **Ctrl** and type `c` for Ctrl+C.
- **Fixed right-side buttons** — visible in every toolbar mode:
  - **⌶** text-selection mode — drag to select, then Select All / Copy / Paste (the paste button works only over HTTPS due to browser policy)
  - **⚙** settings mode — **A−/A+** font size, **⟳** restart terminal
  - **⌨** show/hide soft keyboard — mobile only (not shown on PC)
  - **●** connection status — green = connected, red = reconnecting

## 4. Project structure

```
ttyd-wrapper/
├── public/
│   ├── index.html             # Custom web terminal UI — single file, all resources inlined
│   └── vendor/                # Pristine xterm.js (reference only — runtime uses the inlined copy in index.html)
├── bin/                       # ── Windows ──
│   ├── ttyd.exe / nssm.exe    # Bundled binaries (ttyd, service manager)
│   ├── install-service.bat    # Service install (UAC elevation · firewall · auto start)
│   ├── uninstall-service.bat  # Service uninstall
│   ├── service-launcher.ps1   # Launcher that rebuilds the user PATH at service start
│   └── ttyd.bat               # Manual run
├── linux/                     # ── Linux (systemd user unit) ──
│   ├── install-service.sh / uninstall-service.sh
│   ├── ttyd-wrapper.service   # Unit template
│   └── ttyd.sh                # Manual run
├── macos/                     # ── macOS (LaunchAgent) ──
│   ├── install-service.sh / uninstall-service.sh
│   ├── ttyd-wrapper.plist     # LaunchAgent template
│   └── ttyd.sh                # Manual run
├── docs/                      # ── Detailed documentation (Korean) ──
│   ├── README-legacy.md       # Old README (archive of detailed usage & tech specs)
│   ├── feasibility-review.md  # Technical review · ttyd WebSocket protocol analysis
│   ├── upgrade-plan.md        # Feature roadmap · decision log (auth · HTTPS · sessions · PWA)
│   ├── porting-analysis.md    # Linux/macOS porting analysis
│   └── toolbar-redesign.md    # Toolbar UI design
├── logs/                      # Service logs (1 MB rotation)
├── icon.png                   # App icon source (inlined as favicon & home-screen icon)
└── LICENSE                    # License for this project's own code (MIT)
```

## 5. License

The code original to this repository (web UI, install scripts) is licensed under the [MIT License](LICENSE).

It also uses the following third-party software; each component is governed by its own license.

| Component | Purpose / How included | License |
|-----------|------------------------|---------|
| [ttyd](https://github.com/tsl0922/ttyd) v1.7.7 | Terminal-to-web relay server. Windows binary bundled (`bin/ttyd.exe`); installed separately via package manager on Linux/macOS | [MIT](https://github.com/tsl0922/ttyd/blob/main/LICENSE) |
| [xterm.js](https://github.com/xtermjs/xterm.js) 5.3.0 (+ fit · web-links addons) | Terminal rendering in the browser. Inlined in `public/index.html`; pristine copy in `public/vendor/` | [MIT](https://github.com/xtermjs/xterm.js/blob/master/LICENSE) |
| [NSSM](https://nssm.cc/) 2.24 | Windows service registration. Binary bundled (`bin/nssm.exe`) | Public Domain |
| [tmux](https://github.com/tmux/tmux) | Session persistence on Linux/macOS. Not bundled; installed by the user via package manager | [ISC](https://github.com/tmux/tmux/blob/master/COPYING) |
