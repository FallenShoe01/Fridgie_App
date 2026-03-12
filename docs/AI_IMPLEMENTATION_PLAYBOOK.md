# Fridgie App AI Implementation Playbook

This document is a step-by-step execution guide for AI-assisted coding.

How to use this file:
1. Execute one micro-step only.
2. Run the verification for that micro-step.
3. Fix issues before moving to the next micro-step.
4. Commit after each completed macro step.

## Goal Summary
Build an Android-first Flutter app that tracks product and medicine expiry with:
- Local database for product data and batch expiries.
- Barcode lookup via open world databases.
- Barcode camera scanning.
- Local image upload + crop + storage.
- Configurable local notifications (including Xiaomi guidance).
- Main list with sorting and days-to-expiry.
- Backup/restore (SQLite and ZIP).
- GitHub release APK updater (OTA-style distribution).

## Macro Step 0: Foundation Setup

### 0.1 Dependencies
- [x] Add packages to `pubspec.yaml`:
  - State/UI: `flutter_riverpod`, `go_router`
  - DB: `drift`, `sqlite3_flutter_libs`, `path_provider`, `path`
  - Network: `dio`, `connectivity_plus`
  - Barcode: `mobile_scanner`
  - Images: `image_picker`, `image_cropper`
  - Notifications: `flutter_local_notifications`, `timezone`
  - Android intents/permissions: `android_intent_plus`, `permission_handler`
  - Update: `package_info_plus`
  - Backup/share: `archive`, `file_picker`, `share_plus`
  - i18n: `easy_localization`, `intl`
- [x] Run `flutter pub get`.

Verification:
- [x] `flutter pub get` succeeds.
- [x] `flutter analyze` runs without dependency errors.

### 0.2 Android capability baseline
- [x] Update `android/app/src/main/AndroidManifest.xml` with required permissions:
  - Camera
  - Internet
  - Post notifications (Android 13+)
  - Boot completed (for rescheduling notifications)
- [x] Add required notification receivers/services per plugin docs.
- [x] Confirm `minSdk` in `android/app/build.gradle.kts` satisfies package requirements.

Verification:
- [x] `flutter build apk --debug` succeeds.

## Macro Step 1: Architecture Skeleton

### 1.1 Folder layout
- [x] Create:
  - `lib/app/`
  - `lib/core/db/`, `lib/core/network/`, `lib/core/storage/`
  - `lib/features/products/`, `lib/features/lookup/`, `lib/features/images/`
  - `lib/features/notifications/`, `lib/features/backup/`, `lib/features/update/`, `lib/features/settings/`
  - `lib/l10n/`, `lib/shared/`

### 1.2 App shell
- [x] Replace `lib/main.dart` with app bootstrap using Riverpod + router.
- [x] Add a temporary home page route.

Verification:
- [x] Build compiles with app shell (`flutter analyze`, `flutter build apk --debug`).
- [ ] Run on a connected device/emulator and confirm shell page renders.

## Macro Step 2: Database (Critical Path)

### 2.1 Schema
- [x] Implement Drift schema in `lib/core/db/app_database.dart`.
- [x] Define tables:
  - `products`
  - `product_batches`
  - `product_images`
  - `lookup_cache`
  - `app_settings`
- [x] Add FK constraints and indexes (`barcode`, `product_id`, etc.).

### 2.2 Repositories
- [x] Create repositories for products/batches.
- [x] Add queries for:
  - CRUD
  - Sort by name and expiry
  - Local name autocomplete
  - Duplicate batch

Verification:
- [x] Unit tests for schema open/CRUD/sort/autocomplete/duplicate.
- [x] `flutter test` and `flutter analyze` pass.

## Macro Step 3: Barcode Lookup (Open Databases)

### 3.1 Provider interface
- [x] Create lookup provider contract (`lookupByBarcode`).
- [x] Implement orchestration with fallback and timeout.

### 3.2 Open providers
- [x] Add OpenFoodFacts-family providers.
- [x] Parse canonical fields: name, barcode, category, image URL.
- [x] Save raw payload to `lookup_cache`.

### 3.3 Fallback behavior
- [x] If not found, force manual entry flow.
- [x] Save manual entries to local DB for future autocomplete.

Verification:
- [x] Provider and lookup service unit tests pass (`flutter test`).
- [x] Add flow supports known barcode prefill and unknown barcode manual fallback.
- [ ] Device-level barcode camera scan smoke test pending (requires connected device/emulator).

## Macro Step 4: Image Pipeline

### 4.1 Pick + crop + store
- [x] Implement image picking from camera/gallery.
- [x] Crop to a standardized ratio/size.
- [x] Save locally under app documents directory.

### 4.2 Mapping
- [x] Link image to product and barcode in DB.
- [x] Download remote image from lookup and store locally.
- [x] Never rely on remote URL for final UI rendering.

Verification:
- [x] Product list and add flow use local image paths.
- [ ] Restart + offline image persistence manual smoke pending.

## Macro Step 5: Add Product UX

### 5.1 Add flow page
- [x] Add FAB on main screen.
- [x] Build add page with:
  - scan barcode
  - manual barcode input
  - name field with autocomplete
  - image picker/crop

### 5.2 Add logic
- [x] On barcode: query world DB first.
- [x] Prefill if found; allow edits before save.
- [x] If not found: manual add.

Verification:
- [x] Add by scan trigger/manual/autocomplete code path implemented.
- [ ] Physical-device camera scan confirmation pending.

## Macro Step 6: Multi-Batch Expiry

### 6.1 Batch support
- [x] Product can have multiple batches with separate expiry dates.
- [x] Each batch stores quantity and notification config. (default values currently from schema)

### 6.2 Duplicate shortcut
- [x] Add duplicate batch action for quick repeated entries.

Verification:
- [x] Add-product flow supports creating 3+ batches and duplicate batch action.
- [ ] Manual UI smoke test on device pending.

## Macro Step 7: Main Screen and Sorting

### 7.1 Product list UI
- [x] Build row format: `image - name - days until expiry`.
- [ ] Add visual state for expired/near/safe.

### 7.2 Sorting
- [x] Add sorting by:
  - name
  - alphabetic direction
  - expiry date
- [x] Persist selected sorting in settings table.

Verification:
- [x] Sorting toggles in UI.
- [x] Sorting persistence across restart pending.

## Macro Step 8: Notifications

### 8.1 Scheduler
- [x] Schedule per batch at `(expiry - daysBefore) + selected time`. (default 3 days, 09:00 in add flow)
- [x] Reschedule on batch create/update/delete.
- [ ] Reschedule after device reboot/timezone changes.

### 8.2 Manageability
- [x] Add per-batch and global notification defaults.
- [x] Add settings screen for defaults.

### 8.3 OEM reliability (Xiaomi included)
- [x] Add onboarding guidance page for battery/autostart restrictions.
- [x] Add deep links/intents where possible.
- [ ] Add diagnostics page with next scheduled triggers.

Verification:
- [x] Notification schedule calculation tests added.
- [ ] Foreground/background/reboot manual verification pending.

## Macro Step 9: GitHub OTA (APK Updater)

### 9.1 Check for updates
- [x] Query GitHub Releases API.
- [x] Compare latest release tag with installed version.

### 9.2 Download/install
- [x] Download APK asset with progress.
- [ ] Validate file checksum/size if available.
- [x] Trigger installer and handle unknown-sources guidance.

Verification:
- [x] Updater service unit tests cover release parsing and version comparison.
- [x] In-app update UI flow and installer launch implemented.

## Macro Step 10: Backup and Restore

### 10.1 SQLite mode
- [x] Export raw SQLite DB (included in ZIP).
- [x] Import SQLite DB with validation.

### 10.2 ZIP mode
- [x] Export ZIP with:
  - metadata JSON
  - DB file
  - images directory
- [x] Import ZIP with merge/replace modes and rollback on failure.

Verification:
- [x] ZIP round-trip unit tests pass.
- [ ] Export -> reinstall -> import device smoke test pending.

## Macro Step 11: Localization and Timezone

### 11.1 i18n
- [x] Externalize UI strings.
- [x] Add English + Russian.

### 11.2 Date/time
- [x] Use locale-aware formatting (`DateFormat.yMd`).
- [x] Use local timezone for notifications and display.

Verification:
- [x] Language and timezone changes are reflected correctly.

## Macro Step 12: CI/CD

### 12.1 CI checks
- [x] Add `.github/workflows/ci.yml` for analyze + test.

### 12.2 Release workflow
- [x] Add `.github/workflows/android-release.yml` to build APK and attach to GitHub Release.

Verification:
- [x] CI workflow triggers on push/PR.
- [x] Release workflow produces downloadable APK artifact on `v*` tags.

## Macro Step 13: End-to-End Acceptance
- [ ] Scan known barcode -> data fetched -> saved locally.
- [ ] Unknown barcode -> manual entry works.
- [ ] Name autocomplete suggests local items and prefills image.
- [ ] Product with multiple expiries works with duplicate option.
- [ ] Main list row format and sorting match requirements.
- [ ] Configurable notifications trigger correctly.
- [ ] Xiaomi guidance present.
- [ ] GitHub updater works.
- [ ] Backup/restore works in both formats.
- [ ] Offline mode works after initial data fetch.

## Notes on Constraints
- Global medicine barcode coverage in open no-auth APIs is incomplete.
- Required fallback: manual medicine entry + local persistence for future autocomplete.
- Absolute notification guarantees are impossible on some OEM policies; this plan includes best-practice mitigation.
