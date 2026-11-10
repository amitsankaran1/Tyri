from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="tyri-adhoc-presentation-") as directory:
    temp = Path(directory)
    source = temp / "AdHocManager.swift"
    source.write_text((repo / "Tyri/Services/AdHocManager.swift").read_text().replace("import FamilyControls", ""))
    subprocess.run(["swiftc", "-parse-as-library", "-module-cache-path", str(temp / "cache"),
                    str(source), str(Path(__file__).with_name("main.swift")),
                    "-o", str(temp / "run")], check=True)
    subprocess.run([str(temp / "run")], check=True)
