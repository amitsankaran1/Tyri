# TestFlight

Project reference and review screenshots: [Tyri in Notion](https://app.notion.com/p/2e616e0e0e3a80148841ff8ca2cb3647).

Version **2.3 (3)** uploaded successfully on October 29, 2026. Apple reported that the package was processing; processing completion and tester-group assignment have not been verified. The [upload receipt](builds/2.3-3.json) records the archived source revision, package hash, and verified distribution entitlements.

Version **2.3 (4)** uploaded successfully on October 30, 2026 as a candidate fix for scheduled blocks failing to shield selected apps. Apple reported processing. Physical-device enforcement, processing completion, and tester-group availability are not yet verified. See the [issue report](../docs/issues/2026-10-30-overnight-schedule.md) and [release receipt](builds/2.3-4.json). Source revision: `5460c75`.

Version **2.3 (5)** uploaded successfully on October 30, 2026. This combined candidate includes build 4's schedule recovery plus simpler scheduling, Schedule-first creation, and clearer Stop early / Take a break settings. Source: `b32f561`. Apple reported processing; physical shielding and tester availability remain unverified. Four UI scenarios passed across the full run and the corrected focused scheduling rerun. [Release receipt](builds/2.3-5.json) · [UX changes](../docs/issues/2026-10-30-scheduling-ux.md). The Tyri Notion page includes four latest screenshots and preserves 21 previous images under a versioned toggle.

## Prepare and upload

1. Sign into the existing developer account in Xcode → Settings → Apple Accounts. Unlock the Mac's login keychain and approve signing prompts locally. Do not put passwords or verification codes in shell arguments or project files.
2. In [Tyri's App Store Connect record](https://appstoreconnect.apple.com/apps/6757515805), open TestFlight and check the latest uploaded version/build. The candidate documented here is **2.3 (3)**, after Apple rejected the closed 2.2 release train. For each future upload, choose an unused version/build and update both Tyri and TyriMonitor together. The commands below use this candidate's archive name; use a fresh path and number for a new candidate.
3. From the repository root, make a signed Release archive. Use a new archive path for each attempt; an archive explicitly labeled unsigned is only a compilation check.

   ```sh
   xcodebuild -project Tyri.xcodeproj -scheme Tyri \
     -configuration Release -destination 'generic/platform=iOS' \
     -archivePath "$HOME/Library/Developer/Xcode/Archives/Tyri-2.3-3.xcarchive" \
     -allowProvisioningUpdates archive
   ```

4. Upload the signed archive. This command sends the build to Apple; it does not publish an App Store release. Build-number management is disabled in the export settings to keep the uploaded number tied to the source revision.

   ```sh
   xcodebuild -exportArchive \
     -archivePath "$HOME/Library/Developer/Xcode/Archives/Tyri-2.3-3.xcarchive" \
     -exportPath /tmp/tyri-testflight-upload \
     -exportOptionsPlist release/ExportOptions.plist \
     -allowProvisioningUpdates
   ```

   Alternatively, open the signed archive in Xcode's Organizer and choose Distribute App → App Store Connect → Upload. Keep external TestFlight distribution available if friends will test it.

5. Wait for processing in App Store Connect → app → TestFlight. Resolve any export-compliance or test-information requirements accurately. Upload success alone does not mean the build is available to testers. Confirm its version/build, status, expiry, and group assignment.
6. Use [WhatToTest.txt](WhatToTest.txt) for the beta testing notes. Add the candidate to the existing tester group. External distribution may require TestFlight App Review. Record the source commit, final build number, processing status, and groups in Notion.

Keep the app and extension bundle IDs, App Group, and existing Family Controls/NFC entitlements. Both distribution profiles must support Family Controls. Simulator UI results do not establish physical shielding or NFC behavior.

### Signing from a remote session

Unlocking the login keychain can restore Xcode's saved account access even if the local development key remains unavailable to `codesign`. Apple's cloud-managed distribution signing was usable in this situation.

For the remote signing workflow, a separate copy of the compiled archive was ad-hoc signed with each target's source entitlements, then re-signed by Xcode's automatic App Store Connect export. The ad-hoc input is not a distribution build. Exporting the plain unsigned archive omitted required entitlements, so that package was rejected during local verification and was not uploaded.

Before uploading a remotely signed package, verify both code signatures and embedded Store profiles. The app must retain Family Controls, NFC `TAG`, and `group.com.amitsankaran.Block`; the monitor must retain Family Controls and the same App Group. Both need the expected application identifiers, `beta-reports-active = true`, and `get-task-allow = false`. Check the final version/build in both bundles. The distribution certificate must be Apple's distribution identity, not the temporary ad-hoc signature.

## Add friends as testers

1. Open [Tyri in App Store Connect](https://appstoreconnect.apple.com/apps/6757515805) → TestFlight.
2. Under **External Testing**, select the existing group, or use **+** to create one such as “Friends & Family.” If no internal group exists yet, create one under **Internal Testing** first; Apple requires that before creating an external group.
3. Choose **Add Builds**, select the fresh processed build, add testing notes, and submit it for TestFlight App Review if requested. External testers can install it after approval and distribution to their group.
4. For specific people, use **+** beside **Testers** → **Email**, then enter their email addresses and send invitations.
5. For a reusable invitation, use **Create Public Link** in the group's Testers tab, set an appropriate tester limit, and copy the link. Anyone receiving a forwarded public link may be able to join.
6. Testers install Apple's TestFlight app on their iPhones, open the invitation email or link on the phone, accept, and install Tyri. Existing group members can update when a new available build is assigned to that group.

Use external tester groups for friends. Internal testers are members of your App Store Connect team and need an eligible team role.

Builds expire 90 days after upload; an expired build needs a fresh uploaded build to resume testing. Each future refresh should increment the build number, archive, upload, confirm processing, and assign the new build to the tester group.

Apple references: [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/), [invite external testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/), [add internal testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/).

## Persistence candidate — 2.3 (6)

The app and monitor Release archive compile successfully from `9084fb6`. This candidate hardens usage-lock callbacks, repairs live usage shields on foreground recovery, preserves manual blocks at expiry, binds early-release cooldowns to their activation, and registers break re-locking before lifting shields. See the [QA report](../docs/issues/2026-10-31-block-lifecycle-qa.md) and [candidate receipt](builds/2.3-6.json).

**Uploaded successfully on October 31, 2026 at 18:20:53 UTC.** Unlocking the login keychain restored cloud signing. Both final Apple Distribution signatures, Store profiles, build/version identifiers, Family Controls, App Group and app NFC entitlements were verified before upload. Apple reported “Uploaded package is processing.” Processing completion and tester-group availability remain unverified; the App Store Connect browser session requires sign-in. The [receipt](builds/2.3-6.json) records the verified export hash, upload timestamp and evidence paths. No App Store release or merge was performed.

## Approved UX candidate — 2.3 (7)

Approved in chat November 1, 2026. Release app and monitor archive compiled from `cc26e6c`. Five UI scenarios passed across the full run and the corrected scrolling rerun; 12 lifecycle and 16 calendar checks passed. Both bundles report 2.3 (7). Simulator review flags and sample data are excluded from Release. Live numeric usage totals are not included; tracking status and revised copy are included.

**Uploaded successfully on November 1, 2026 at 17:00:10 UTC.** Unlocking the login keychain restored cloud signing. Both final Apple Distribution signatures, Store profiles, bundle versions, Family Controls, App Group, and app NFC entitlements were verified. Apple reports “Uploaded package is processing.” No upload errors or warnings. Processing completion and tester-group availability remain unverified because the browser connection is unavailable. See [release receipt](builds/2.3-7.json).

## Papercut fixes — 2.3 (8)

**Uploaded successfully on November 1, 2026 at 19:41:24 UTC.** Fixes timed-end wording, website Save without +, domain validation and schedule-registration error/retry feedback. Source: `8c24279`. Three focused simulator UI scenarios passed across the initial run and corrected schedule reruns; 25 domain/status, eight schedule-error, 12 lifecycle and 16 calendar checks passed. Both app and monitor signatures, Store profiles, versions and required capabilities were verified. Apple reports processing; tester availability remains unverified. [Release receipt](builds/2.3-8.json) · [Review and validation](../docs/reviews/2026-11-01-papercuts.md). Screenshots are on the Tyri Notion project page.

## Repeat usage cycles and ad hoc sessions — 2.3 (9)

**Uploaded successfully on November 3, 2026 at 05:22:25 UTC.** Fresh usage-monitor identities, stale-threshold protection, registration error/retry feedback, missing expiry repair, and temporary Block for a while sessions. Source: `42170df`. Both Apple Distribution signatures, Store profiles, versions and required entitlements were verified. Apple reports processing. Tester availability and physical enforcement remain acceptance checks; browser access was unavailable. [Release receipt](builds/2.3-9.json) · [Review, screenshots and test evidence](../docs/reviews/2026-11-03-usage-cycle-and-ad-hoc.md). No App Store release was performed.

## Timer durations — 2.4 (3)

Uploaded successfully November 4, 2026 at 21:45:34 UTC from `7334f2b`. This build contains only the duration picker and timer-progress changes: 00:05–23:55 in five-minute steps, reported usage milestones, and elapsed blocked time. AI block creation, list onboarding, App Attest and the model endpoint are excluded. Deferred work is preserved separately on `develop/2.4` at `51cca9b`.

Both focused UI tests passed on the isolated release checkout; all 287 duration milestone ranges and progress-state checks passed. The physical-device Release archive and distribution export succeeded. Both final signatures, profiles, versions and required capabilities were verified. Apple accepted the upload without errors or warnings. Processing is complete: VALID and IN_BETA_TESTING for Amit Internal. Export compliance is completed and testing notes are saved. External beta review has not been submitted. Physical Screen Time enforcement remains a tester acceptance check. See [receipt](builds/2.4-3.json) and [testing notes](WhatToTest.txt).

Amit confirmed on November 4 that 2.4 (3) works on his device. The timer request is accepted; individual boundary scenarios were not separately enumerated.

## Blocking reliability and usability — 2.4 (4)

Apple accepted the upload November 6, 2026 at 05:24:20 UTC without errors. Source: `e9bcf4b`. Repairs lost foreground registrations, frees usage activity capacity before lockout, applies manual shields before registration, surfaces missing permission and shield-setting failures, and adds release-accessible diagnostics. Active controls precede configuration; manual duration is explicit; an in-form Save action fixes the missing toolbar action on Duo.

Modern simulator scenarios pass across iOS 26.2, 26.5, 27.0 and corrected 27.1 runs. All production-logic checks pass. iOS 17.5 testing remains unverified after candidate and clean-baseline XCTest timeouts. Actual iPhone enforcement is still an acceptance check. AI remains excluded. See [QA report](../docs/qa/blocking-2026-11-05/README.md), [release receipt](builds/2.4-4.json), and [Notion evidence](https://app.notion.com/p/41016e0e0e3a818e843ec19a9777c384). Processing is complete: VALID and IN_BETA_TESTING. Membership in Amit Internal was verified through its automatic all-build distribution. Testing notes and export compliance are saved. External review was not submitted.
