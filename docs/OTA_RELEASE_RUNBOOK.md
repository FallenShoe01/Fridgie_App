# Fridgie OTA Release Runbook (GitHub Releases)

This runbook explains how to publish new APK versions so users can update from inside the app.

## 1. Create GitHub Repository

1. Create a new repository in GitHub (private or public).
2. Push project code:

```bash
git init
git add .
git commit -m "Initial Fridgie release"
git branch -M main
git remote add origin https://github.com/<owner>/<repo>.git
git push -u origin main
```

## 2. Configure Android Identity and FileProvider

1. Ensure `applicationId` in `android/app/build.gradle.kts` matches your real app id.
2. Ensure FileProvider authority in `AndroidManifest.xml` uses the same app id suffix:

- `android:authorities="<applicationId>.fileprovider"`

3. Keep `android/app/src/main/res/xml/file_paths.xml` present.

## 3. Configure GitHub Actions Release Workflow

This project already includes `.github/workflows/android-release.yml`.

1. Commit and push workflows.
2. Ensure release job has `contents: write` permission.
3. (Optional) Add signing secrets and release signing if you distribute production APKs.

## 4. In-App OTA Configuration (once per device)

In Fridgie app:

1. Open `Settings` tab.
2. Set:
- GitHub owner / username
- GitHub repository name
3. Tap `Check for updates`.

The app calls GitHub Releases API:
- `https://api.github.com/repos/<owner>/<repo>/releases/latest`

## 5. Publish New Version to Users

1. Increase app version in `pubspec.yaml` (example: `0.2.0+2`).
2. Commit changes and push to `main`.
3. Create and push tag using semantic versioning:

```bash
git tag v0.2.0
git push origin v0.2.0
```

4. GitHub Action builds `app-release.apk` and attaches it to release `v0.2.0`.
5. Users tap `Check for updates` -> `Download & Install` in app.

## 6. Recommended Release Rules

1. Use `vMAJOR.MINOR.PATCH` tags (`v1.4.0`).
2. Keep one APK asset in each GitHub release.
3. Add release notes for user-facing changes.
4. Verify install flow on at least one physical Android device before announcement.

## 7. Rollback / Hotfix

1. Build and publish a higher patch version (example `v0.2.1`) with the fix.
2. Avoid deleting already released tags used by clients.
3. If a release is broken, mark release notes with warning and publish hotfix immediately.

## 8. Troubleshooting

- No update found:
  - Verify owner/repo in app settings.
  - Ensure latest release contains an `.apk` asset.
- Installer does not open:
  - Verify FileProvider authority equals current app id.
  - Ensure unknown apps install permission is granted on device.
- GitHub API failure:
  - Check network and GitHub status.
  - Public API is rate-limited when unauthenticated.
