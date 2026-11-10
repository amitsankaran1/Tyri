# Hosted task dispatcher

The existing native routine is [Advance agent tasks](https://chatgpt.com/scheduled?automationId=6af2349203a08190bf217be3aaaaf9f9&automationSource=cloud), enabled hourly in America/New_York. Its identity and cadence are unchanged; its prompt now covers new ideas, drafts, research, bugs and delivery requests across projects.

Use [ask-matt](https://app.notion.com/p/9b34cc3b74c0496b82499bc013c9c135) for skill routing and the [Agent Operating Guide](https://app.notion.com/p/3ee16e0e0e3a814d9fbbe386b62fad21) for shared phases, authority and ownership. See [the saved native prompt](native-routine-prompt.md).

## Run behavior

Reconcile existing task/checkpoint, branch/PR, exact-revision checks, artifact and delivery receipts before fresh pickup. Assess Inbox requests created after 2026-11-09T21:10:00Z; old backlog requires an explicit recorded request to resume. Migration/edit time alone is not activation. Preserve other owners, pauses, stopped projects, Future, Done and Archived.

Investigate useful next steps, research facts and make reasonable reversible choices within scope. Questions and answers stay in the same task; Human review is for Amit's required decision/approval/acceptance, Blocked for an external dependency. Do not merely summarize the queue when useful authorized work can proceed.

Tyri's verified claim lives on the separate automation/tyri-dispatch-state branch at .automation/dispatch-lock.json. Acquire/release with expected content SHA, unique owner/generation tokens and read-back of ownership. A stale competing update returned 409 in the integration probe. Hold the claim through bounded mutation and persisted checkpoint, then release only your own claim when execution stops. Reacquire/reconcile on the next run; do not hold it indefinitely while waiting for CI, review or a person. Do not auto-clear another or uncertain crashed owner.

Other projects need a compatible claim/execution path; do not place their private metadata into Tyri's public repository. Missing setup becomes a concrete dependency, not permission to improvise a competing dispatcher. Ordinary intake edits reread and preserve the task's current content.

The reviewer is a role, not a fixed product. An independent reviewer must accept the handoff; moving a task to Agent review does not invoke another agent. Current Tyri merges still require Amit's explicit approval. Delivery uses the project's established authorized executor and native CI, and Done requires the agreed outcome including requested availability/acceptance.

## Verified capabilities and gaps

The hosted run has Linux shell and connected Notion/GitHub access. Prior probes verified source reads, a fixture draft PR and result persistence; the fixture PR #26 was closed and must never be repeated. No Swift/Xcode or separate Cloud-task launcher is guaranteed in the routine.

Tyri Xcode Cloud PR triggering is verified, but the latest full Cloud test action failed. The internal-candidate workflow remains disabled; the hosted routine has no provisioned Apple credential and no assigned independent reviewer. Current facts live in the [Tyri project](https://app.notion.com/p/2e616e0e0e3a80148841ff8ca2cb3647) and [CI task](https://app.notion.com/p/3cb16e0e0e3a81438ddbd3a49c70e1ed). A saved prompt does not prove end-to-end delivery.

Do not activate independent competing pickup loops in filing agents, export credentials, widen source access, contact other people/agents through messaging tools, merge or distribute without the applicable authority.
