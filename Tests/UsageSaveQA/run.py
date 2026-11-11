"""Regression guard: editing a usage limit must not run DeviceActivity IPC on the Save path.

This checks the real Swift entry point. Physical-device acceptance is still required.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
source = (root / "Tyri/Views/BlockEditorView.swift").read_text()
save = source.split("    private func save() {", 1)[1].split("    private func deleteBlock()", 1)[0]
assert "case .timer:" in save, "Timer save path missing"
timer = save.split("case .timer:", 1)[1].split("case .tag:", 1)[0]
assert "usageLimitManager.applyUsageLimit" not in timer, (
    "Saving a timer still performs synchronous DeviceActivity registration on the UI thread"
)
assert "ForegroundRecovery.shared.request()" in timer, (
    "Timer edits must schedule the existing background recovery worker"
)
assert re.search(r"Task\s*\{", timer), (
    "Recovery must be scheduled after Save releases its enforcement lease"
)
print("PASS: usage-limit Save defers native monitoring to foreground recovery")
