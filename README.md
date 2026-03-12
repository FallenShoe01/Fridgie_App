# Fridgie App

Fridgie is an Android-first Flutter app for tracking product and medicine expiry dates.

## Project Purpose
- Track products with barcode, name, category, buy date, expiry date, and image.
- Support multiple expiry batches for the same product.
- Notify users before expiry with configurable timing.
- Work offline after initial product lookup and local save.

## AI Implementation Guide
The full step-by-step execution plan for AI coding is here:

- `docs/AI_IMPLEMENTATION_PLAYBOOK.md`

Use that file as the source of truth for implementation order, verification, and acceptance criteria.

## Current Status
- Base Flutter scaffold initialized.
- Detailed AI playbook created.
- Foundation dependencies installed.
- Static analysis baseline passes (`flutter analyze`).
- Android manifest capability baseline completed.
- Debug APK build passes (`flutter build apk --debug`).
- Architecture folder skeleton created.
- Riverpod + `go_router` app shell wired.
- Drift database schema implemented (products, batches, images, cache, settings).
- Repository layer implemented with autocomplete, sorting, and batch duplication.
- Open-database barcode lookup provider layer implemented (OpenFoodFacts family).
- Lookup results are cached locally in DB (`lookup_cache`).
- Image service implemented for pick, crop, local save, and remote image download.
- Product list page with sorting and FAB add flow is implemented.
- Add Product page supports scanner sheet, world lookup prefill, manual fallback, and local autocomplete.
- Multi-batch entry with duplicate batch shortcut is implemented in Add Product flow.
- Notification service foundation is implemented with per-batch scheduling on save.
- Xiaomi/OEM background reliability guidance page is available from main screen.
- GitHub updater service foundation is implemented (release fetch + version compare).
- Android debug build, tests, and analyzer are currently passing.
- Unit tests and static analysis pass.
- Feature implementation is in progress.
