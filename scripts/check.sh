#!/bin/bash
# Local and CI entry point for deterministic checks; no signing or uploads.
set -euo pipefail
cd "$(dirname "$0")/.."
task_check_tmp=$(mktemp -d "${TMPDIR:-/tmp}/tyri-check.XXXXXX")
trap 'rm -rf "$task_check_tmp"' EXIT
printf 'Checking source %s\n' "$(git rev-parse HEAD)"
task_tests_dir=Tests
if [[ ! -d "$task_tests_dir" ]]; then task_tests_dir=tests; fi
# Run every checked-in deterministic harness, including new lifecycle suites.
# Do not silently succeed if the test directory or its harnesses disappear.
task_suite_count=0
for task_suite in "$task_tests_dir"/*/run.py; do
  [[ -f "$task_suite" ]] || continue
  printf '\nRunning %s\n' "$task_suite"
  python3 "$task_suite"
  task_suite_count=$((task_suite_count + 1))
done
[[ "$task_suite_count" -gt 0 ]] || { echo 'No deterministic harnesses found' >&2; exit 1; }
swiftc -module-cache-path "$task_check_tmp/cache" Shared/BlockingSchedule.swift "$task_tests_dir/ScheduleWindowTests.swift" -o "$task_check_tmp/schedule"
"$task_check_tmp/schedule"
swiftc -module-cache-path "$task_check_tmp/cache" Tyri/Models/WebsiteDomain.swift Tyri/Models/BlockingEndDescription.swift "$task_tests_dir/PapercutTests.swift" -o "$task_check_tmp/papercuts"
"$task_check_tmp/papercuts"
if [[ -f "$task_tests_dir/UsageProgressQA/main.swift" ]]; then
  swiftc -module-cache-path "$task_check_tmp/cache" Shared/UsageProgress.swift "$task_tests_dir/UsageProgressQA/main.swift" -o "$task_check_tmp/usage-progress"
  "$task_check_tmp/usage-progress"
fi
printf 'Deterministic checks passed. Simulator, signing, and physical-device checks are separate.\n'
