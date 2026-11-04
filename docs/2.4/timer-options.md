# Timer durations — November 4

Source: https://app.notion.com/p/40e16e0e0e3a817fb221e81772cf959d

Both usage allowance and subsequent lockout use the same hours/minutes wheel:
00:05–23:55, five-minute steps. Done applies the edit; Cancel preserves the
original. Existing non-step durations remain unchanged unless explicitly edited.
Natural-language drafts must meet the new bounds and steps, with no silent rounding.
Earlier Jev HTML packets used different bounds; this requirement supersedes them.

Focus usage progress shows the latest iOS threshold milestone, not elapsed wall
time. There are at most 60 progress events per usage monitor, plus its original
limit event. Small allowances report each minute; long allowances report in larger
increments, stated in the UI. Records are scoped to the current monitor generation
and local day; out-of-order milestones never reduce the reported count. If extra
progress events cannot register, retry enforcement alone and display progress as
unavailable. Existing monitors keep their consumed budget and acquire progress
reporting when the next cycle is armed.

Blocked time counts upward once per second, bounded by the saved lock deadline.
Five- and ten-minute locks use the existing 15-minute DeviceActivity interval with
a warning callback at the real deadline; the callback checks the persisted deadline.
Foreground reconciliation remains a recovery path, not proof of background timing.

Default pending feedback: keep the existing midnight allowance reset. This work
does not replace daily accounting with a cross-day budget.

Physical-device acceptance still required: select real native app tokens, consume
a five-minute allowance, observe reported progress, verify shielding and automatic
release after a five-minute lock while Tyri is closed, then verify a fresh allowance.
Check a long lock over midnight and compare the recorded deadline. Simulator
screenshots and authored review states cannot prove Screen Time enforcement.
