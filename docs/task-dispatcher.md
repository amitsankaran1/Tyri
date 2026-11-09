# Hosted task dispatcher

Approved pilot: Tyri only; scheduled check every 15 minutes; one active implementation per project. Filing a clear bug through any of Amit's agents authorizes investigation and an eligible low-risk fix through a PR. Human merge review remains required. This replaces chat-only pickup for the enabled pilot.

## Activation requirements

The hosted scheduler must have connected Notion access and a coding executor it can start without Amit copying a task link. The executor needs Tyri repository read/write access, an isolated checkout, a suitable macOS/Xcode environment for its required checks, and a place to save run/PR evidence.

Configure one serialized dispatcher and enforce the per-project execution slot in the host. A Notion status or body checkpoint is not an atomic lock. If the host cannot enforce single ownership, do not enable dispatch. Do not start independent dispatchers in GB, Dot or Instinct; they remain filing agents and may use the shared enrichment skill.

At activation, record the scheduler identity, executor identity, activation timestamp, configured interval and permissions in the pipeline task. Only bugs filed after that timestamp are in the initial automatic pilot. Existing backlog work requires explicit opt-in, preventing surprise pickup of parked or historical reports.

Validate one real filed bug from intake to accepted execution and a PR. Also verify that overlapping checks cannot launch duplicate work, an active task is skipped, an ambiguous report requests a decision, and an excluded change is not implemented automatically. Record the actual results. Instructions or a recurring Notion summary alone do not satisfy activation.

## Scheduled prompt

Check Tasks at https://app.notion.com/p/69b0ba1ab76140ccbc98da7cf3b607ed for new software bug reports in the enabled Tyri pilot. Read the current dispatcher activation record in https://app.notion.com/p/41316e0e0e3a819793daf1454045a641 first. Stop without dispatch if it is not marked activated with a verified host/executor and activation timestamp.

Load the shared enrich-bug-task skill from https://app.notion.com/p/41316e0e0e3a815cbd30e796d7e29bac and the live Tyri project/testing profile. Read the actual database schema before querying. Scope candidates to the Tyri relation, new reports after activation, and unstarted Inbox bugs. Inbox is a filter, not authorization: require the standing pilot authority and a clear defect report as well. Do not pick up ideas/features, Future/parked, paused, Done, Archived, Human review or work already owned by an executor.

Inspect current task checkpoints and existing repo branches/PRs. Enrich eligible reports using the shared skill, preserving original evidence. No unchanged-task rewrites or repeated questions every 15 minutes. Missing user intent and higher-risk decisions go to Human review with a concise question and recommendation. Missing runtime access is recorded as an operational dependency.

Before launch, acquire the host's project execution slot and re-read the task and its material scope. If another implementation is active, leave the task queued and release this check's resources. The slot belongs to the executor run until completion or confirmed termination, not merely until the polling check ends. On an uncertain launch result, inspect the existing run identity; do not launch another attempt. On expired/disconnected ownership, reconcile the actual run and PR before releasing/retrying.

Dispatch the exact task URL, scope snapshot and acceptance criteria to one coding executor. Record its accepted run identity/link and branch in the task; move it to In progress only after acceptance. A proposed handoff is not a started implementation. If the report materially changes during the run, reconcile intent before continuing.

The executor reproduces/otherwise establishes the failure, implements narrowly, runs relevant checks, and reassesses risk against the actual diff. If scope grows or exclusions are touched, stop for Human review. Return a draft PR with source revision, test/review evidence, limitations and the exact requested decision. No automatic merge or deployment. Record a resumable checkpoint on failure; do not retry a code failure indefinitely on every poll.

Do not send messages through GB, Dot, email or other channels. Keep results in the task and the executor's normal run output. Do not change schemas, enable other projects or widen source access. Done requires the agreed verified outcome, including delivery when requested.

## Current state

The shared skill is created and enabled. The scheduled prompt is prepared. No hosted scheduler/executor pair has been connected or activated, and no automatic coding dispatch has been verified.
