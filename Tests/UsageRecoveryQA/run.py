from pathlib import Path
root = Path(__file__).resolve().parents[2]
s = (root / "Tyri/Services/UsageLimitManager.swift").read_text()
method = s.split("    func applyUsageLimit(", 1)[1].split("    /// Full teardown", 1)[0]
assert "requestAccepted()" in method
assert "DeviceActivityCenter" not in method and "UsageMonitoring." not in method
print("PASS: usage manager delegates all registration to the recovery worker (behavior covered in ForegroundRecoveryQA)")
