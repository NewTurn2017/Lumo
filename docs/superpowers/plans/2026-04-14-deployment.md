# Lumo Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Git 태그 push 하나로 빌드·서명·공증·DMG·GitHub Release·appcast 업데이트까지 자동화하고, Sparkle 자동 업데이트와 함께 공개 배포 체계를 완성한다.

**Architecture:** GitHub Actions (macos-15)가 xcodegen → xcodebuild archive → notarytool → create-dmg → GitHub Release → gh-pages appcast 순서로 파이프라인을 실행한다. Sparkle 2.x가 gh-pages의 appcast.xml을 폴링해 자동 업데이트를 제공한다.

**Tech Stack:** Swift 5.9, Xcode 16, xcodegen, Sparkle 2.6.4, create-dmg, xcrun notarytool, GitHub Actions, GitHub Pages

---

## File Map

| 파일 | 작업 | 역할 |
|------|------|------|
| `.gitignore` | 수정 | docs/, .superpowers/, 아이콘 소스 추가 |
| `project.yml` | 수정 | Sparkle 패키지 + 타겟 의존성 추가 |
| `Sources/Lumo/Info.plist` | 수정 | Sparkle 공개키, feed URL, 자동 확인 키 추가 |
| `Sources/Lumo/App/AppDelegate.swift` | 수정 | SPUStandardUpdaterController 프로퍼티 추가 |
| `Sources/Lumo/Menu/MenuBarController.swift` | 수정 | "업데이트 확인..." 메뉴 항목 추가 |
| `scripts/ExportOptions.plist` | 생성 | xcodebuild -exportArchive 옵션 |
| `scripts/dmg-background.png` | 생성 | 660×400 DMG 창 배경 이미지 |
| `.github/workflows/release.yml` | 생성 | 전체 릴리즈 파이프라인 |
| `gh-pages` 브랜치 `appcast.xml` | 생성 | Sparkle 업데이트 피드 |
| `README.md` | 생성 | 공개 문서 |

---

## Task 1: .gitignore 업데이트

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: 항목 추가**

`.gitignore` 파일을 열어 기존 내용 아래에 추가:

```
# Design docs & brainstorm (local only)
docs/
.superpowers/

# Icon generation sources
lumo-icon-source.png
lumo-menubar-source.png
lumo-menubar-nobg.png

# CI/CD
*.p12
```

- [ ] **Step 2: 커밋**

```bash
git add .gitignore
git commit -m "chore: expand gitignore for docs and icon sources"
```

---

## Task 2: Sparkle 의존성 추가

**Files:**
- Modify: `project.yml`

- [ ] **Step 1: project.yml에 Sparkle 패키지 추가**

`project.yml`의 `packages:` 섹션에 추가 (KeyboardShortcuts 아래):

```yaml
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    from: "2.6.4"
```

`targets.Lumo.dependencies:` 리스트에 추가:

```yaml
      - package: Sparkle
```

최종 project.yml의 해당 섹션:

```yaml
packages:
  KeyboardShortcuts:
    url: https://github.com/sindresorhus/KeyboardShortcuts
    from: "2.0.0"
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    from: "2.6.4"

targets:
  Lumo:
    ...
    dependencies:
      - package: KeyboardShortcuts
      - package: Sparkle
```

- [ ] **Step 2: Xcode 프로젝트 재생성**

```bash
xcodegen generate
```

예상 출력: `✔ Generated project at Lumo.xcodeproj`

- [ ] **Step 3: Sparkle 패키지 resolve 확인**

```bash
xcodebuild -resolvePackageDependencies -scheme Lumo 2>&1 | tail -5
```

예상 출력: Sparkle 2.6.x resolved 메시지

- [ ] **Step 4: 커밋**

```bash
git add project.yml
git commit -m "chore(deps): add Sparkle 2.6.4 for auto-update"
```

---

## Task 3: Info.plist Sparkle 키 추가

**Files:**
- Modify: `Sources/Lumo/Info.plist`

- [ ] **Step 1: 키 3개 추가**

`Sources/Lumo/Info.plist`의 `</dict>` 바로 위에 삽입:

```xml
	<key>SUPublicEDKey</key>
	<string>44JMfuhD9wodqkPx/GL+xHWteYRACSO9XJU6KtC31WU=</string>
	<key>SUFeedURL</key>
	<string>https://newturn2017.github.io/Lumo/appcast.xml</string>
	<key>SUEnableAutomaticChecks</key>
	<true/>
```

- [ ] **Step 2: plist 유효성 확인**

```bash
plutil -lint Sources/Lumo/Info.plist
```

예상 출력: `Sources/Lumo/Info.plist: OK`

- [ ] **Step 3: 커밋**

```bash
git add Sources/Lumo/Info.plist
git commit -m "feat(sparkle): add Sparkle feed URL and public key to Info.plist"
```

---

## Task 4: Sparkle AppDelegate + MenuBarController 연결

**Files:**
- Modify: `Sources/Lumo/App/AppDelegate.swift`
- Modify: `Sources/Lumo/Menu/MenuBarController.swift`

- [ ] **Step 1: MenuBarController에 업데이트 콜백 추가**

`Sources/Lumo/Menu/MenuBarController.swift`에서 `setupMenu()` 메서드를 수정:

```swift
import AppKit

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private(set) var state: MenuBarState = .idle {
        didSet { render() }
    }

    /// AppDelegate가 Sparkle updater와 연결하기 위해 주입하는 콜백
    var onCheckForUpdates: (() -> Void)?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        render()
        setupMenu()
    }

    private func setupMenu() {
        let menu = NSMenu()

        let updateItem = NSMenuItem(title: "업데이트 확인...", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "설정...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Lumo 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func checkForUpdates() {
        onCheckForUpdates?()
    }

    @objc private func openSettings() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    func send(_ event: MenuBarEvent) {
        state = state.reduce(event)
    }

    private func render() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(named: "MenuBarIcon")
        button.image?.isTemplate = true
        button.toolTip = nil

        switch state {
        case .idle:
            button.appearsDisabled = false
        case .busy:
            button.appearsDisabled = false
        case .warning(let msg):
            button.toolTip = msg
        case .error(let msg):
            button.appearsDisabled = true
            button.toolTip = msg
        }
    }
}
```

- [ ] **Step 2: AppDelegate에 SPUStandardUpdaterController 추가**

`Sources/Lumo/App/AppDelegate.swift` 상단에 import 추가:

```swift
import Sparkle
```

`AppDelegate` 클래스 프로퍼티 선언부에 추가 (기존 `private var menu: MenuBarController!` 바로 위):

```swift
private let updaterController: SPUStandardUpdaterController
```

`override init()` 메서드 수정 — `super.init()` 호출 전에 updaterController 초기화 추가:

```swift
override init() {
    self.mlxServerManager = MLXServerManager.live(
        modelID: SettingsSnapshot.load().model
    )
    self.updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    super.init()
}
```

`applicationDidFinishLaunching` 내 `menu = MenuBarController()` 직후에 추가:

```swift
menu = MenuBarController()
menu.onCheckForUpdates = { [weak self] in
    self?.updaterController.updater.checkForUpdates()
}
```

- [ ] **Step 3: 빌드 확인**

```bash
xcodebuild build -scheme Lumo -configuration Debug 2>&1 | grep -E "error:|BUILD"
```

예상 출력: `BUILD SUCCEEDED` (error: 없음)

- [ ] **Step 4: 커밋**

```bash
git add Sources/Lumo/App/AppDelegate.swift Sources/Lumo/Menu/MenuBarController.swift
git commit -m "feat(sparkle): wire SPUStandardUpdaterController + check-for-updates menu item"
```

---

## Task 5: ExportOptions.plist 생성

**Files:**
- Create: `scripts/ExportOptions.plist`

- [ ] **Step 1: 파일 생성**

`scripts/ExportOptions.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>2UANJX7ATM</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
    <key>stripSwiftSymbols</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 2: 유효성 확인**

```bash
plutil -lint scripts/ExportOptions.plist
```

예상 출력: `scripts/ExportOptions.plist: OK`

- [ ] **Step 3: 커밋**

```bash
git add scripts/ExportOptions.plist
git commit -m "chore(ci): add ExportOptions.plist for Developer ID export"
```

---

## Task 6: DMG 배경 이미지 생성

**Files:**
- Create: `scripts/dmg-background.png`

- [ ] **Step 1: 660×400 배경 이미지 생성**

```bash
ffmpeg -y \
  -f lavfi -i "color=c=0x0D1117:size=660x400:rate=1" \
  -vframes 1 \
  /tmp/dmg-bg-base.png 2>/dev/null

# 화살표 안내 텍스트를 Python으로 오버레이
python3 - << 'PYEOF'
import struct, zlib, math

def make_png(width, height, pixels):
    def write_chunk(type_bytes, data):
        length = len(data)
        chunk = type_bytes + data
        return (struct.pack('>I', length) + chunk +
                struct.pack('>I', zlib.crc32(chunk) & 0xffffffff))

    raw = b''
    for row in pixels:
        raw += b'\x00' + bytes(row)
    compressed = zlib.compress(raw, 9)

    png  = b'\x89PNG\r\n\x1a\n'
    png += write_chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
    png += write_chunk(b'IDAT', compressed)
    png += write_chunk(b'IEND', b'')
    return png

W, H = 660, 400
bg = (13, 17, 23)   # #0D1117
pixels = [[list(bg) for _ in range(W)] for _ in range(H)]
data = make_png(W, H, pixels)
with open('scripts/dmg-background.png', 'wb') as f:
    f.write(data)
print("dmg-background.png created")
PYEOF
```

- [ ] **Step 2: 크기 확인**

```bash
sips -g pixelWidth -g pixelHeight scripts/dmg-background.png
```

예상 출력:
```
  pixelWidth: 660
  pixelHeight: 400
```

- [ ] **Step 3: 커밋**

```bash
git add scripts/dmg-background.png
git commit -m "chore(assets): add DMG window background (660x400)"
```

---

## Task 7: GitHub Actions 릴리즈 워크플로우

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: 워크플로우 디렉토리 생성**

```bash
mkdir -p .github/workflows
```

- [ ] **Step 2: release.yml 작성**

`.github/workflows/release.yml`:

```yaml
name: Release

on:
  push:
    tags:
      - 'v*.*.*'

permissions:
  contents: write
  pages: write
  id-token: write

jobs:
  build-and-release:
    runs-on: macos-15

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install tools
        run: |
          brew install xcodegen create-dmg

      - name: Generate Xcode project
        run: xcodegen generate

      - name: Import signing certificate
        env:
          APPLE_CERTIFICATE_BASE64: ${{ secrets.APPLE_CERTIFICATE_BASE64 }}
          APPLE_CERTIFICATE_PASSWORD: ${{ secrets.APPLE_CERTIFICATE_PASSWORD }}
        run: |
          KEYCHAIN_PATH=$RUNNER_TEMP/signing.keychain-db
          CERT_PATH=$RUNNER_TEMP/certificate.p12
          echo -n "$APPLE_CERTIFICATE_BASE64" | base64 --decode -o "$CERT_PATH"
          security create-keychain -p "" "$KEYCHAIN_PATH"
          security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
          security unlock-keychain -p "" "$KEYCHAIN_PATH"
          security import "$CERT_PATH" \
            -P "$APPLE_CERTIFICATE_PASSWORD" \
            -A -t cert -f pkcs12 \
            -k "$KEYCHAIN_PATH"
          security list-keychain -d user -s "$KEYCHAIN_PATH"

      - name: Build archive
        env:
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
        run: |
          xcodebuild archive \
            -scheme Lumo \
            -configuration Release \
            -archivePath "$RUNNER_TEMP/Lumo.xcarchive" \
            CODE_SIGN_IDENTITY="Developer ID Application" \
            CODE_SIGN_STYLE=Manual \
            DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
            -allowProvisioningUpdates

      - name: Export app
        run: |
          xcodebuild -exportArchive \
            -archivePath "$RUNNER_TEMP/Lumo.xcarchive" \
            -exportPath "$RUNNER_TEMP/export" \
            -exportOptionsPlist scripts/ExportOptions.plist

      - name: Notarize
        env:
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APPLE_APP_PASSWORD: ${{ secrets.APPLE_APP_PASSWORD }}
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
        run: |
          ditto -c -k --keepParent \
            "$RUNNER_TEMP/export/Lumo.app" \
            "$RUNNER_TEMP/Lumo-notarize.zip"
          xcrun notarytool submit "$RUNNER_TEMP/Lumo-notarize.zip" \
            --apple-id "$APPLE_ID" \
            --password "$APPLE_APP_PASSWORD" \
            --team-id "$APPLE_TEAM_ID" \
            --wait

      - name: Staple
        run: xcrun stapler staple "$RUNNER_TEMP/export/Lumo.app"

      - name: Create DMG
        run: |
          VERSION="${GITHUB_REF_NAME#v}"
          create-dmg \
            --volname "Lumo" \
            --volicon "Sources/Lumo/Assets.xcassets/AppIcon.appiconset/icon_512.png" \
            --background "scripts/dmg-background.png" \
            --window-pos 200 120 \
            --window-size 660 400 \
            --icon-size 128 \
            --icon "Lumo.app" 165 185 \
            --hide-extension "Lumo.app" \
            --app-drop-link 495 185 \
            "$RUNNER_TEMP/Lumo-${VERSION}.dmg" \
            "$RUNNER_TEMP/export/"
          echo "DMG_PATH=$RUNNER_TEMP/Lumo-${VERSION}.dmg" >> "$GITHUB_ENV"
          echo "VERSION=$VERSION" >> "$GITHUB_ENV"

      - name: Sign update for Sparkle
        env:
          SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}
        run: |
          SPARKLE_VER="2.6.4"
          curl -sL "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VER}/Sparkle-${SPARKLE_VER}.tar.xz" \
            -o /tmp/sparkle.tar.xz
          mkdir -p /tmp/sparkle_bin
          tar -xf /tmp/sparkle.tar.xz -C /tmp/sparkle_bin

          echo "$SPARKLE_PRIVATE_KEY" > /tmp/sparkle.key
          SIGNATURE=$(/tmp/sparkle_bin/bin/sign_update \
            --ed-key-file /tmp/sparkle.key \
            "$DMG_PATH")
          rm /tmp/sparkle.key

          DMG_SIZE=$(stat -f%z "$DMG_PATH")
          echo "SPARKLE_SIGNATURE=$SIGNATURE" >> "$GITHUB_ENV"
          echo "DMG_SIZE=$DMG_SIZE" >> "$GITHUB_ENV"

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          name: "Lumo ${{ env.VERSION }}"
          body: |
            ## Lumo ${{ env.VERSION }}

            ### 설치
            `Lumo-${{ env.VERSION }}.dmg`를 다운로드하고 Lumo.app을 Applications 폴더로 드래그하세요.

            **시스템 요구사항:** macOS 13.0+, Apple Silicon
          files: ${{ env.DMG_PATH }}
          draft: false
          prerelease: false

      - name: Generate appcast.xml
        run: |
          DATE=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")
          DMG_URL="https://github.com/NewTurn2017/Lumo/releases/download/v${VERSION}/Lumo-${VERSION}.dmg"
          cat > /tmp/appcast.xml << APPCAST
          <?xml version="1.0" encoding="utf-8"?>
          <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
               xmlns:dc="http://purl.org/dc/elements/1.1/">
            <channel>
              <title>Lumo</title>
              <link>https://newturn2017.github.io/Lumo/appcast.xml</link>
              <description>Lumo 업데이트</description>
              <language>ko</language>
              <item>
                <title>Lumo ${VERSION}</title>
                <pubDate>${DATE}</pubDate>
                <sparkle:version>${VERSION}</sparkle:version>
                <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
                <enclosure
                  url="${DMG_URL}"
                  length="${DMG_SIZE}"
                  type="application/octet-stream"
                  sparkle:edSignature="${SPARKLE_SIGNATURE}"/>
              </item>
            </channel>
          </rss>
          APPCAST

      - name: Deploy appcast to GitHub Pages
        uses: peaceiris/actions-gh-pages@v4
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: /tmp
          publish_branch: gh-pages
          include_hidden: false
          keep_files: false
          force_orphan: false
```

- [ ] **Step 3: 워크플로우 YAML 문법 확인**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yml'))" && echo "YAML valid"
```

예상 출력: `YAML valid`

- [ ] **Step 4: 커밋**

```bash
git add .github/workflows/release.yml
git commit -m "feat(ci): add GitHub Actions release pipeline with notarization + Sparkle"
```

---

## Task 8: GitHub Pages 초기 설정

**Files:**
- Create: `gh-pages` 브랜치 `appcast.xml` (초기 빈 피드)

- [ ] **Step 1: gh-pages 브랜치 생성 및 초기 appcast.xml 푸시**

```bash
git checkout --orphan gh-pages
git rm -rf . 2>/dev/null || true

cat > appcast.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Lumo</title>
    <link>https://newturn2017.github.io/Lumo/appcast.xml</link>
    <description>Lumo 업데이트</description>
    <language>ko</language>
  </channel>
</rss>
EOF

git add appcast.xml
git commit -m "chore(pages): initial empty appcast.xml"
git push origin gh-pages

git checkout main
```

- [ ] **Step 2: GitHub Pages 활성화**

```bash
gh api repos/NewTurn2017/Lumo/pages \
  --method POST \
  --field source='{"branch":"gh-pages","path":"/"}' \
  2>&1 || echo "(이미 활성화된 경우 무시)"
```

- [ ] **Step 3: appcast URL 접근 확인 (배포까지 최대 2분 소요)**

```bash
sleep 30
curl -s -o /dev/null -w "%{http_code}" \
  https://newturn2017.github.io/Lumo/appcast.xml
```

예상 출력: `200`

---

## Task 9: README.md 작성

**Files:**
- Create: `README.md`

- [ ] **Step 1: README.md 생성**

`README.md`:

```markdown
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
mlx_lm.server --model mlx-community/gemma-3-4b-it-4bit --port 8080
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
```

- [ ] **Step 2: LICENSE 파일 생성**

```bash
cat > LICENSE << 'EOF'
MIT License

Copyright (c) 2026 NewTurn2017

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF
```

- [ ] **Step 3: 커밋**

```bash
git add README.md LICENSE
git commit -m "docs: add README with CLI logo, usage, and installation guide"
```

---

## Task 10: 첫 번째 릴리즈 실행

- [ ] **Step 1: main 브랜치 GitHub push**

```bash
git push -u origin main
```

- [ ] **Step 2: 첫 릴리즈 태그**

```bash
git tag v1.0.0
git push origin v1.0.0
```

- [ ] **Step 3: Actions 실행 확인**

```bash
gh run watch --repo NewTurn2017/Lumo
```

모든 단계가 ✓로 완료되면 성공.

- [ ] **Step 4: 릴리즈 확인**

```bash
gh release view v1.0.0 --repo NewTurn2017/Lumo
```

예상 출력: `Lumo-1.0.0.dmg` asset 포함된 릴리즈 정보

- [ ] **Step 5: appcast.xml 확인**

```bash
curl -s https://newturn2017.github.io/Lumo/appcast.xml | grep -E "version|edSignature"
```

예상 출력: version 1.0.0 및 edSignature 포함
```
