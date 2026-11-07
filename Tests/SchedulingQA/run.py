from pathlib import Path
import subprocess
import tempfile
repo = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="tyri-schedule-errors-") as directory:
    temp = Path(directory)
    source = (repo / "Tyri/Services/SchedulingManager.swift").read_text()
    source = source.replace("import DeviceActivity", "").replace("import Combine", "")
    manager = temp / "SchedulingManager.swift"
    manager.write_text(source)
    subprocess.run(["swiftc", "-module-cache-path", str(temp / "cache"), str(manager), str(repo / "Shared/EnforcementTransaction.swift"), str(Path(__file__).with_name("Doubles.swift")), "-o", str(temp / "run")], check=True)
    subprocess.run([str(temp / "run")], check=True)
