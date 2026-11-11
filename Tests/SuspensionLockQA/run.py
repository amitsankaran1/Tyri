"""Actual kernel-flock probe against current source or QA_REVISION baseline."""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="tyri-suspension-lock-") as directory:
    temp = Path(directory)
    doubles = (root / "Tests/ShieldQA/Doubles.swift").read_text().split("@main struct Tests")[0]
    doubles += '''
@main struct LockProbe {
 static func main() {
  setbuf(stdout, nil)
  let id = UUID()
  let outer = EnforcementTransaction.begin()!
  BlockingActuator.apply(tokens:.init(apps:[1]),blockID:id)
  outer.finish()
  BlockingActuator.clearShields(blockID:id)
  print("Native writes under flock: \\(NativeProbe.lockedCalls)")
  precondition(NativeProbe.lockedCalls == 0, "ManagedSettings IPC retained shared flock")
  print("PASS: native apply and clear, including nested state transitions, release shared flock")
 }
}
'''
    fixture = temp / "Doubles.swift"
    fixture.write_text(doubles)
    files = [fixture]
    for relative in ["Shared/BlockingActuator.swift", "Shared/EnforcementTransaction.swift", "Shared/EnforcementDiagnostics.swift"]:
        revision = os.environ.get("QA_REVISION")
        source = subprocess.check_output(["git", "show", revision + ":" + relative], cwd=root, text=True) if revision else (root / relative).read_text()
        source = source.replace("import ManagedSettings", "").replace("import FamilyControls", "")
        path = temp / Path(relative).name
        path.write_text(source)
        files.append(path)
    binary = temp / "run"
    subprocess.run(["swiftc", "-module-cache-path", str(temp / "cache"), *map(str, files), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
