# diple. — App Store readiness report

Audited 2026-08-26 against the working tree at `dev/diple/diple` (branch `main`).
Method: read the project configuration, then built a real unsigned **Release archive**
(`** ARCHIVE SUCCEEDED **`) and inspected the finished `.app` — merged `Info.plist`,
`UIDeviceFamily`, icons, privacy manifests, bundled resources, and the linked binary's
required-reason API symbols. Then installed on an **iPad Pro 13-inch (M5)** simulator with a
real library and walked the app to settle the iPad question. Findings are about the built
product, not the source.

---

## Verified good

| Area | State |
|---|---|
| Release archive | Builds clean, `arm64`, `MinimumOSVersion 18.0`, iOS 26.2 SDK (Xcode 26.3) |
| App icon | 1024×1024, **no alpha channel**, dark + tinted variants; four alternates all correct |
| Export compliance | `ITSAppUsesNonExemptEncryption = false` baked into the build; no "Missing Compliance" hold |
| Privacy manifest | Present, and now covers the file-timestamp APIs the binary actually links (see Fixed) |
| Tracking / IDFA | None. No analytics or crash SDK, no `identifierForVendor`, no `ATTrackingManager` |
| StoreKit | None — free app, no IAP, matching the site's "no subscription, no paid tier" |
| ATS | No arbitrary-loads exception, and pasted `http://` links are upgraded to `https://` before use |
| Font licences | All three OFL texts ship inside the `.app` alongside the fonts |
| Background mode | `remote-notification` is genuinely required by `CKSyncEngine`; not a phantom declaration |
| Age rating | No in-app browser (no `SFSafariViewController`), no shared UGC → clean 4+ |
| Placeholders | No TODO / FIXME / lorem / localhost / example.com anywhere in shipping source |
| Provisioning | Development profiles exist for both bundle IDs with iCloud, App Group and push |

---

## Fixed in this pass

**1. Privacy Policy link now points at the site.**
`diple/View/AppSettingsView.swift:7` pointed at
`github.com/outsideness-x/diple/blob/main/README.md`. It now points at
`https://diple-reader.vercel.app/privacy` (verified live, HTTP 200). That was the only
occurrence in the app.

**2. Privacy manifest was under-declaring an API category.**
The linked binary references `NSFileCreationDate` / `NSFileModificationDate` — the
`NSPrivacyAccessedAPICategoryFileTimestamp` required-reason category — but
`diple/PrivacyInfo.xcprivacy` declared only `UserDefaults`. The usage comes from
ZIPFoundation, which is *statically linked into the app binary*; its own manifest travels
in a nested resource bundle, which is not a dependable answer for Apple's scanner. Left
alone this is the classic **ITMS-91053 "Missing API declaration"** rejection email. The
manifest now declares the category with `C617.1` (files in the app container) and `3B52.1`
(files the reader picked in the document browser) — both true of the app in its own right.
Verified present in the rebuilt archive.

**3. App and share extension now agree on devices — iPhone only.**
`TARGETED_DEVICE_FAMILY` was `1` on the app while the share extension declared `1,2`. An
extension advertising a device family its container does not support is an inconsistency
App Store validation can reject on. iPad was considered and dropped (see below), so the fix
went the other way: the extension is now `1` as well. Verified in a rebuilt archive — app and
`.appex` both report `UIDeviceFamily [1]`.

---

## Why iPad was dropped

The app was briefly set to `"1,2"` and walked on an iPad Pro 13-inch simulator with a real
library. Screenshots are in `app-store/ipad-audit/`. What that showed:

**The reader is genuinely iPad-native and would have needed nothing.** Readium lays the page
out as a real two-column spread at 13", with proper measure (~60 characters a column),
highlights rendering correctly and the living-margin dipla in the outer margin.

**The three shell screens are stretched iPhone layouts, and that is a Guideline 2.4.1 risk.**

- **Home** — the three capture buttons stretch to ~470 pt each around a small centred label.
  Note previews run the full 1032 pt width, roughly 180 characters a line, which the project's
  own typographic rule (65–75) rejects everywhere else. The bottom third is empty.
- **Library** — rows have a small cover at the far left and a wide empty right side; the
  Inbox / Later / Archive segments and the progress rules span the whole width.
- **Empty library** — worst case. Masthead in the top-left corner, three enormous buttons, one
  card at two-thirds width, and roughly 80% of the screen black. This is what a reviewer opening
  a fresh install on an iPad would have seen first.

Shipping that is the "iPhone app blown up" shape Apple names in 2.4.1, and fixing it properly
is real work: there is already a three-column layout in `View/Mac/MacRootView.swift`, but
`dipleApp.swift` gates it on `#if targetEnvironment(macCatalyst)`, so iPad falls through to
`phoneRoot`. Driving that layout from the horizontal size class instead is the route whenever
iPad is picked up again. It would also have required a second screenshot set (2064 × 2752).

**One consequence for the listing:** the marketing site says "iPhone · iPad · Mac". The App
Store listing will say iPhone. Soften the site's device line before launch so the two agree.

---

## Still to decide or check

**4. The Mac Catalyst provisioning profile is missing the App Group.**
`Mac Catalyst Team Provisioning Profile: com.chemical-pink.diple` carries iCloud and push but
no `com.apple.security.application-groups`. A Catalyst build embedding the share extension will
fail to sign. Irrelevant to the iOS submission; blocking whenever Mac ships.

**5. `aps-environment` is `development` in `diple/diple.entitlements`.**
Xcode rewrites this to `production` when it re-signs for App Store distribution, so this
normally sorts itself out. Worth *checking* rather than trusting: after exporting, run
`codesign -d --entitlements - path/to/diple.app` and confirm it reads `production`. A build
shipping the development value gets no production pushes, which here means silent CloudKit
sync quietly not arriving.

**6. GRDB is pinned to a moving branch.**
`Package.resolved` has `grdb.swift` on `branch: master` (revision `b83108d1`) while every other
dependency is on a version tag. A resolve on another machine, or a clean CI checkout, can pull a
different GRDB than the one you tested against — under the app's own storage layer. Pin it to a
released version before the release build.

**7. No Apple Distribution certificate on this Mac.**
The keychain has only `Apple Development: Aliaksei Krauchanka`. Xcode creates the distribution
certificate the first time you run Organizer → Distribute App with automatic signing; just know
that step is still ahead of you, and it is why the archive above was built unsigned.

**8. `FirstLaunchView.swift:25` ships a test hook in Release.**
`isForcedForTesting` reads `-diple-test-first-launch` with no `#if DEBUG` around it, unlike the
two fixtures in `dipleApp.swift`, which are guarded. No user can pass a launch argument to an
App Store build, so this is not a security or review problem — it is dead weight and an
inconsistency the next fixture will copy.

**9. The privacy policy now exists in two places.**
`README.md` still holds the full policy text, and the app now links to the website copy. Two
copies drift. Cut the README down to a pointer at `https://diple-reader.vercel.app/privacy`
and let the site be canonical.

**10. There is no `/support` page.**
App Store Connect requires a Support URL. `https://diple-reader.vercel.app/` returns 200 and
carries a contact address, so it will pass — but a reviewer landing on a marketing page looking
for help is a weaker answer than a page that says how to get it.

---

## Submitted — Saturday 2026-08-29

The App Store Connect record exists: Apple ID **6806528966**, name `diple.`, SKU
`com.chemical-pink.diple`, primary language English (U.S.), categories Books / Productivity,
free in all territories, age rating 4+, App Privacy answered **Data Not Collected**, content
rights answered **No**.

Xcode's own "create the app record" step failed first with
`IDEDistribution.DistributionAppRecordProviderError error 0`, which swallows the real reason.
Creating the record by hand in App Store Connect got past it. Worth remembering for the next
app: when that dialog errors, go make the record in ASC, where the error message is real.

URLs as filed:

| Field | Value |
|---|---|
| Support | `https://diple-reader.vercel.app/privacy#contact` |
| Marketing | `https://diple-reader.vercel.app/` |
| Privacy Policy | `https://diple-reader.vercel.app/privacy` |

The support URL carries the anchor deliberately: the contact block lives on the privacy page,
not on the root, and the anchor lands the reader on it instead of leaving them to scroll a
legal document. Replace it if a real `/support` page is ever built.

**CloudKit schema is deployed to Production.** Development was completed first by exercising
the app (tagging a book, tagging a note, linking a note to a book, adding a bookmark — the four
paths that had never run), and the dead `DipleHighlightReview` record type, left over from the
v12/v13 spaced-repetition feature, was deleted from Development *before* the deploy so it would
not land in Production permanently. The deploy diff was pure addition: no line was removed, and
`Users` was the only type Production already held. The `recordName` QUERYABLE indexes were
deliberately skipped — they are only needed for the Console's own record browser, and adding
them later is an ordinary additive deploy.

**Two things were never verified and should be, before this build reaches anyone:**

1. **Production CloudKit sync on a real build.** Everything above proves the *schema* is right;
   nothing yet proves a distribution-signed build can actually save through it. The submitted
   build is already installable from TestFlight for internal testers with no review, so this can
   be checked right now, in parallel with review: two devices on one Apple ID, sync on, then a
   book with a cover, a highlight with a comment, a bookmark, a tag, a note linked to a book,
   and a link shared from Safari through the "Save to diple" extension. Watch for `Up to Date`
   rather than `Needs Attention` — a missing field does not crash the app, it silently parks the
   record in the outbox.
2. **`aps-environment` in the exported build.** Still unchecked:
   `codesign -d --entitlements - <exported>/Payload/diple.app` must read `production`. If it
   reads `development`, silent CloudKit pushes never arrive and sync only catches up on launch.

---

## CloudKit Console — what has to happen before the release build

This is a hard blocker that nothing in the build can warn you about. **A TestFlight or App
Store build talks to the CloudKit *Production* environment. Only Xcode-installed builds talk to
Development.** Production schema is read-only to the app: it can write records, but it cannot
create a record type or a field that is not already there. Anything the Development schema does
not carry at deploy time simply fails forever in production.

Container `iCloud.com.chemical-pink.diple`, private database, custom zone `Diple`
(`CloudSyncService.zoneName` — the app creates the zone itself at runtime, so nothing to do
there).

**Step 1 — make the Development schema complete before deploying.** The schema is grown
implicitly: a field springs into existence the first time a record carrying it is saved. A field
you never exercised on a dev device does not exist, so it will not deploy. The full set the code
can write:

| Record type | Fields |
|---|---|
| `DipleBook` | `title`, `author`, `fileName`, `coverFileName`, `addedAt`, `lastOpenedAt`, `progress`, `furthestProgress`, `locator`, `sourceURL`, `sourceKind`, `location`, `tags` (STRING LIST), `tagsCount` (INT64), `modifiedAt` |
| `DipleBookAsset` | `publication` (ASSET), `fileName`, `cover` (ASSET), `coverFileName`, `modifiedAt` |
| `DipleHighlight` | `bookID`, `locator`, `text`, `comment`, `colorHex`, `createdAt`, `bookTitle`, `bookAuthor`, **`tags` (STRING LIST)**, **`tagsCount` (INT64)**, `modifiedAt` |
| `DipleBookmark` | `bookID`, `locator`, `name`, `colorHex`, `createdAt`, `modifiedAt` |
| `DipleNote` | `title`, `body`, `bookID`, `createdAt`, `updatedAt`, `tags` (STRING LIST), `tagsCount` (INT64), `modifiedAt` |
| `DipleSettings` | `payload` (BYTES), `modifiedAt` |

Open Schema → Record Types in the Console and check every row against this table. The ones most
likely to be missing are the rare paths: `tags` / `tagsCount` (a book or note has to have been
tagged — and note that `tags` is written *only when non-empty*, precisely because an empty list
has no element type for CloudKit to infer from, see the comment on `CloudSyncService.write(tags:to:)`),
`comment` on a highlight, `bookTitle` / `bookAuthor` (only written once a book is renamed or
deleted), `sourceURL` (an imported article), `cover` / `coverFileName`, and `location` other
than the default. Either exercise each one on a dev device, or add the missing field by hand in
the Console with the type from the table above.

> **New since the v1.0 deploy, and a hard blocker for the next release:** `DipleHighlight` gained
> `tags` and `tagsCount` when passages became taggable. The Production schema deployed on
> 2026-08-29 does **not** carry them, and `tagsCount` is written on **every** highlight save —
> not only on tagged ones. Until these two fields are deployed, a TestFlight or App Store build
> has every highlight record refused and parked in the outbox: not "tags do not sync" but
> "highlights stop syncing", with no crash and no message beyond `Needs Attention` in Settings.
>
> Creating them in Development needs one specific action, because `tags` is written only when it
> is non-empty (an empty list has no element type for CloudKit to infer): **save a highlight with
> at least one tag** on an Xcode-installed build with sync on. Any highlight save creates
> `tagsCount`; only a tagged one creates `tags`. Adding both by hand in the Console with the
> types above works too.
>
> Nothing else added since v1.0 touches the schema: the fore-edge, the ink stroke, the widget,
> the Markdown export, the passage echoes and the Kindle/Readwise import are all local, and
> imported passages are ordinary `DipleHighlight` rows.

**Step 2 — Deploy Schema Changes to Production.** Schema → "Deploy Schema Changes…", review the
diff, deploy.

**Get the types right the first time.** A deploy to Production is one-way: after it, a field's
type can never be changed and no field or record type can ever be removed. Only additions are
possible. A `tags` field that lands in Production as the wrong type is permanent.

**Optional but worth it:** add a QUERYABLE index on `recordName` for each record type. Sync
itself does not need it — `CKSyncEngine` works from zone change tokens, not queries — but
without it the Console's own record browser cannot list anything, which is the difference
between debugging a production sync complaint and guessing at it.

**Nothing else needs doing there.** The private database's default security roles are correct,
and `CKSyncEngine` creates its own subscription, so there is no subscription to set up by hand.

---

## Prepared for you

The App Store Connect copy — name, subtitle, promotional text, keywords, full description,
URLs, copyright, categories, age-rating answers, privacy nutrition-label answer, review notes,
and a screenshot order with captions — is prepared and every length-limited field is within
Apple's limit. It is deliberately **not** in this repository: it lives beside the screenshots in
the working directory above the checkout, as `app-store/metadata-en.md`.
