# diple. 1.2 — release readiness (iOS)

Written 2026-11-06 against `main` at `9261eea`. Read `release-1.1-readiness.md` first: what it
verified (archives, devices, icons, privacy manifest, export compliance) still holds and is not
repeated here.

**State: `1.2 (3)` is uploaded to App Store Connect (2026-11-06 18:19, "Upload succeeded",
processing). It is not submitted for review.** What remains is App Store Connect itself: the copy,
the screenshots and the submission, with Alex's go-ahead on the text — see the end of this file.


**1.1 shipped on 2026-09-16** (build 2, with the Notes mode — its copy is in
`/Users/chemical_pink/dev/diple/app-store/1.1/`). This release is **1.2**. The September verdict
still holds for the code; what changed is what the app is. The Notes mode it was
audited with was withdrawn on 2026-09-27, the RSS feed (2026-10-21) was withdrawn on 2026-11-06, and
a polish round landed the same day (see CLAUDE.md, «Шрифт читалки», «Поиск внутри открытой книги»,
«Полнотекстовый поиск по книгам»; the page is now set in Literata).

- **Version `1.2 (3)`.** Two uploads were refused on the way: `1.1 (2)` ("the bundle version must be
  higher than the previously uploaded version") and `1.1 (3)` ("the train version '1.1' is closed" —
  1.1 is approved and live). Distribution signing works through Xcode's cloud-managed certificate:
  no `Apple Distribution` identity is needed in this keychain.
- **CloudKit Production needs nothing.** `cloudkit-schema-1.1.ckdb` and the sync code are unchanged
  since the 2026-09-15 deploy; `DipleFeedSource` never reached Production and is gone from the file.
- **Unit tests:** 375 in `dipleTests`, one failure — the locale-bound
  `MarginaliaTests.testAnUnnarrowedCollectionIsNamedByItsDate` on an `en_US` simulator, as before.
- **Both platforms build** (iOS Simulator and Mac Catalyst).
- **Migrations v22 and v23** run on the first launch of 1.2: v22 drops the feed's table and file,
  v23 drops the derived book-text index, which the search root rebuilds on the same launch —
  reading estimates are missing for the first minute or so and then come back, correct.
- **App Store copy and screenshots** are outside the repo, in
  `/Users/chemical_pink/dev/diple/app-store/1.2/`: `metadata-1.2.md` (What's New written against the
  live 1.1, which has the Notes mode), `paste-review-notes*.txt`, and the seven cards in `ios-6.9in/`.

### The TestFlight checks, revised

The list above was written for the Notes mode; three of its six items no longer exist (Siri and
Shortcuts actions, the Control Center control and the Notes widget, spaces and today's page). What
is left to touch by hand on a distribution build:

1. **Sync through Production** — two devices, one Apple ID: a tagged passage, a note linked to a
   book, a deleted note.
2. `codesign -d --entitlements -` on the exported app reads `aps-environment` **production**.
3. **Korean (Hangul) typing** in the live-Markdown note editor, and a Korean book on the Literata
   page (Hangul from the New York guard, Apple SD Gothic Neo).
4. **Language learning** on a device: a tap on a sentence opens the system translator.
5. **Mac input**: ⌘N, ⌘K, ⌥⌘I, right-click row menus.


### What is left, in App Store Connect

1. Wait for the build to finish processing (an email arrives), then create version **1.2** for iOS
   and select build **3**.
2. Paste from `/Users/chemical_pink/dev/diple/app-store/1.2/metadata-1.2.md`: What's New, the
   promotional text, keywords and the description (the live description and promotional text still
   promise daily pages and five accents).
3. Replace all six live screenshots with the seven cards in `app-store/1.2/ios-6.9in/`.
4. Review notes: `app-store/1.2/paste-review-notes.txt`. Sign-in required: no.
5. Submit for review.

The Mac build is not part of 1.2: it needs manual Mac App Store profiles first
(`mac-app-store-submission.md` §4a).
