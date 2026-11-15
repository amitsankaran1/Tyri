"""Seeded properties of production MonitorLedger, not a parallel state model.

QA_SEED and QA_STEPS replay a sequence. Failure output includes a
removal-minimized operation trace. This suite does not exercise native iOS.
"""
from pathlib import Path
import os
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="tyri-lifecycle-stress-") as directory:
    temp = Path(directory)
    files = [repo / "Shared/MonitorLedger.swift", Path(__file__).with_name("main.swift")]
    subprocess.run(["swiftc", "-parse-as-library", "-swift-version", "6", "-strict-concurrency=complete",
                    "-module-cache-path", str(temp / "cache"), *map(str, files), "-o", str(temp / "run")], check=True)
    subprocess.run([str(temp / "run")], check=True, env=os.environ)
