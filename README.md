# Foglietto

A mobile port of **[Buffer](https://gitlab.gnome.org/cheywood/buffer)** — the minimal
ephemeral text editor for GNOME, originally created by **Chris Heywood** — rebuilt as a
**Kotlin Multiplatform** app with a native SwiftUI iOS front-end.

The app opens to a blank page. The user types. The text is gone when the app closes.
The last 10 notes are silently preserved and recoverable.

> **Unofficial project.** Foglietto is a community-built port and is **not affiliated
> with, endorsed by, or maintained by** Chris Heywood or the GNOME project.

---

## Architecture

```
shared/          Kotlin Multiplatform module — domain + data only, NO presentation.
                 Targets: commonMain · jvmTest · iosArm64 · iosSimulatorArm64 · iosX64.
                 Built as an XCFramework consumed by iosApp/ over Swift Package Manager.

iosApp/          Native SwiftUI application (iOS 26+, first-class Liquid Glass).
                 Owns all presentation; calls into shared/ suspend use cases.
```

This is the **iOS-only MVP** (Milestone 1 — scaffold). The `shared/` module is
intentionally empty of ported logic; domain and data ports land in Milestone 2.

---

## Build & test

### Prerequisites

- JDK 17+ on `PATH` (for Gradle/JVM-side tasks — no Kotlin SDK required separately).
- macOS + Xcode 26 for iOS archive (CI only; no local Mac assumed).

### JVM-side shared tests (Mac-less — runs on Linux/CI with JDK 17)

```bash
# Full check — resolves deps, compiles shared module, runs JVM tests
./gradlew check

# Scoped fast test (JVM target only)
./gradlew :shared:jvmTest
```

These tasks require no Apple toolchain and are the authoritative local verification
gate. Use them to confirm dependency resolution and shared-module correctness.

### Build the shared XCFramework (CI — macOS/Xcode required)

```bash
./gradlew :shared:assembleSharedReleaseXCFramework
# Artifact: shared/build/XCFrameworks/release/shared.xcframework
```

The XCFramework is consumed by `iosApp/` via the local Swift package at
`iosApp/SharedPackage/Package.swift` (SPM `.binaryTarget`, no CocoaPods).

### iOS archive (CI only — macOS 15 + Xcode 26)

```bash
xcodebuild \
  -project iosApp/iosApp.xcodeproj \
  -scheme iosApp \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/iosApp.xcarchive \
  archive
```

Run this **after** the XCFramework step above. On CI the build number is injected via
`CURRENT_PROJECT_VERSION=$GITHUB_RUN_NUMBER`.

---

## CI

| Workflow | Runner | Trigger | What it does |
|---|---|---|---|
| `quality.yml` | `ubuntu-latest` | push / PR to `main`, `kmp-rewrite` | `./gradlew check` — JVM-side shared tests, dep resolution |
| `ios.yml` `build_ios` | `macos-26` + Xcode 26 | push / PR to `main`, `kmp-rewrite` | Gradle XCFramework → `xcodebuild archive` (no-codesign smoke) |
| `ios.yml` `deploy_testflight` | `macos-26` + Xcode 26 | tag `v*` only | Code-sign, export IPA, upload to TestFlight via `altool` |

Android build is retired in the iOS-only MVP; `android.yml` has been removed.

The `ios.yml` deploy job requires eight secrets configured in the GitHub repository
settings (retained from the previous Flutter build):
`IOS_DIST_CERT_P12_BASE64`, `IOS_DIST_CERT_PASSWORD`,
`IOS_PROVISIONING_PROFILE_BASE64`, `APPLE_TEAM_ID`,
`APP_STORE_CONNECT_API_KEY`, `APP_STORE_CONNECT_API_KEY_ID`,
`APP_STORE_CONNECT_API_ISSUER_ID`, `APP_STORE_CONNECT_APP_ID`.

---

## Credits

Foglietto is based on **Buffer**, the original GNOME desktop application created and
maintained by **Chris Heywood**:

- Original source: <https://gitlab.gnome.org/cheywood/buffer>
- The original is written in Rust (GTK / libadwaita). Foglietto ports the concept and
  UX to Kotlin Multiplatform + native SwiftUI.

The original idea, design, and name are Chris Heywood's.

---

## License

Licensed under the **[GNU General Public License v3.0](LICENSE) (GPLv3)**.

- Original Buffer concept: © **Chris Heywood**.
- KMP/SwiftUI implementation: © **Paolo Santucci**.
