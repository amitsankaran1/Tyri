# Hosted task dispatcher

The existing native task is [Advance agent tasks](https://chatgpt.com/scheduled?automationId=6af2349203a08190bf217be3aaaaf9f9&automationSource=cloud), enabled hourly in America/New_York. Scheduler identity/cadence are unchanged. [Native prompt](native-routine-prompt.md) mirrors its saved instructions.

The [Agent Operating Guide](https://app.notion.com/p/3ee16e0e0e3a814d9fbbe386b62fad21) defines policy. [ask-matt](https://app.notion.com/p/9b34cc3b74c0496b82499bc013c9c135) routes to the existing skills. Read each project's live profile for capability and delivery, and the [pipeline checkpoint](https://app.notion.com/p/41316e0e0e3a819793daf1454045a641) for activation/run evidence. Do not infer runtime capability from this document.

## Scheduler adapter

Each run reconciles accepted work before assessing fresh Inbox records created after 2026-11-09T21:10:00Z. Old backlog requires explicit recorded resumption; migration/edit time alone does not activate it. The saved prompt contains the exact selection and reconciliation instructions.

Tyri's claim adapter is GitHub's expected-content-SHA update on branch automation/tyri-dispatch-state at .automation/dispatch-lock.json. The saved native prompt contains the token/acquire/read-back/release procedure. A stale competing update returned 409 in the earlier integration probe. This is a coordination mechanism, not a task lifecycle. Other projects need their own compatible verified claim/execution path; unrelated metadata does not belong in Tyri's public repository.

## Runtime evidence

Observed in the original November 9, 2026 probes: Linux shell and connected Notion/GitHub access, source reads, fixture draft PR and result persistence. Fixture PR #26 was subsequently closed and must not be repeated. This dated probe is not evidence of current Xcode, reviewer-launcher or delivery capability.

Expanded prompt behavior and actual boundaries must be verified in post-update runs and recorded in the pipeline checkpoint. Current CI/TestFlight readiness belongs only in the [CI task](https://app.notion.com/p/3cb16e0e0e3a81438ddbd3a49c70e1ed); do not copy mutable readiness into scheduler policy.
