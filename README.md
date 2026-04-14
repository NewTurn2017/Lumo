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

Lumo는 로컬 MLX 서버를 사용합니다. 앱 설정(⌘,)에서 모델을 선택하면 자동으로 설치됩니다.

**수동 설정:**

```bash
# MLX LM 설치
pip install mlx-lm

# 서버 실행 (앱이 자동으로 관리)
mlx_lm.server --model mlx-community/gemma-4-e4b-it-4bit --port 8080
```

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
