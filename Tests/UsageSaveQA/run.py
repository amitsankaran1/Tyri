"""Regression guard: editing a usage limit must not run DeviceActivity IPC on the Save path.

This checks the real Swift entry point. Physical-device acceptance is still required.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
source = (root / "Tyri/Views/BlockEditorView.swift").read_text()
save = source.split("    private func save() {", 1)[1].split("    private func deleteBlock()", 1)[0]
assert "usageLimitManager.applyUsageLimit" not in save
assert "schedulingManager.applySchedule" not in save
assert "ForegroundRecovery.shared.requestAccepted()" in save
print("PASS: all rule Save paths own bounded asynchronous registration")
