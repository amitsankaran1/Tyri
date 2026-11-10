#!/bin/bash
# Xcode Cloud runs this before its build actions. Failure stops the workflow.
set -euo pipefail
task_ci_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$task_ci_root"
if [[ "${CI_XCODE_CLOUD:-}" == "TRUE" ]]; then
  # Apple reads this folder next to the project when distributing to TestFlight.
  mkdir -p TestFlight
  {
    printf 'Internal candidate %s\nSource: %s\n' "${CI_BUILD_NUMBER:?}" "${CI_COMMIT:-$(git rev-parse HEAD)}"
    printf 'Change: %s\n\n' "$(git log -1 --format=%s)"
    printf 'Verify the affected task on your physical device. Simulator checks do not establish NFC or Screen Time enforcement.\n\n'
    cat release/WhatToTest.txt
  } > TestFlight/WhatToTest.en-US.txt
fi
printf 'Running Tyri deterministic checks before Xcode Cloud actions.\n'
exec /bin/bash scripts/check.sh
