```
██╗     ██╗   ██╗███╗   ███╗ ██████╗ 
██║     ██║   ██║████╗ ████║██╔═══██╗
██║     ██║   ██║██╔████╔██║██║   ██║
██║     ██║   ██║██║╚██╔╝██║██║   ██║
███████╗╚██████╔╝██║ ╚═╝ ██║╚██████╔╝
╚══════╝ ╚═════╝ ╚═╝     ╚═╝ ╚═════╝ 
```

**Instant screen translation for macOS — powered by local AI.**

[![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue?logo=apple)](https://www.apple.com/macos)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-required-orange)](https://support.apple.com/en-us/HT211814)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)](https://swift.org)
[![License](https://img.shields.io/github/license/NewTurn2017/Lumo)](LICENSE)
[![Release](https://img.shields.io/github/v/release/NewTurn2017/Lumo)](https://github.com/NewTurn2017/Lumo/releases/latest)

---

Lumo는 화면의 어느 영역이든 캡처하거나 선택한 텍스트를 **클라우드 없이 로컬 AI로 즉시 번역**하는 macOS 메뉴바 앱입니다. 결과는 자동으로 클립보드에 복사됩니다.

## Demo

[![Lumo 튜토리얼](https://img.youtube.com/vi/qjlIY7GKStk/maxresdefault.jpg)](https://www.youtube.com/watch?v=qjlIY7GKStk)

## Features

- **⌘⇧1** — 화면 영역 드래그 캡처 → 번역
- **⌘C ⌘C** — 선택 텍스트 즉시 번역 (300ms 이내 두 번)
- **자동 언어 감지** — 한국어 감지 시 영어로, 그 외는 한국어로
- **스트리밍 출력** — 번역 결과를 토큰 단위로 실시간 표시
- **클립보드 자동 복사** — 번역 완료 즉시 복사
- **오프라인 동작** — 인터넷 연결 불필요, 모든 추론이 로컬에서 실행
- **자동 업데이트** — Sparkle 기반 백그라운드 업데이트

## Installation

### DMG 다운로드 (권장)

1. [최신 릴리즈](https://github.com/NewTurn2017/Lumo/releases/latest)에서 `Lumo-x.x.x.dmg` 다운로드
2. DMG를 열고 **Lumo.app**을 **Applications** 폴더로 드래그
3. 첫 실행 시 **시스템 환경설정 → 개인 정보 보호 → 화면 기록**에서 Lumo 허용
4. [Local AI Setup](#local-ai-setup) 섹션을 따라 기본 MLX 모델(~3 GB)을 사전 다운로드 — **앱이 모델을 자동으로 받지 않습니다.**

### AI 어시스턴트로 설치 (Claude Code / Codex)

아래 영문 프롬프트를 Claude Code · Codex · 기타 에이전트 CLI에 그대로 붙여넣으면 알아서 끝까지 설치해줍니다 — 최신 DMG 다운로드, `/Applications` 배치, Gatekeeper 검증, Python 3 확인, `huggingface-cli` 설치, 기본 모델 사전 다운로드, 서버 헬스체크까지.

<details>
<summary>📋 English install prompt (click to expand → copy-paste into your AI assistant)</summary>

```
Install Lumo, a macOS menu-bar app that translates any screen region or
selected text using a local MLX model. Target environment: macOS 13+ on
Apple Silicon. Everything runs locally — no cloud calls.

Execute these steps in order. Verify each step before moving on, and stop
with a clear error message if anything fails instead of silently retrying.

1. Resolve the latest release version:
     VERSION=$(curl -fsSL https://api.github.com/repos/NewTurn2017/Lumo/releases/latest \
       | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p')
   Confirm VERSION is non-empty before proceeding.

2. Download the DMG:
     curl -L -o "/tmp/Lumo-${VERSION}.dmg" \
       "https://github.com/NewTurn2017/Lumo/releases/download/v${VERSION}/Lumo-${VERSION}.dmg"

3. Install into /Applications (replacing any prior copy):
     hdiutil attach "/tmp/Lumo-${VERSION}.dmg" -nobrowse -quiet -mountpoint /tmp/LumoMount
     rm -rf /Applications/Lumo.app
     ditto /tmp/LumoMount/Lumo.app /Applications/Lumo.app
     hdiutil detach /tmp/LumoMount -quiet
     rm "/tmp/Lumo-${VERSION}.dmg"

4. Verify Gatekeeper accepts the app. Must print "accepted" and
   "Notarized Developer ID":
     spctl -a -vv /Applications/Lumo.app

5. Ensure Python 3 is available. Lumo searches these paths in order:
     /opt/homebrew/bin/python3, /usr/local/bin/python3, /usr/bin/python3
   If none exist, install Homebrew then Python:
     /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
     brew install python@3.12

6. Install the Hugging Face CLI in an isolated environment (do not touch
   system Python):
     brew install pipx || python3 -m pip install --user pipx
     pipx ensurepath
     pipx install "huggingface_hub[cli]"

7. Pre-download the default model (~3 GB). Lumo intentionally does NOT
   download the model itself — you must do this before first launch or
   the app will show "모델 없음" and refuse to start:
     huggingface-cli download mlx-community/gemma-4-e4b-it-4bit
   Files land in ~/.cache/huggingface/hub/models--mlx-community--gemma-4-e4b-it-4bit/

8. Launch Lumo:
     open -a Lumo

9. Tell the user: on the first screen capture, macOS will request Screen
   & System Audio Recording permission. Walk them through:
     System Settings → Privacy & Security → Screen & System Audio Recording
     → toggle "Lumo" ON → relaunch Lumo from the menu bar icon.

10. Verify the local MLX server is healthy (may take 10-30 s to warm up
    on first launch):
     curl -fsS http://127.0.0.1:8080/v1/models
    Expected: JSON containing "mlx-community/gemma-4-e4b-it-4bit".
    If it fails, surface the last 30 lines of the server log:
     tail -n 30 ~/Library/Logs/Lumo/mlx-server.log

11. Report a short final summary:
    - Installed Lumo version and bundle path
    - Model cache size on disk (du -sh on the model folder)
    - Server health check result
    - Any manual permission step the user still needs to click

Defaults — do not change unless the user explicitly asks:
- Model:  mlx-community/gemma-4-e4b-it-4bit   (switchable in-app via ⌘,)
- Venv:   ~/.local/share/Lumo/mlx-venv         (auto-recreated on launch if missing)
- Server: http://127.0.0.1:8080

If Python 3 is missing and you cannot install Homebrew (no sudo, no
network, restricted host), stop and ask how to proceed rather than
building Python from source.
```

</details>

**시스템 요구사항**

| 항목 | 최소 사양 |
|------|----------|
| macOS | 13.0 Ventura 이상 |
| 칩 | Apple Silicon (M1 이상) |
| 저장 공간 | 30MB + MLX 모델 용량 |

## Usage

### 화면 영역 번역

```
⌘ + ⇧ + 1
```

화면이 어두워지면 번역할 영역을 드래그합니다. ESC로 취소.

### 선택 텍스트 번역

```
⌘C → ⌘C  (300ms 이내)
```

텍스트를 선택하고 ⌘C를 두 번 빠르게 누릅니다.  
한국어 텍스트를 선택하면 자동으로 영어로 번역됩니다.

### 결과 팝업

- 번역 결과가 화면 우하단에 스트리밍으로 표시됩니다
- 완료 즉시 클립보드에 복사됩니다
- 5초 후 자동으로 사라집니다 (마우스 오버 시 유지)

## Local AI Setup

Lumo는 로컬 MLX 서버를 직접 띄웁니다. 앱은 첫 실행 시 `~/.local/share/Lumo/mlx-venv`에 Python venv를 만들고 `mlx-lm`을 자동으로 설치하지만, **모델 파일 자체는 의도적으로 자동 다운로드하지 않습니다** — 수 GB 트래픽을 사용자 동의 없이 쓰지 않기 위함입니다. 첫 실행 **전에** 직접 받아주세요:

```bash
# huggingface-cli 설치 (pipx 권장, 시스템 Python을 건드리지 않음)
brew install pipx || python3 -m pip install --user pipx
pipx ensurepath
pipx install "huggingface_hub[cli]"

# 기본 모델 다운로드 (~3 GB)
huggingface-cli download mlx-community/gemma-4-e4b-it-4bit
```

다운로드된 모델은 `~/.cache/huggingface/hub/models--mlx-community--gemma-4-e4b-it-4bit/`에 저장되고, Lumo가 자동으로 감지해 `mlx_lm.server`를 `127.0.0.1:8080`에 기동합니다. 기동 로그는 `~/Library/Logs/Lumo/mlx-server.log` 에서 확인할 수 있습니다.

다른 모델을 쓰려면 앱 설정(⌘,)에서 모델 ID를 바꾸고, 새 모델도 같은 방식으로 `huggingface-cli download <model-id>` 로 사전에 받아 두세요.

## Auto Update

Lumo는 **Sparkle**을 통해 새 버전을 자동으로 확인합니다.  
메뉴바 아이콘 → **업데이트 확인...** 으로 수동 확인도 가능합니다.

## Building from Source

```bash
# 의존성
brew install xcodegen

# 빌드
git clone https://github.com/NewTurn2017/Lumo.git
cd Lumo
xcodegen generate
open Lumo.xcodeproj
```

Xcode 16+, Swift 5.9, macOS 13 SDK 필요.

## License

MIT © 2026 NewTurn2017
