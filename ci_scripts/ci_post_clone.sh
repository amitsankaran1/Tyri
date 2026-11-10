#!/bin/bash
# Xcode Cloud runs this before its build actions. Failure stops the workflow.
set -euo pipefail
task_ci_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$task_ci_root"
printf 'Running Tyri deterministic checks before Xcode Cloud actions.\n'
exec /bin/bash scripts/check.sh
