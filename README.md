# CFAL3 — CFA Level III Study App

Personal iOS study app for CFA Level III case-based questions, spaced repetition, and Claude-powered essay grading.

## Requirements

- **Xcode 15+** with the **iOS 17 SDK**
- **iOS 17.0+** device or simulator
- An **Anthropic API key** (for essay grading and optional MC reasoning grading)

## Open the project

1. Clone or copy this repo to your Mac.
2. Open `CFAL3.xcodeproj` in Xcode.
3. Select the **CFAL3** scheme and your target device.

## Signing & bundle identifier

1. Select the **CFAL3** project in the navigator → **CFAL3** target → **Signing & Capabilities**.
2. Set **Team** to your Apple ID (Personal Team works for sideloading).
3. Change **Bundle Identifier** if needed (default: `com.brandonkeeny.CFAL3`).
4. Repeat for **CFAL3Tests** if you run unit tests on device.

## Install on your iPhone (free 7-day provisioning)

1. Connect your iPhone and trust the computer.
2. Choose your iPhone as the run destination.
3. Press **Run** (⌘R). Xcode builds, signs, and installs the app.
4. On first launch, if iOS blocks the app: **Settings → General → VPN & Device Management** → trust your developer certificate.

**Note:** Free Apple ID provisioning expires every **7 days**. Re-run from Xcode to reinstall/re-sign. A paid Apple Developer Program membership gives **1-year** signing certificates.

## Anthropic API key

1. Launch the app → **Home** → **Settings** (or open Settings from Home).
2. Tap **Update API key** and paste your key (`sk-ant-…`).
3. The key is stored in the **Keychain** on-device only.

Grading calls go **only** to `api.anthropic.com`. Browsing questions and tracking progress work offline; grading requires network access.

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

- **Study notes** — all **25 readings** (`CFA_L3_Notes_R01–R25.docx`) bundled as `reading_notes.json`
- **LOS checklist** — all **237 LOS** with tap-to-mark progress
- **Practice questions** — filtered by reading/LOS from the question bank

Readings **without** bundled notes: Ethics (no reading in curriculum JSON), Endowment case study (no R26 notes file yet).

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
