from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
subprocess.run(["python3", str(Path(__file__).with_name("source_guard.py"))], check=True)
with tempfile.TemporaryDirectory(prefix="tyri-foreground-recovery-") as directory:
    temp = Path(directory)
    source = (root / "Tyri/Services/ForegroundRecovery.swift").read_text()
    for module in ["Combine", "DeviceActivity", "FamilyControls"]:
        source = source.replace("import " + module, "")
    production = temp / "ForegroundRecovery.swift"
    production.write_text(source)
    subprocess.run(["swiftc", "-parse-as-library", "-module-cache-path", str(temp / "cache"),
                    str(production), str(Path(__file__).with_name("main.swift")),
                    "-o", str(temp / "run")], check=True)
    subprocess.run([str(temp / "run")], check=True, timeout=15)
