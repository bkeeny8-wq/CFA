# CFAL3 — CFA Level III Study App

Personal iOS study app for CFA Level III case-based questions, spaced repetition, and Claude-powered essay grading.

## Device

**iPad only.** `TARGETED_DEVICE_FAMILY = 2`. Build, run and TEST on an iPad
simulator — the layouts that matter (the Study and Vignettes split views, the
width-capped Practice list, the tab bar rendered as a floating pill at the
top) only exist at regular width. A green run on an iPhone simulator proves
very little: the UI suite once passed in full on iPhone while every test in it
failed on iPad.

```bash
xcodebuild -project CFAL3.xcodeproj -scheme CFAL3 \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' test
```

## Requirements

- **Xcode 15+** with the **iOS 17 SDK**
- **iPadOS 17.0+** device or simulator
- Network access for essay grading and optional MC reasoning grading (via the deployed grader proxy)

## Open the project

1. Clone or copy this repo to your Mac.
2. Open `CFAL3.xcodeproj` in Xcode.
3. Select the **CFAL3** scheme and your target device.

## Signing & bundle identifier

1. Select the **CFAL3** project in the navigator → **CFAL3** target → **Signing & Capabilities**.
2. Set **Team** to your Apple ID (Personal Team works for sideloading onto an iPad).
3. Change **Bundle Identifier** if needed (default: `com.brandonkeeny.CFAL3`).
4. Repeat for **CFAL3Tests** if you run unit tests on device.

The target is **iPad-only** (`TARGETED_DEVICE_FAMILY = 2`). Do not install onto an iPhone — the Study and Vignettes split views, the width-capped Practice list, and the tab bar as a floating pill at the top only exist at regular width.

## Grader proxy

Essay and reasoning grading call a **Cloudflare Worker** (`workers/grader-proxy-worker.js`) that holds the Anthropic API key server-side. Set `GraderConfig.endpoint` and `GraderConfig.proxyToken` in `CFAL3/Services/GraderConfig.swift` to match your deployed worker. Browsing questions and tracking progress work offline; grading requires network access.

## Privacy

- No analytics or telemetry
- No third-party SDKs
- No accounts or cloud sync (v1)
- User progress is stored locally via SwiftData

## Tests

In Xcode: **Product → Test** (⌘U). Unit tests cover SM-2 scheduling and grading JSON parsing.

## Bundled content

- `question_bank.json` — cases and questions (read-only)
- `los_master.json` — LOS hierarchy
- `topics.json` — topic index

Replace these files to update the question bank; do not edit them at runtime from the app.

## LOS Study Pal

The **Study** tab is a digital version of your review materials:

- **Study notes** — **36 of 36** readings bundled as `reading_notes.json` (including Asset Manager Code)
- **LOS checklist** — all **247 LOS** with tap-to-mark progress
- **Practice questions** — filtered by reading/LOS from the question bank

Note: the R26 Endowment case-study notes were authored in-app (no `.docx` source exists), so `convert_reading_notes.py` will **not** regenerate that entry — preserve it when re-converting from Word files.

Re-convert notes after editing the Word files:

```bash
python3 scripts/convert_reading_notes.py
```

Or sync everything from `~/Desktop/CFA L3 Exam/Archive.zip` (notes docx, drill JSONs, and bank files if present):

```bash
python3 scripts/ingest_archive.py
```

Drop `los_drills_r2.json`, `los_drills_r3.json`, etc. into `CFAL3/Resources/` and run:

```bash
python3 scripts/sync_drills.py   # updates index + Xcode — no AI, instant
```

Full archive ingest (notes + drills + bank files):

```bash
python3 scripts/ingest_archive.py
```

### Content generation (minimize AI usage)

| Step | Who | Cost |
|------|-----|------|
| Generate `los_drills_rN.json` | You (Claude web/API) or Cursor, **one reading at a time** | Your choice |
| Drop file in `CFAL3/Resources/` | You | Free |
| `python3 scripts/sync_drills.py` | Local script | Free |
| Rebuild in Xcode | You | Free |

**Do not** regenerate content that already exists on disk. The app only loads files listed in `los_drills_index.json` and bundled in the Xcode project — a JSON file sitting in Resources without running `sync_drills.py` is invisible to the app.

Drill bundles are **not** capped at 4 questions per LOS. R3 ships 75 MC (7–8 per unique LOS). Target depth per reading is in `content_targets.json` (~75 MC + ~25 essay for R3).
