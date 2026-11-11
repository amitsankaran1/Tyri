from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="tyri-monitor-ledger-") as directory:
    binary = Path(directory) / "run"
    subprocess.run(["swiftc", "-parse-as-library", "-swift-version", "6", "-strict-concurrency=complete",
                    str(root / "Shared/MonitorLedger.swift"), str(Path(__file__).with_name("main.swift")),
                    "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
