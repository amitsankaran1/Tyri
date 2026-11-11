from pathlib import Path
import subprocess, tempfile, os
root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="tyri-store-durability-") as d:
    d = Path(d)
    files = [Path(__file__).with_name("main.swift")]
    for name in ["BlockStore", "AppGroupStore"]:
        relative = "Tyri/Services/" + name + ".swift"
        rev = os.environ.get("QA_REVISION")
        source = subprocess.check_output(["git", "show", rev + ":" + relative], cwd=root, text=True) if rev else (root / relative).read_text()
        source = source.replace("import Combine", "").replace("import FamilyControls", "")
        if rev: source = source.replace("    private init()", "    var loadError: String? { nil }\n    private init()")
        path = d / (name + ".swift"); path.write_text(source); files.append(path)
    subprocess.run(["swiftc", "-parse-as-library", "-module-cache-path", str(d / "cache"), *map(str, files), "-o", str(d / "run")], check=True)
    subprocess.run([str(d / "run")], check=True, timeout=20)
