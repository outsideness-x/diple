# diple. — Mac App Store submission

Written 2026-09-06, against the working tree at `dev/diple/diple` (branch `main`).
The iOS version of this same app record was submitted on 2026-08-29; this document covers
**only what is different for macOS**, and every step below has been carried as far as this
machine allows. Where a step could not be executed here, it says so and says why.

The macOS build is the **Mac Catalyst** variant of the same target — same bundle ID, same
database, same Readium engine. It is not a separate app and it does not get a separate App
Store Connect record.

---

## 0. The one thing that blocks the release, and it is not macOS

**The CloudKit Production schema is out of date.** `DipleHighlight` gained `tags` (STRING LIST)
and `tagsCount` (INT64) when passages got tags; neither field exists in the schema deployed for
v1.0. `tagsCount` is written on **every** highlight save, not only a tagged one, so against the
current Production schema CloudKit rejects the whole record — that is not "tags don't sync", it
is "passages stop syncing", silently, with nothing but `Needs Attention` in Settings to show for
it. See the note in `CLAUDE.md` under *Теги цитаты*.

Deploy it from the CloudKit Console (Development → Production) **before** submitting anything,
iOS or macOS. In Development a field is only created once a value of that type has actually been
written, so exercise the path by hand first: save a passage, add a tag to it, then check that
`tags` and `tagsCount` exist on `DipleHighlight` in the Development schema before promoting.

---

## 1. What changed in the app for macOS

All of this is committed on `main`.

| Change | Why it was needed |
|---|---|
| **App Sandbox** (`diple/diple-macos.entitlements`) | Mandatory for the Mac App Store, meaningless on iOS. Absent before; the upload would have been rejected at validation. |
| `com.apple.security.files.user-selected.read-write` | The file importer reads a publication; Settings *writes* a backup and a Markdown library into a folder the reader picks. Read-only would have failed the second pair at the moment of writing. |
| `com.apple.security.network.client` | Article import and CloudKit transport. No local server is run — Readium 3 serves EPUB resources through a `WKURLSchemeHandler`, in-process, so `network.server` is deliberately **not** declared. |
| **Team-prefixed App Group** | macOS requires an App Group identifier to begin with the team ID. Asking for the bare iOS name returns `nil` from `containerURL(forSecurityApplicationGroupIdentifier:)` — silently. The Share Extension queue and the widget snapshot had never worked on the Mac. Both names are declared; `SharedLinkInbox.appGroupIdentifier` prefers the prefixed one. |
| **macOS app icon ladder** (`Scripts/generate_mac_icon.py`) | The set carried one iOS 1024 image. macOS masks nothing, so that lands in the Dock as a hard-cornered square; and without a 512 pt @2x rung the compiled catalog has no 1024 px representation at all. |
| `NSHumanReadableCopyright` | Printed in the About box and Finder's Get Info. The app had none. |
| Desktop UI work | Menu bar, keyboard, column headers, selection and hover — see the four commits from `a6600da` onward. Not a store requirement, but this is the build that gets reviewed. |

Everything the iOS readiness report verified still holds and is not re-checked here:
no tracking SDKs, no StoreKit, clean ATS, font licences shipped, `ITSAppUsesNonExemptEncryption`
baked into the build. See `app-store/readiness-report.md`.

---

## 2. What was verified on this machine

- `xcodebuild -destination 'platform=macOS,variant=Mac Catalyst' -allowProvisioningUpdates build`
  **succeeds and signs**, and Xcode created Mac Catalyst provisioning profiles for all three
  bundle IDs (`com.chemical-pink.diple`, `.ShareExtension`, `.Widget`). The provisioning failure
  recorded in earlier notes is gone.
- The signed app's applied entitlements were read back with `codesign -d --entitlements -`:
  sandbox on, both App Group names present, `$(TeamIdentifierPrefix)` expanded to
  `KX98K6BPAP.`.
- Both group containers exist on disk after a launch
  (`~/Library/Group Containers/KX98K6BPAP.group.com.chemical-pink.diple` and the bare one).
- A **Release archive** builds clean: universal `x86_64 arm64`, `LSMinimumSystemVersion 15.0`,
  `LSApplicationCategoryType public.app-category.books`, copyright present, both extensions
  embedded in `Contents/PlugIns`, privacy manifest present, no `.entitlements` leaking into
  `Resources`.
- The app runs sandboxed: the library opens, and **a book renders** — two-column spread, math,
  code blocks, progress line. This is the check that would have caught a missing
  `network.server`, and it passed without one.

## 3. What could not be verified here, and what to do about it

- **No distribution certificate exists in this keychain** — `security find-identity -v -p
  codesigning` returns one identity, `Apple Development`. The Distribute flow in step 5 creates
  the `Apple Distribution` certificate itself; that is the intended path and needs no manual
  work, but it is why no upload was attempted from here.
- **Nothing was uploaded**, so App Store Connect has never seen a macOS build of this record and
  the platform section may not exist yet. Step 6 covers both cases.
- The **generated `.icns`** carries four rungs (16, 32, 128, 512), which is what `actool` emits
  for every Mac Catalyst target regardless of what the set contains — the compiled `Assets.car`
  does carry the full ladder up to 1024, verified with `assetutil`. If validation ever complains
  about a missing icon, that is the place to look, not the asset set.

---

## 4. Before you open Xcode

1. **Deploy the CloudKit Production schema** (section 0). Nothing else matters until this is done.
2. Confirm you are signed into Xcode with the account for team `KX98K6BPAP`
   (Xcode → Settings → Accounts).
3. Decide the build number. macOS and iOS have **separate build-number namespaces** in App Store
   Connect, so `CURRENT_PROJECT_VERSION = 1` is free for the first macOS upload even though iOS
   shipped build 1. If App Store Connect refuses it, bump `CURRENT_PROJECT_VERSION` in
   `project.pbxproj` (both configurations) and archive again — never reuse a build number.
4. `MARKETING_VERSION` stays `1.0`. Same version string as iOS is fine and is what you want.

---

## 5. Archive and upload

1. Open `diple.xcodeproj`.
2. Scheme **diple**. Run destination: **My Mac (Mac Catalyst)** — not "Any Mac", not a simulator.
   The destination is what decides which platform Archive produces; this is the step people get
   wrong.
3. **Product → Archive.** It builds Release, universal. Expect a few minutes.
4. In the Organizer window that opens, select the new archive and check the header says
   **macOS** before going further.
5. **Distribute App → App Store Connect → Upload.**
   - Leave **Upload your app's symbols** on.
   - Leave **Manage Version and Build Number** *off* — you set the build number deliberately in
     step 4 above, and letting Xcode change it silently makes the archive and the repo disagree.
   - Signing: **Automatically manage signing**. This is where Xcode creates the `Apple
     Distribution` certificate and the App Store provisioning profiles for all three bundle IDs.
     Approve the prompts.
6. Xcode validates before uploading. If validation fails, it names the bundle and the key; fix it
   in the project and archive again — do not hand-edit anything inside the `.xcarchive`.
7. Upload finishes with **Upload Successful**. Processing on Apple's side takes 15–60 minutes;
   you get an email when the build is ready, and the build appears greyed out in App Store
   Connect until then.

---

## 6. App Store Connect

App record: **`diple.`**, Apple ID **6806528966**, SKU `com.chemical-pink.diple`.

### 6a. Make the macOS platform exist

For a Mac Catalyst app sharing the iOS bundle ID, the macOS section normally appears on its own
once a macOS build finishes processing. Open the app record and look at the left sidebar:

- If **macOS App** is already listed — good, go to 6b.
- If it is not, use the **+** beside the platform list at the top of the sidebar and add
  **macOS**. If the option is missing entirely, the build has not finished processing yet; wait
  for the email and reload.

### 6b. Fill in the macOS version

Most metadata is per-platform, so it does **not** inherit from iOS and has to be entered again.
The iOS copy is in `/Users/chemical_pink/dev/diple/app-store/metadata-en.md` — reuse it verbatim
except where noted.

| Field | What to use |
|---|---|
| Screenshots | `app-store/mac-screenshots/` — four 2880×1800 PNGs (library, reader, highlights, notes). Apple accepts 1280×800, 1440×900, 2560×1600 or 2880×1800; at least one, up to ten. |
| Promotional text / Description / Keywords | From `metadata-en.md`. **Change any "iPhone" wording** — the description should describe a desktop reader. |
| Support URL / Marketing URL | `https://diple-reader.vercel.app` |
| Copyright | `2026 chemical_pink` (matches `NSHumanReadableCopyright` in the build) |
| Category | Primary **Books**. Matches `LSApplicationCategoryType` in the build; a mismatch is a review question. |
| Age rating | Same answers as iOS → 4+ |
| App Privacy | Shared across platforms — already answered for iOS, nothing to do |
| Pricing & Availability | Shared across platforms — free, already set |
| Review notes | From `paste-review-notes.txt`, plus one macOS line: iCloud sync is **off by default** and lives in Settings; a reviewer who wants to see it must turn it on. |
| Build | Select the processed macOS build once it appears |

### 6c. Export compliance

`ITSAppUsesNonExemptEncryption = false` is baked into the build, so no "Missing Compliance" hold
appears and there is nothing to answer. This is deliberate even though CryptoSwift is linked
transitively through Readium — ReadiumLCP is not linked, so no DRM crypto ships.

### 6d. Submit

**Add for Review → Submit to App Review.** Answer "no" to advertising identifier.

---

## 7. Worth doing before you submit

**Install the build from TestFlight for macOS.** Internal testers get it with no review, and it
is the only cheap way to check two things that a locally-signed build cannot answer:

1. That a **distribution-signed** app can actually read and write through the *Production*
   CloudKit schema. The schema is proven correct; this pairing is not.
2. That the export rewrote `aps-environment` to `production` —
   `codesign -d --entitlements - /Applications/diple.app` on the installed copy.

Both are carried over from the iOS submission as still-unverified; the macOS build is the second
chance to close them.

---

## 8. If review comes back

The two things most likely to be asked about a Catalyst app on this store:

- **"What is this app for on the Mac?"** — the description is the answer, so make sure it is not
  the iPhone one. Reviewers do read it against the screenshots.
- **iCloud sync appearing not to work.** It is off by default, on purpose (`CloudSyncService
  .isEnabled` is a device-local `UserDefaults` flag, not a synced setting). Say so in the review
  notes rather than waiting to be asked.
