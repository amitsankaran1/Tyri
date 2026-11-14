# Build 37 provenance and prior execution

Read-only audit on November 14, 2026, by independent release-audit worker. **Build 2.4 (37)'s exact source is still unverified.** Current main must not be labeled as that build without the missing Apple evidence.

## Verified source and delivery history

- Remote `main`, freshly queried through GitHub: `a9c222505b8c1f83b3bd6eb8c9db9b47dbba2698`. No open pull requests or subsequent main fixes were found.
- The last successful durable internal receipt identifies **2.4 (33)** as `1bea72dc76d3a3b7d346c5b982a3bb20c0ff9f36`. Apple run `c6b87147-0eba-4c7b-91da-8b25f2e9f81d`, build `f3aea262-0f7a-4d83-b046-2fd86a8e2b07`, VALID, IN_BETA_TESTING, Amit Internal. [Receipt](https://github.com/amitsankaran1/Tyri/pull/25#issuecomment-6814597593), [successful observer](https://github.com/amitsankaran1/Tyri/actions/runs/43155396447).
- Current main's Apple run `d7d335b5-3912-4825-abff-b86e7063e018` archived successfully but its test action failed `BlockingReliabilityTests.testBothSaveButtonsRejectBlankName()` at `TyriUITests/BlockingReliabilityTests.swift:50`. [Failed receipt workflow](https://github.com/amitsankaran1/Tyri/actions/runs/43275975291), [incomplete receipt](https://github.com/amitsankaran1/Tyri/pull/25#issuecomment-6831786093). The receipt contains neither build number nor verified availability; it does not identify build 37.
- Since verified build 33, [PR #34](https://github.com/amitsankaran1/Tyri/pull/34) added corruption/missing-list preservation, timed ownership expiry with legacy manual snapshots, deferred clears, inactive Save admission, Emergency Access/list mutation safeguards, explicit UTC/Gregorian deadlines and pending-state presentation. Its commits are `678f4122`, `fe309209`, `d888622b`, merged as current main. See [the prior review record](../../issues/2026-11-12-opus-review.md). These are historical fixes, not a diagnosis of the recurrence.

## Existing claim and local changes

- Canonical task branch `factory/41516e0e0e3a81dfb1b0f7f45f43fb02` remains at `2cdfb432bafaa4de21ed26d630844b0fa49321e1`. Its old `/private/tmp/tyri-suspension-fix` worktree is clean. [PR #33](https://github.com/amitsankaran1/Tyri/pull/33) merged that attempt on November 12 at 04:31:47Z as `1bea72dc`; it is not an open executor attempt.
- PR #34 merged November 12 at 18:04:10Z. The fetched bug history records these completed attempts and pending delivery/device checks; no newer active executor was found.
- The old `automation/tyri-dispatch-state` lock says `owner:null`. That mechanism is historical, not a substitute for the current task-branch claim rules. No existing claim or worktree was altered by this audit.
- The user's original checkout is deferred branch `9bf604ca2b8c80ca195c3c3ad2ab26a0560299be`, with untracked `.agents/`; preserved. It predates both PR33 and PR34 and is not build37 evidence.

## Provenance blocker and bounded local search

The existing authenticated Apple helper was used for read-only build37 and candidate-run queries. Both returned: “A required agreement is missing or has expired.” The tool reports an account-wide API access block. The Account Holder must review/accept the required agreement at [App Store Connect agreements](https://appstoreconnect.apple.com/agreements). No agreement was accepted or account configuration changed.

The bounded local search inspected the 13 archive metadata files under `~/Library/Developer/Xcode/Archives` (latest archive date October 29), root-level `/private/tmp/*.xcarchive` app metadata, repository release receipts, and `/private/tmp/tyri-*.json` release/build records. None establishes build37 provenance. GitHub PR25 receipt history contains successful build20,25,28,30,33 receipts and an incomplete current-main receipt. Searching opaque simulator/XCResult filenames containing “37” does not establish an app build number.

Resume after Apple access returns, using existing credentials without printing them:

```sh
python3 /private/tmp/tyri-asc-api.py builds info --app 6757515805 --build-number 37 --platform IOS
python3 /private/tmp/tyri-asc-api.py xcode-cloud build-runs list --workflow-id 37dfe861-29f0-4013-bc1c-5dc29544d23d --limit 10
```

Correlate build ID, source SHA, Xcode Cloud run and availability before replacing the unverified attribution. Local copied GitHub receipt evidence: `/private/tmp/tyri-release-comments.json`. No build trigger, upload, distribution or physical-device acceptance was performed by this audit.
