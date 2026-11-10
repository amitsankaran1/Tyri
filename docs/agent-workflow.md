# Agent work and delivery

Follow the live [Agent Operating Guide](https://app.notion.com/p/3ee16e0e0e3a814d9fbbe386b62fad21) for phase definitions, ownership, questions/answers and authority. Use [ask-matt in Notion Skills](https://app.notion.com/p/9b34cc3b74c0496b82499bc013c9c135) to choose the existing intake, investigation, implementation and independent-review skills.

## Start or resume

Forward the original screenshot, bug, idea, draft, research question or build request through a filing agent into the existing Tasks database, related to the project, Status Inbox. State the desired outcome when known; rough ideas can be investigated before they become a spec. The designated routine handles eligible pickup without a second coding-chat handoff.

Read the existing task and artifact/branch/PR/run before starting. Save questions, recommendations, answers, accepted executor and resumable evidence in the same task. The live Guide and Skills are canonical; this repository does not define a second workflow.

## Tyri

Read the [Tyri project profile](https://app.notion.com/p/2e616e0e0e3a80148841ff8ca2cb3647) for source, product constraints, checks, authorized delivery, physical-device acceptance and recovery. Current setup/run evidence belongs to the [CI task](https://app.notion.com/p/3cb16e0e0e3a81438ddbd3a49c70e1ed); read it before promising automatic TestFlight delivery.

Repository commands and checked-in Xcode Cloud configuration are described in [iOS delivery](ios-delivery.md) and [cloud configuration](../ci_scripts/xcode-cloud/README.md). Run bash scripts/check.sh for deterministic checks; use project-appropriate compilation/UI checks and captioned evidence for the actual change. A receipt must identify the verified source/artifact.

For a build-only request, file "Build Tyri from approved current main for Amit Internal; produce a fresh build and verify availability" in Inbox. Status queues the request; it does not approve a merge or bypass missing executor capability. Follow the profile's existing-candidate/retry and acceptance rules.

## Automation

[Dispatcher setup](task-dispatcher.md) records the scheduler/claim adapter. [Native prompt](native-routine-prompt.md) is a read-back mirror of the saved scheduler instructions, not an independently maintained policy. Change shared rules in the Guide/Skills, project rules in the project profile/runbook, and runtime facts in the evidence task.
