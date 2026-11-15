# Build 37 provenance and prior execution

Read-only audit started November 14, 2026, and completed November 15 after Apple access and local storage recovered. **Build 2.4 (37) is verified as source `a9c222505b8c1f83b3bd6eb8c9db9b47dbba2698`, which remains current main.** This attribution comes from the build's direct Xcode Cloud relationship, not an assumption based on the checkout or incomplete GitHub receipt.

## Build 37: authoritative Apple evidence

- [App Store Connect build](https://api.appstoreconnect.apple.com/v1/builds/5583084b-442b-4a6d-8f7f-15284b2ca86d): ID `5583084b-442b-4a6d-8f7f-15284b2ca86d`, build number `37`, prerelease version `2.4` / IOS, uploaded `2026-11-12T18:10:58Z`, `VALID`, not expired. The build lookup included prerelease version `32ac6380-c8ed-4a58-aad5-91d5f719f6ff` with version `2.4`.
- [Direct Cloud-run build relationship](https://api.appstoreconnect.apple.com/v1/ciBuildRuns/d7d335b5-3912-4825-abff-b86e7063e018/builds) returns exactly that build ID. [Cloud run 37](https://appstoreconnect.apple.com/teams/6785d4c1-d8f9-4e40-9783-4c31742ffb55/apps/6757515805/ci/builds/d7d335b5-3912-4825-abff-b86e7063e018) has source commit `a9c222505b8c1f83b3bd6eb8c9db9b47dbba2698`, started `2026-11-12T18:04:34.704Z`, finished `2026-11-12T18:40:04.917Z`, `COMPLETE` / `ERRORED`. The existing failed UI-test record is consistent with this run status; an errored run does not mean its successful archive was never uploaded.
- [Current beta detail](https://api.appstoreconnect.apple.com/v1/builds/5583084b-442b-4a6d-8f7f-15284b2ca86d/buildBetaDetail): external `IN_BETA_TESTING`, internal `READY_FOR_BETA_TESTING`. Complete group lookup returned internal **Dev** (all-builds access, ID `ef128175-ca20-4e29-8e04-b0d222463e8d`, the ID historically named Amit Internal) and external **Tyri Beta** (explicit membership, ID `064feeb3-c339-4cb1-be3c-6392094757b0`). No group was changed, no distribution action was taken, and this audit did not verify an individual tester's installation.
- Rechecked GitHub on November 15: main remains the same SHA, so no subsequent merged fix exists after build37. The sole open PR is this investigation's [PR #35](https://github.com/amitsankaran1/Tyri/pull/35), branch `fix/lifecycle-build37`, observed head `1da7a2741c55e4f0dd7ca6bc9dc18791b6af7a71`; it is not delivered code.
- Build37 therefore contains both PR33 and PR34. The original deferred checkout `9bf604c` does not represent it. Current-main test results can now be identified as source-equivalent to build37, while simulator results still do not establish actual Screen Time enforcement.

## Verified source and delivery history

- On November 14, remote `main` was `a9c222505b8c1f83b3bd6eb8c9db9b47dbba2698`; no open pull requests or subsequent main fixes were found at that initial checkpoint. The November 15 PR35 state is recorded above.
- The last successful durable internal receipt identifies **2.4 (33)** as `1bea72dc76d3a3b7d346c5b982a3bb20c0ff9f36`. Apple run `c6b87147-0eba-4c7b-91da-8b25f2e9f81d`, build `f3aea262-0f7a-4d83-b046-2fd86a8e2b07`, VALID, IN_BETA_TESTING, Amit Internal. [Receipt](https://github.com/amitsankaran1/Tyri/pull/25#issuecomment-6814597593), [successful observer](https://github.com/amitsankaran1/Tyri/actions/runs/43155396447).
- Current main's Apple run `d7d335b5-3912-4825-abff-b86e7063e018` archived successfully but its test action failed `BlockingReliabilityTests.testBothSaveButtonsRejectBlankName()` at `TyriUITests/BlockingReliabilityTests.swift:50`. [Failed receipt workflow](https://github.com/amitsankaran1/Tyri/actions/runs/43275975291), [incomplete receipt](https://github.com/amitsankaran1/Tyri/pull/25#issuecomment-6831786093). The receipt contains neither build number nor verified availability; it does not identify build 37.
- Since verified build 33, [PR #34](https://github.com/amitsankaran1/Tyri/pull/34) added corruption/missing-list preservation, timed ownership expiry with legacy manual snapshots, deferred clears, inactive Save admission, Emergency Access/list mutation safeguards, explicit UTC/Gregorian deadlines and pending-state presentation. Its commits are `678f4122`, `fe309209`, `d888622b`, merged as current main. See [the prior review record](../../issues/2026-11-12-opus-review.md). These are historical fixes, not a diagnosis of the recurrence.

## Existing claim and local changes

- Canonical task branch `factory/41516e0e0e3a81dfb1b0f7f45f43fb02` remains at `2cdfb432bafaa4de21ed26d630844b0fa49321e1`. Its old `/private/tmp/tyri-suspension-fix` worktree is clean. [PR #33](https://github.com/amitsankaran1/Tyri/pull/33) merged that attempt on November 12 at 04:31:47Z as `1bea72dc`; it is not an open executor attempt.
- PR #34 merged November 12 at 18:04:10Z. The fetched bug history records these completed attempts and pending delivery/device checks; no newer active executor was found.
- The old `automation/tyri-dispatch-state` lock says `owner:null`. That mechanism is historical, not a substitute for the current task-branch claim rules. No existing claim or worktree was altered by this audit.
- The user's original checkout is deferred branch `9bf604ca2b8c80ca195c3c3ad2ab26a0560299be`, with untracked `.agents/`; preserved. It predates both PR33 and PR34 and is not build37 evidence.

## Initial blockers and bounded local search (resolved)

Initial read-only build37 and candidate-run queries returned “A required agreement is missing or has expired.” Amit later confirmed agreement acceptance. Subsequent attempts were prevented before execution by automatic approval review's inability to create its session lock under disk exhaustion. On November 15, after Amit freed storage, the normally approved read-only requests succeeded. This audit accepted no agreement and changed no account configuration.

The bounded local search inspected the 13 archive metadata files under `~/Library/Developer/Xcode/Archives` (latest archive date October 29), root-level `/private/tmp/*.xcarchive` app metadata, repository release receipts, and `/private/tmp/tyri-*.json` release/build records. None establishes build37 provenance. GitHub PR25 receipt history contains successful build20,25,28,30,33 receipts and an incomplete current-main receipt. Searching opaque simulator/XCResult filenames containing “37” does not establish an app build number.

The temporary `/private/tmp/tyri-asc-api.py` helper had been removed during cleanup. Successful November 15 queries invoked `/opt/homebrew/bin/asc` with the existing `/Users/amitsankaran/.asc/tyri-key-setup.json` key configuration loaded into child-process environment only; no credential value was printed or recorded. Read-only commands:

```sh
asc builds info --app 6757515805 --build-number 37 --platform IOS
asc xcode-cloud build-runs list --workflow-id 37dfe861-29f0-4013-bc1c-5dc29544d23d --limit 10
asc xcode-cloud build-runs builds --run-id d7d335b5-3912-4825-abff-b86e7063e018
asc builds build-beta-detail view --build-id 5583084b-442b-4a6d-8f7f-15284b2ca86d
asc builds groups list --build-id 5583084b-442b-4a6d-8f7f-15284b2ca86d
```

Build ID, source SHA, Cloud run and current beta state are now correlated above. Original GitHub receipt links remain durable evidence of the earlier failed observer; its temporary local copy may have been removed during disk cleanup. No build trigger, upload, distribution or physical-device acceptance was performed by this audit.
