"""Run production callbacks and lifecycle helpers against deterministic OS/store doubles."""
from pathlib import Path
import subprocess
import tempfile
repo = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="tyri-callback-qa-") as directory:
    temp = Path(directory)
    files = [Path(__file__).with_name("Doubles.swift")]
    for relative in ["TyriMonitor/TyriMonitorExtension.swift", "Shared/UsageMonitoring.swift", "Shared/BreakMonitoring.swift"]:
        source = (repo / relative).read_text().replace("import DeviceActivity", "").replace("import FamilyControls", "")
        path = temp / Path(relative).name
        path.write_text(source)
        files.append(path)
    subprocess.run(["swiftc", "-module-cache-path", str(temp / "cache"), *map(str, files), "-o", str(temp / "run")], check=True)
    subprocess.run([str(temp / "run")], check=True)
