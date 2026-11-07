# Deferred natural-language creation

Parked at Amit's request on 2026-11-07. This is a prototype snapshot for a later build, not the current release.

- Durable branch: `deferred/nl-creation-2.4`
- Original implementation snapshot: `51cca9b` (also retained on local `develop/2.4`).
- Released work: [PR #24 — TestFlight 2.4 (7)](https://github.com/amitsankaran1/Tyri/pull/24), branch `fix/blocking-reliability`.
- Product/model review: [existing Notion 2.4 task](https://app.notion.com/p/40916e0e0e3a818fbe99c4af5617de8f).

## Agreed journey

1. Skippable list onboarding, also available from Lists: editable Social media, Games and Scrollers starters, plus custom lists. People select actual apps in Apple's picker; a model never invents Screen Time tokens. Lists can overlap.
2. Describe saved lists and timing in natural language, then review and edit one block before saving. A missing list takes a creation detour while retaining the block draft.

Supported interpretation targets are weekly schedules, repeating usage allowance/lockout cycles and NFC tag blocks. Immediate temporary blocks remain a separate flow. Defaults and ambiguity must be visible; unsupported requests must not silently become a different rule. No provider is selected: validate the finite-choice model and user journey before choosing Jev or a generative model.

## Preserved implementation and artifacts

| Area | Entry points | Status |
|---|---|---|
| List onboarding | `Tyri/Views/ListOnboardingView.swift`, `AppGroupListView.swift`, `AppGroupEditorView.swift` | Prototype starter-list flow and Apple picker integration |
| Describe → review | `Tyri/Views/DescribeBlockView.swift`, `Tyri/Models/BlockDescriptionDraft.swift`, `Tyri/Services/DescriptionService.swift` | Provider-neutral draft validation and DEBUG fixtures; live interpretation is not implemented |
| Request transport | `Tyri/Services/AttestedDescriptionTransport.swift` | Account-free App Attest client scaffold; physical-device acceptance remains required |
| Backend | `server/README.md`, `server/api/`, `server/lib/`, `server/schema.sql`, `server/test/` | Challenge/enrollment/assertion validation and request budgets; `/api/create` returns `provider_unconfigured` without an evaluated adapter |
| Choice model | `docs/2.4/jev-choice-model.html`, `jev-model-data.json`, `jev-choice-packet.json` | User-centric input/choice model and generated HTML |
| Independent review | `docs/2.4/jev-independent-review.md`, `jev-evaluation-handoff.md` | Feasibility/tradeoff analysis, missing-list-name limitations, consistency checks and benchmark proposal; not measured model-quality evidence |
| Regression scaffolding | `Tests/DescriptionQA/`, `TyriUITests/OnboardingTests.swift`, `server/test/` | Existing validation/fixture tests; not rerun merely to archive this snapshot |

The dedicated Vercel/Neon resource names and operational notes are in `server/README.md`. This archival task does not deploy, delete or change those resources. Current credential availability and deployed resource health have not been revalidated. Secrets stay outside Git; obtain/verify the model key through the existing local secret workflow when needed, never through chat or a committed file.

## Resume safely

1. Read the Notion task, choice model and independent review. Decide whether the proposed choices adequately cover multiple lists, missing names, negation, ambiguous times and unsupported requests.
2. Start implementation from the then-current release/main. Use this branch as reference and selectively port the NL-specific changes. **Do not merge the old snapshot wholesale:** `51cca9b` also includes timer work already shipped, and predates the blocking lifecycle fixes in 2.4 (7). Preserve the new transaction, active-edit, retry and recovery contracts.
3. Reconcile the draft validator with current duration/schedule constraints and test missing-list creation/cancel/return, multiple missing lists and stale saved-list IDs.
4. Evaluate Jev and the proposed generative baseline on the same labeled inputs, including abstention and deterministic consistency validation. Select the provider only after that evidence.
5. Verify backend credentials/resource health, implement the selected adapter, and test real Apple attestation plus end-to-end interpretation. DEBUG fixture success is not live service success.
6. Recheck privacy disclosures and capabilities, capture/review the updated UI, and add screenshots/results to the Notion task before a future release.

The 2.4 (7) PR deliberately excludes this branch. It remains deferred until we resume the feature work.
