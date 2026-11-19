# Tyri repository guidance

Start with [README.md](README.md) for commands and [docs/agent-workflow.md](docs/agent-workflow.md) for the shared workflow. Fetch Amit’s enabled Notion Skills at session start and read the approved Agent Operating Guide and Shared Context before project work or Notion writes, as required by the host instructions.

Use `bash scripts/check.sh` for deterministic checks. The `Tyri` scheme includes `TyriUITests`. Use an explicit simulator UDID and separate build output for parallel worktrees. Read the relevant harness and source before choosing additional checks.

Preserve app `name.amitsankaran.Block`, monitor `name.amitsankaran.Block.BlockMonitor`, App Group `group.com.amitsankaran.Block`, persistence compatibility, and active-block protections. App and extension coordination is documented in `docs/STATE_MACHINES.md`.

Inspect screenshots of changed UI flows and save captioned evidence to the existing Tyri Notion task or Builds & Tests record. Label fixtures and simulator limitations. Physical NFC, Screen Time enforcement and background timing require device acceptance.

Use the established internal TestFlight workflow and existing task/run identities. Follow `docs/ios-delivery.md` and `docs/testflight-agent-command.md`. Merges require Amit’s approval of the named revision. Record code, implementation plans and executable runbooks in the repository.
