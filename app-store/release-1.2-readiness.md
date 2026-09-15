# diple. 1.2 — release readiness (iOS + macOS)

Audited 2026-09-14 against `main` at `5a245d4`. Method as in `readiness-report.md`: build real
Release archives and inspect the products, run the unit tests, then walk the built app. Read that
report first — what it verified (no tracking SDKs, ATS, font licences, export compliance) is not
repeated here unless it changed.

**Verdict: the build is ready; the release is not.** Nothing in the code blocks 1.2. The CloudKit
Production schema did, and was deployed on 2026-09-15 (below); what remains is a distribution
certificate and a handful of paths that have never been touched by a human hand.

---

## Fixed in this pass

**Version was still `1.0 (1)` on every target.** Now `1.2 (2)` (`20a5660`). Both extensions read
`$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`, verified in the archived `.appex` plists. If
App Store Connect already holds a 1.2 build 2 from somewhere, bump the build number again.

---

## Verified good

| Area | State |
|---|---|
| iOS Release archive | `ARCHIVE SUCCEEDED`, unsigned. arm64, `MinimumOSVersion 18.0`, `iphoneos26.2` SDK, Xcode 26.3 |
| Devices | `UIDeviceFamily [1]` on the app **and** both extensions |
| Mac Release archive | `ARCHIVE SUCCEEDED`, signed (development). Universal `x86_64 arm64`, `LSMinimumSystemVersion 15.0`, `public.app-category.books`, both extensions embedded |
| Mac entitlements | Sandbox, both App Group names, `files.user-selected.read-write`, `network.client` — read back with `codesign -d --entitlements -` |
| Icons | Mynerve sets, every 1024 RGB without alpha; macOS ladder regenerated with the icon (512@2x present); `AppIconMynerve.icns` in the Mac bundle |
| Privacy manifest | The app binary links `NSUserDefaults`, `NSFileCreationDate`/`NSFileModificationDate` and `lstat` — all inside the two declared categories. **Neither extension links any required-reason API** (checked with `nm -u`), so they need no manifest of their own |
| Usage descriptions | None needed: the cover picker is `PhotosPicker`, which runs out of process |
| App Intents | `Metadata.appintents` written for the app and the widget extension. The share extension's "Metadata extraction skipped" warning is correct — it has no intents |
| Share extension | Activation rule accepts text, one URL and one web page — the text path is the new "share words into the Inbox" |
| Export compliance | `ITSAppUsesNonExemptEncryption = false` in both builds |
| Strings | English only, 471 keys, none stale |
| Unit tests | 362 in `dipleTests`: the full run gave 361 passed and 1 failed under an `en_US` simulator; that one passes with the simulator's default locale (the whole `MarginaliaTests` class re-run: 39/39). See the note below |
| Compiler | 18 warnings, all Swift 6 actor-isolation notices; none is an error in the Swift 5 mode the project builds in |

**One test is locale-bound.** `MarginaliaTests.testAnUnnarrowedCollectionIsNamedByItsDate` expects
`"Collected 15 Jan 2027"` and fails on a simulator set to `en_US` (`"Collected Jan 15, 2027"`). The
app is right to follow the reader's locale; the test is not pinning one. It passes on the default
simulator locale, which is how it has always been run. UI tests were not run in this pass.

---

## Blockers — cannot be done from this machine

**1. CloudKit Production schema — deployed 2026-09-15.** Alex deployed it from the Console. The
Production export read back afterwards is **byte-identical** to `app-store/cloudkit-schema-1.2.ckdb`,
and the deploy diff was additions only (24 lines, no removals, no type changes). Whether a
distribution-signed build actually saves through it is still the first TestFlight check below.
What it needed, kept for the record:

- `DipleHighlight`: `tags` LIST&lt;STRING&gt;, `tagsCount` INT64 — `tagsCount` is written on every highlight save;
- `DipleSpace`: the whole record type (`name`, `symbol`, `sortIndex` DOUBLE, `createdAt`, `updatedAt`, `modifiedAt`);
- `DipleNote`: `spaceID`, `pinnedAt`, `trashedAt`, `dailyDate` (STRING).

Types and the exact procedure are in `readiness-report.md` → *CloudKit Console*. Without the deploy a
TestFlight or App Store build silently parks every highlight and every note in the outbox. `cktool`
has no management token on this Mac; the schema was read through Console exports pasted by hand.
**The next schema change starts from `cloudkit-schema-1.2.ckdb`**: add to that file, import it into
Development, deploy, and diff the Production export against it.

**2. No Apple Distribution certificate** in this keychain. Xcode's Distribute flow creates it; it
is why both archives above are unsigned / development-signed.

---

## Test on TestFlight before submitting

None of these can be exercised by a simulator or by the window-photograph harness, and the
What's New text promises most of them:

1. **Sync through Production with a distribution-signed build** — open since 1.0. Two devices, one
   Apple ID: a tagged highlight, a note moved into a space, a pinned note, a deleted note, today's page.
2. `codesign -d --entitlements -` on the exported app reads `aps-environment` **production**.
3. **Korean (Hangul) typing** in the live-Markdown note editor.
4. **Siri / Shortcuts** — New Note and Add to Today.
5. **Control Center** New Note control and the **Notes widget**.
6. **Mac input**: dragging a note onto a space, ⌘N, ⌘8, ⌥⌘I, right-click row menus.

---

## Open, not blocking

- **GRDB still tracks `branch: master`** (revision `b83108d1`) — the storage layer on a moving target.
  `Package.resolved` holds the revision, so a normal build is reproducible; a re-resolve is not.
- **The marketing site is stale**: "iPhone · iPad · Mac", "App Store Soon", "Ink / Brass", and no
  word of Notes. The listing is iPhone + Mac.
- **Copyright disagrees**: the Mac build's `NSHumanReadableCopyright` says "© 2026 chemical_pink",
  while the iOS listing was filed as "2026 Aliaksei Krauchanka". Pick one before the Mac listing.
- `FirstLaunchView.isForcedForTesting` still reads a launch argument outside `#if DEBUG`
  (item 8 of the 1.0 report). Harmless.

---

## Prepared, outside the repo

`/Users/chemical_pink/dev/diple/app-store/1.2/`:

- `ios-6.9in-dark/`, `ios-6.9in-paper/` — eight 1320×2868 frames each;
- `mac-dark/`, `mac-paper/` — five 2880×1800 frames each;
- `raw/` — the untouched captures; `tools/` — the seed and render scripts;
- `metadata-1.2.md` — What's New (iOS and macOS), promotional text, keywords, description
  insert, captions and a review-notes paragraph.

The Mac reader is not among the frames: the window-photograph harness cannot see a `WKWebView`
(see CLAUDE.md, *Мастерская заметок на Mac*).
