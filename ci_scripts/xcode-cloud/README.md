# Tyri Xcode Cloud configuration

Manage this setup with `asc` (App Store Connect CLI), not Xcode window automation. The setup used Homebrew `asc` 6.6.0. Apple Account/source access was connected once in Xcode; workflow configuration and verification use CLI/API calls.

## Identities

- App: `6757515805`; cloud product: `4b792aee-e88d-4d54-b834-3b7837a7cd28`.
- Repository: `3111bb30-22b7-4250-9b13-9160d3dd6233` (`amitsankaran1/Tyri`).
- PR checks: `87b4c157-9dd9-4050-9f74-85811fc950ce`.
- Internal candidate: `37dfe861-29f0-4013-bc1c-5dc29544d23d`.
- Existing internal group: `ef128175-ca20-4e29-8e04-b0d222463e8d` (`Amit Internal`).
- Original Default workflow: `F80F0303-E001-4811-A15A-E721A7561AD5`.

Pin Xcode 27.2 (27B52) and macOS 27.2 (26B123). The test destination is iPhone 18 Pro / iOS 27.2. Update pins deliberately when Apple retires a toolchain; verify the available versions first.

## Authentication

The approved `Tyri automation` API key has the Developer role. Apple team keys are account-wide; these instructions authorize using it only for Tyri. The private key is outside Git, with restricted permissions; the named CLI profile is stored in macOS Keychain. Never include keys, JWTs, passwords, or web sessions in this repository or Notion.

Use `asc --profile 'Tyri automation' ...` from the authenticated local terminal context. Some headless processes cannot access login Keychain even when the profile exists. Do not infer that the key is missing, create another key, export Keychain contents, or request passwords in chat. Use the approved local private-key path through `ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_PRIVATE_KEY_PATH` for that command when permitted, or run from the authenticated terminal context. Do not copy credentials to a remote agent without separate authorization.

The `asc web` family uses a cached Apple web session for post-actions and product build numbering. This session can expire. Setup intentionally did not save the Apple password. Renew interactively with `asc web auth login` if required; standard build/status operations use API-key auth and do not depend on that web session.

## Inspect before changing

```sh
asc --profile 'Tyri automation' xcode-cloud workflows --app 6757515805
asc --profile 'Tyri automation' xcode-cloud workflows view --id 87b4c157-9dd9-4050-9f74-85811fc950ce
asc web xcode-cloud workflows describe --product-id 4b792aee-e88d-4d54-b834-3b7837a7cd28 --workflow-id 37dfe861-29f0-4013-bc1c-5dc29544d23d
asc --profile 'Tyri automation' builds next-build-number --app 6757515805
```

`*.create.json` are reviewable provisioning payloads, not files that Apple watches in Git. Do not rerun create when the workflow already exists. Read current state, preserve unrelated settings, and update the named workflow. The post-action patch contains the current archive action's ID; resolve a fresh ID before applying it to a newly created workflow.

`main-protection.json` requires all three checks from GitHub App 117084 (Xcode Cloud), a current base, PR integration and resolved conversations. No approving-review count is imposed because the repository owner files and reviews their own changes; Amit's explicit merge decision remains required by the agent policy. Automatic merge is not enabled.

The internal workflow is initially provisioned disabled. Its archive remains App Store eligible, but its only distribution post-action targets `Amit Internal`. No external group or public submission is configured. File filters include product, shared code, extension, project, tests and CI/build configuration; receipts and Markdown-only changes do not archive.

## Verify and resume

```sh
asc --profile 'Tyri automation' xcode-cloud build-runs list --workflow-id 87b4c157-9dd9-4050-9f74-85811fc950ce
asc --profile 'Tyri automation' xcode-cloud status --run-id RUN_ID
asc --profile 'Tyri automation' xcode-cloud actions --run-id RUN_ID
asc --profile 'Tyri automation' xcode-cloud issues list --run-id RUN_ID
asc --profile 'Tyri automation' xcode-cloud test-results list --run-id RUN_ID
asc --profile 'Tyri automation' xcode-cloud artifacts list --run-id RUN_ID
```

Inspect the existing run before retrying. A successful PR build does not authorize a merge or establish physical enforcement. After an approved main merge, the candidate must pass checks, archive/sign, process successfully in Apple and become available to the existing internal group. Record source SHA, run ID, version/build and group availability in the task. An uncertain upload must be reconciled before a replacement attempt.

The remote request/receipt adapter is documented in docs/testflight-agent-command.md.
Apply internal-candidate.immutable-source.patch.json as a complete start-condition
set: automatic app-changing main, manual main, and manual protected candidate tags.
Apple's public update replaces the start-condition set, so a manual-only patch
can remove the automatic trigger. Verify the complete private editor readback,
including disabled/active state and the unchanged internal post-action, after
updates. CLI response models omit false values such as isEnabled=false.

Cloud numbering was advanced from 1 to 10 after checking both uploaded builds and in-flight upload records. PR checks also consume numbers; gaps are expected. Inspect the current counter and uploads for any exceptional local release instead of hardcoding the next number.
