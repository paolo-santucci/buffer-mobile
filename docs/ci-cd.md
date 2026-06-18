# CI/CD Guide — Buffer (Android + iOS)

This project ships three GitHub Actions workflows under `.github/workflows/`. This
document explains what each one does, the secrets they need, how to obtain and add
those secrets, and how to cut a release.

> App identity: bundle / application id `com.paolosantucci.foglietto` on both platforms.
> Flutter is pinned in every workflow to **3.44.2** (your local version).

---

## 1. Workflows at a glance

| File | Job(s) | Triggers | What it produces |
|------|--------|----------|------------------|
| `quality.yml` | `quality` | push to `main`, PRs to `main`, manual | Lint, analyze, codegen-determinism check, tests + coverage report (non-blocking) |
| `android.yml` | `build_android` | push to `main`, `v*` tags, PRs, manual | Debug APKs, release APKs (split-per-ABI), release AAB — uploaded as artifacts |
| `ios.yml` | `build_ios` | push to `main`, `v*` tags, PRs | Compile-only sanity build (no signing) |
| `ios.yml` | `deploy_testflight` | **`v*` tags only** | Signed IPA uploaded to TestFlight |

Key design points:

- **The CI is green with zero secrets configured.** Android release falls back to
  debug signing; the iOS deploy job is skipped on everything except `v*` tags.
- **Secrets are only needed when you want signed/released artifacts.**
- **The coverage check is informational** — it prints the line-coverage summary but
  never fails the build (see §6 to turn it into a hard gate later).

---

## 2. One-time setup: the GitHub Secrets

Add secrets in the GitHub repo UI:
**Settings → Secrets and variables → Actions → New repository secret.**

Nothing below is ever committed — the workflows decode each secret onto the
ephemeral runner and wipe signing material in an `always()` cleanup step.

### 2a. Android signing (optional — enables a real release signature)

Without these four, release APK/AAB are **debug-signed** (fine for testing, **not**
acceptable for Play Store). To sign properly you need a keystore.

**Create a keystore** (once; keep the file + passwords safe and private — losing it
means you can never update the Play listing):

```bash
keytool -genkey -v \
  -keystore buffer-release.keystore \
  -alias buffer \
  -keyalg RSA -keysize 2048 -validity 10000
```

**Base64-encode it for the secret** (Linux):

```bash
base64 -w0 buffer-release.keystore
```

Add these secrets:

| Secret                    | Value                                    |
| ------------------------- | ---------------------------------------- |
| `KEYSTORE_BASE64`         | output of the `base64 -w0` command above |
| `KEYSTORE_STORE_PASSWORD` | the keystore (store) password you chose  |
| `KEYSTORE_KEY_PASSWORD`   | the key password you chose               |
| `KEYSTORE_KEY_ALIAS`      | the alias (e.g. `buffer`)                |

> Local note: `android/key.properties`, `*.keystore`, `*.jks` are already gitignored.
> For a local release build, create `android/key.properties` by hand with
> `storePassword` / `keyPassword` / `keyAlias` / `storeFile=buffer-release.keystore`
> and drop the keystore in `android/app/`. `build.gradle.kts` reads it automatically
> and otherwise falls back to debug signing.

### 2b. iOS signing + TestFlight (required only for `deploy_testflight`)

You have no Mac locally — all of this is consumed on the CI macOS runner. You still
need an **Apple Developer Program** membership ($99/yr) to obtain the materials. The
items below come from the Apple Developer portal and App Store Connect.

| Secret                             | What it is                                                                        | Where to get it                                                             |
| ---------------------------------- | --------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `IOS_DIST_CERT_P12_BASE64`         | Apple **Distribution** certificate + private key, as a base64 `.p12`              | See "Distribution certificate" below                                        |
| `IOS_DIST_CERT_PASSWORD`           | password you set when exporting the `.p12`                                        | you choose it at export                                                     |
| `IOS_PROVISIONING_PROFILE_BASE64`  | base64 of an **App Store** provisioning profile for `com.paolosantucci.foglietto` | Developer portal → Profiles → Distribution → App Store                      |
| `IOS_KEYCHAIN_PASSWORD`            | an arbitrary password for the throwaway CI keychain                               | invent any strong string                                                    |
| `IOS_DEVELOPMENT_TEAM_ID`          | your 10-char Apple Team ID                                                        | Apple Developer → Membership details                                        |
| `APP_STORE_CONNECT_API_KEY_BASE64` | base64 of the `.p8` App Store Connect API key                                     | App Store Connect → Users and Access → Integrations → App Store Connect API |
| `APP_STORE_CONNECT_API_KEY_ID`     | the key's ID (e.g. `2X9ABC3DEF`)                                                  | shown next to the key                                                       |
| `APP_STORE_CONNECT_API_ISSUER_ID`  | the issuer UUID for the API keys                                                  | top of the same API keys page                                               |

**Distribution certificate → `.p12` (no Mac):** the classic Keychain Access export
needs a Mac. Without one, the simplest path is **fastlane** run on the macOS runner
(`fastlane cert`/`match`) to create and store the cert, or generate it via `openssl`
from a CSR + the downloaded `.cer`:

```bash
# 1. Generate a private key + CSR
openssl req -new -newkey rsa:2048 -nodes \
  -keyout dist.key -out dist.csr \
  -subj "/emailAddress=paolo@paolosantucci.com/CN=Buffer Distribution/C=IT"
# 2. Upload dist.csr in the Apple portal → create an "Apple Distribution"
#    certificate → download dist.cer
# 3. Convert the DER .cer to PEM, then bundle key+cert into a .p12
openssl x509 -inform DER -in dist.cer -out dist.pem
openssl pkcs12 -export -legacy \
  -inkey dist.key -in dist.pem \
  -out dist.p12 -passout pass:YOUR_P12_PASSWORD
# 4. Base64 for the secret
base64 -w0 dist.p12
```

(`YOUR_P12_PASSWORD` becomes `IOS_DIST_CERT_PASSWORD`.)

**Base64 for the profile and the API key** (Linux):

```bash
base64 -w0 profile.mobileprovision   # → IOS_PROVISIONING_PROFILE_BASE64
base64 -w0 AuthKey_XXXXXXXXXX.p8      # → APP_STORE_CONNECT_API_KEY_BASE64
```

> The provisioning profile's bundle id **must** be `com.paolosantucci.foglietto` and it
> must reference the same Distribution certificate you put in `IOS_DIST_CERT_P12_BASE64`.
> The export template at `ios/ExportOptions.plist.template` already pins that bundle id.

---

## 3. Day-to-day: what runs when

- **Open a PR / push to `main`** → `quality`, `build_android` (debug + release
  artifacts), and `build_ios` (compile sanity) run. No signing secrets required;
  unsigned/debug artifacts are still produced and uploaded.
- **Download build artifacts** → the run's **Summary** page, "Artifacts" section
  (`debug-apks`, `release-apks`, `release-aab`).

---

## 4. Cutting a release

### Android (Play Store)

1. Bump the version in `pubspec.yaml` (`version: 1.0.0+1` → e.g. `1.0.1+2`; the
   `+N` build number must strictly increase for each Play upload).
2. Ensure the four Android secrets (§2a) are set so the AAB is release-signed.
3. Push to `main` (or a `v*` tag) → download the `release-aab` artifact
   (`com.paolosantucci.foglietto-release.aab`).
4. Upload that AAB to the Play Console (Internal testing → … → Production).

### iOS (TestFlight)

1. Bump `pubspec.yaml` (the workflow passes `--build-name=1.0.0`; update that line in
   `ios.yml` if the marketing version changes — the build **number** is the GitHub run
   number, which auto-increments).
2. Ensure all eight iOS secrets (§2b) are set.
3. Create and push a tag:

   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

4. The `deploy_testflight` job builds, signs, archives, exports the IPA, validates it,
   and uploads to TestFlight via `altool`. Watch it under the repo's **Actions** tab.
5. The build appears in App Store Connect → TestFlight after Apple finishes processing.

> Tip: tags trigger **both** `build_android` and `ios.yml`. If you only want the iOS
> deploy on a tag, that's already how it's wired — the Android job just rebuilds the
> same artifacts.

---

## 5. Maintaining the Flutter pin

The `quality` job regenerates code (`build_runner`) and fails if the result differs
from what's committed, and it enforces `pubspec.lock`. So when you upgrade Flutter
locally:

1. Update the `flutter-version:` value (currently `3.44.2`) in **all three** workflow
   files.
2. Run `flutter pub get` and `dart run build_runner build --delete-conflicting-outputs`
   locally, then `dart format .`.
3. Commit the refreshed `pubspec.lock` and any regenerated `*.g.dart` / `*.freezed.dart`.

If CI's "Check formatting and codegen determinism" step ever fails, it means committed
generated files or formatting drifted — run the three commands above and commit.

---

## 6. Turning coverage into a hard gate (later)

Right now `quality.yml` only **prints** line coverage. Once you know Foglietto's real
number and want to enforce a floor, replace the "Coverage report" step's final lines
with a threshold check, e.g.:

```bash
SUMMARY=$(lcov --summary coverage/lcov_filtered.info 2>&1); echo "$SUMMARY"
PCT=$(echo "$SUMMARY" | grep -E 'lines\.*:' | awk '{print $2}' | tr -d '%')
PASS=$(awk -v p="$PCT" 'BEGIN{print (p>=80)?"yes":"no"}')
[ "$PASS" = yes ] || { echo "FAILED: coverage ${PCT}% < 80%"; exit 1; }
```

Pick a threshold at or just below the measured value so you ratchet up, not break the
build on day one.

---

## 7. Security notes

- All signing material is decoded only onto the ephemeral runner and removed in an
  `always()` cleanup step; nothing is committed or left in artifacts.
- The iOS provisioning-profile UUID is masked in logs (`::add-mask::`).
- Keep `KEYSTORE_*`, the `.p12`, and the `.p8` private. The Android keystore in
  particular is **unrecoverable** — back it up offline; losing it forfeits the ability
  to update the Play listing.
