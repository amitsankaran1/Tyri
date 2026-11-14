"""Exercise production lock acquisition against unavailable storage and real flock.

QA_REVISION pins an old production source for the baseline timeout regression.
"""
from pathlib import Path
import fcntl
import os
import subprocess
import tempfile
import time
import uuid

repo = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="tyri-unavailable-transaction-") as directory:
    root = Path(directory)
    source = repo / "Shared/EnforcementTransaction.swift"
    if revision := os.environ.get("QA_REVISION"):
        source = root / "EnforcementTransaction.swift"
        source.write_bytes(subprocess.check_output(
            ["git", "show", f"{revision}:Shared/EnforcementTransaction.swift"], cwd=repo))
    subprocess.run(["swiftc", "-parse-as-library", "-module-cache-path", str(root / "cache"),
                    str(source), str(Path(__file__).with_name("main.swift")),
                    "-o", str(root / "run")], check=True)
    env = dict(os.environ, TYRI_TEST_SUITE="tyri-unavailable-" + str(uuid.uuid4()),
               TYRI_TRANSACTION_PATH=str(root / "missing" / "lock"))
    # Old code spins indefinitely here. The process timeout is a failure, not a
    # successful expected result, so CI can detect the regression directly.
    subprocess.run([str(root / "run"), "unavailable"], env=env, check=True, timeout=3)
    env["TYRI_TRANSACTION_PATH"] = str(root / "lock")
    with open(root / "lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        waiter = subprocess.Popen([str(root / "run"), "contended"], env=env)
        time.sleep(0.2)
        assert waiter.poll() is None, "effect acquired while another process held the lock"
        fcntl.flock(lock, fcntl.LOCK_UN)
        assert waiter.wait(timeout=3) == 0
        fcntl.flock(lock, fcntl.LOCK_EX)
        subprocess.run([str(root / "run"), "disabled"], env=env, check=True, timeout=3)
    # Compile the actual actuator with the existing native ManagedSettings double.
    # Remove only framework imports and the other suite's entry point.
    doubles = (repo / "Tests/ShieldQA/Doubles.swift").read_text().split("@main struct Tests")[0]
    (root / "Doubles.swift").write_text(doubles)
    files = [source, root / "Doubles.swift", Path(__file__).with_name("actuator.swift")]
    for relative in ["Shared/BlockingActuator.swift", "Shared/EnforcementDiagnostics.swift"]:
        artifact_revision = os.environ.get("QA_ACTUATOR_REVISION", revision)
        text = (subprocess.check_output(["git", "show", f"{artifact_revision}:{relative}"], cwd=repo).decode()
                if artifact_revision else (repo / relative).read_text())
        text = text.replace("import ManagedSettings", "").replace("import FamilyControls", "")
        target = root / Path(relative).name
        target.write_text(text)
        files.append(target)
    subprocess.run(["swiftc", "-parse-as-library", "-module-cache-path", str(root / "cache"),
                    *map(str, files), "-o", str(root / "actuator")], check=True)
    subprocess.run([str(root / "actuator")], env=env, check=True, timeout=3)
