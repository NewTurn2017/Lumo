# Lumo — 배포 시스템 설계

**Date:** 2026-04-14  
**Status:** Approved  
**Target:** macOS 13+ / Apple Silicon / Developer ID 배포

---

## 1. 개요

Lumo의 공개 배포를 위한 전체 파이프라인 설계. Git 태그 push 하나로 빌드·서명·공증·DMG 생성·GitHub Release·appcast 업데이트까지 자동화한다.

**배포 채널:** GitHub Releases (DMG)  
**자동 업데이트:** Sparkle 2.x (EdDSA 서명, GitHub Pages appcast)  
**릴리즈 트리거:** `git tag v*.*.*` → `git push --tags`

---

## 2. 에셋

### AppIcon.appiconset (완료)

| 파일 | 크기 | 용도 |
|------|------|------|
| `icon_16.png` | 16×16 | Finder/Dock small |
| `icon_32.png` | 32×32 | 16pt @2x |
| `icon_64.png` | 64×64 | 32pt @2x |
| `icon_128.png` | 128×128 | 128pt @1x |
| `icon_256.png` | 256×256 | 256pt @1x |
| `icon_512.png` | 512×512 | 512pt @1x |
| `icon_1024.png` | 1024×1024 | 512pt @2x |

소스: 후레쉬가 브라우저 창을 비추는 미니멀 아이콘, 어두운 네이비 배경.

### MenuBarIcon.imageset (완료)

| 파일 | 크기 | 용도 |
|------|------|------|
| `menubar_icon.png` | 18×18 | @1x template |
| `menubar_icon@2x.png` | 36×36 | @2x template |

투명 배경, 흑백 template 렌더링.

### DMG 배경 (구현 필요)

- 파일: `scripts/dmg-background.png`
- 크기: 660×400px
- 내용: 어두운 배경 + Lumo 로고 + 드래그 안내 화살표
- create-dmg에서 참조

---

## 3. Sparkle 자동 업데이트

### 의존성 추가 (project.yml)

```yaml
packages:
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    from: "2.6.4"
```

### Info.plist 키

```xml
<key>SUPublicEDKey</key>
<string>44JMfuhD9wodqkPx/GL+xHWteYRACSO9XJU6KtC31WU=</string>
<key>SUFeedURL</key>
<string>https://newturn2017.github.io/Lumo/appcast.xml</string>
<key>SUEnableAutomaticChecks</key>
<true/>
```

### 앱 코드

- `AppDelegate`에 `SPUStandardUpdaterController` 프로퍼티 추가
- Settings 창 또는 메뉴의 "업데이트 확인..." 항목에 연결

### appcast.xml 호스팅

- GitHub Pages (`gh-pages` 브랜치)
- URL: `https://newturn2017.github.io/Lumo/appcast.xml`
- CI가 매 릴리즈마다 자동 업데이트

---

## 4. CI/CD — GitHub Actions

### 파일 위치

`.github/workflows/release.yml`

### 트리거

```yaml
on:
  push:
    tags:
      - 'v*.*.*'
```

### 파이프라인 단계

```
git tag v1.0.0 → git push --tags
       ↓
[GitHub Actions: macos-latest]
       ↓
1. xcodegen generate          # project.yml → .xcodeproj
2. xcodebuild archive         # Developer ID 서명
3. xcodebuild -exportArchive  # .app 추출
4. notarytool submit          # Apple 공증
5. stapler staple             # 티켓 첨부
6. create-dmg                 # DMG 생성 (배경 이미지 포함)
7. sign_update (Sparkle)      # EdDSA 서명 + appcast.xml 항목 생성
8. GitHub Release 생성        # DMG asset 업로드
9. gh-pages 브랜치 커밋       # appcast.xml 업데이트
```

### GitHub Secrets (등록 완료)

| Secret | 값 |
|--------|-----|
| `APPLE_CERTIFICATE_BASE64` | Developer ID .p12 base64 |
| `APPLE_CERTIFICATE_PASSWORD` | .p12 암호 |
| `APPLE_TEAM_ID` | `2UANJX7ATM` |
| `APPLE_ID` | `hyuni2020@gmail.com` |
| `APPLE_APP_PASSWORD` | 앱 전용 비밀번호 |
| `SPARKLE_PRIVATE_KEY` | EdDSA 비밀키 |

### ExportOptions.plist

```xml
<key>method</key>
<string>developer-id</string>
<key>teamID</key>
<string>2UANJX7ATM</string>
<key>signingStyle</key>
<string>manual</string>
```

---

## 5. .gitignore 업데이트

기존 항목 유지, 추가:

```
# Design docs & brainstorm assets
docs/
.superpowers/

# Icon source files
lumo-icon-source.png
lumo-menubar-source.png
lumo-menubar-nobg.png
```

---

## 6. README 구조

```
[Figlet 블록체 ASCII 로고 — "LUMO"]
[뱃지: macOS 13+ | Apple Silicon | Swift | License | Latest Release]

짧은 소개 (1-2줄)

## Features
## Installation
  - DMG 다운로드 직링크 (GitHub Release)
  - 시스템 요구사항 (macOS 13+, Apple Silicon)
## Usage
  - ⌘⇧1: 화면 영역 캡처 번역
  - ⌘C ⌘C: 선택 텍스트 번역
  - 언어 자동 감지 (한→영, 영→한)
## Local AI Setup
  - MLX 모델 설정 방법
## Auto Update
  - Sparkle 기반 자동 업데이트 안내
## Building from Source
  - xcodegen, xcodebuild 빌드법
## License
```

---

## 7. 파일 트리 (구현 후)

```
Lumo/
├── .github/
│   └── workflows/
│       └── release.yml
├── scripts/
│   ├── generate_icons.swift      (기존)
│   ├── dmg-background.png        (신규)
│   └── ExportOptions.plist       (신규)
├── Sources/Lumo/
│   ├── Assets.xcassets/
│   │   ├── AppIcon.appiconset/   (완료)
│   │   └── MenuBarIcon.imageset/ (완료)
│   └── Info.plist                (Sparkle 키 추가)
├── project.yml                   (Sparkle 의존성 추가)
├── README.md                     (신규)
└── .gitignore                    (docs/ 등 추가)
```
