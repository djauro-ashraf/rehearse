# Releasing Rehearse

This document explains how **Rehearse** keeps its Android app identity consistent so every future APK update installs cleanly on your phone without losing data or hitting signature-conflict errors.

## App Identity

- **Application ID / Package Name:** `app.rehearse` (configured in `android/app/build.gradle.kts`)
- **Signing Keystore (local, gitignored):** `android/app/rehearse-release.jks`
- **Signing Properties (local, gitignored):** `android/key.properties`
- **Key Alias:** `rehearse`
- **Certificate SHA-1:** `20:35:D3:B5:72:40:48:E3:86:E2:FE:2D:C3:DB:66:A5:3E:DB:4F:96`
- **Certificate SHA-256:** `64:0B:5D:5B:37:85:4F:13:89:3B:55:DC:18:64:72:3C:E5:56:86:03:04:A0:4F:47:FC:26:47:E4:49:C8:41:F3`

> **Important:** Never delete or replace `android/app/rehearse-release.jks` or change `applicationId`. Android rejects updates if either the package ID or the signing certificate changes. The keystore is gitignored so private keys are never exposed in the public repository; an identical copy is stored in GitHub Actions repository secrets (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`).

## Creating a New GitHub Release

1. Update the version in `pubspec.yaml` (for example `version: 1.0.1+2`) and commit your changes to `main`.
2. Tag the release and push the tag:
   ```bash
   git tag v1.0.1
   git push origin main --tags
   ```
3. GitHub Actions (`.github/workflows/release.yml`) will automatically:
   - Run `flutter analyze` and `flutter test`
   - Build a signed release APK using the repository signing secrets
   - Verify the APK signing certificate fingerprint
   - Publish a GitHub Release with `rehearse-v1.0.1.apk` and its `.sha256` checksum attached

You can also trigger a release manually from the **Actions → Release Android APK → Run workflow** tab on GitHub.

## Building a Signed APK Locally

Because `android/app/rehearse-release.jks` and `android/key.properties` are kept in the local project directory, running a standard release build signs with the exact same release identity:

```bash
flutter build apk --release -P releaseSigningRequired=true --dart-define=APP_VERSION=1.0.0
```
