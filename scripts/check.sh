#!/bin/bash
# Local and CI entry point for deterministic checks; no signing or uploads.
set -euo pipefail
cd "$(dirname "$0")/.."
task_check_tmp=$(mktemp -d "${TMPDIR:-/tmp}/tyri-check.XXXXXX")
trap 'rm -rf "$task_check_tmp"' EXIT
printf 'Checking source %s\n' "$(git rev-parse HEAD)"
python3 tests/CallbackQA/run.py
python3 tests/SchedulingQA/run.py
swiftc -module-cache-path "$task_check_tmp/cache" Shared/BlockingSchedule.swift tests/ScheduleWindowTests.swift -o "$task_check_tmp/schedule"
"$task_check_tmp/schedule"
swiftc -module-cache-path "$task_check_tmp/cache" Tyri/Models/WebsiteDomain.swift Tyri/Models/BlockingEndDescription.swift tests/PapercutTests.swift -o "$task_check_tmp/papercuts"
"$task_check_tmp/papercuts"
printf 'Deterministic checks passed. Simulator, signing, and physical-device checks are separate.\n'
