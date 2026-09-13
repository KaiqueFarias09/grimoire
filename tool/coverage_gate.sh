#!/bin/sh
# Coverage non-regression gate for e_livre_viewer.
#
# Runs the test suite with coverage, then fails when the line coverage
# of the package's own Dart sources drops below the floor.
#
#   tool/coverage_gate.sh [floor_percent]
#
# The floor defaults to 72.8 — the measured coverage of the snapshot
# baseline this quality candidate started from (the deterministic-test
# rework had let it slip to 71.65%). Generated code is excluded from
# the sum (see $_exclude), and test/helper files are never counted
# because lcov only records lib/ sources here.
#
# Requirements: flutter on PATH, python3 for the lcov sum.
set -eu

floor="${1:-72.8}"
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

# Sources excluded from the coverage sum: build_runner output and
# vendored snippets. Keep this list in sync with the repository's
# codegen conventions.
_exclude='\.g\.dart$|\.freezed\.dart$|\.gr\.dart$'

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

echo "Running flutter test --coverage (floor: ${floor}%)..."
flutter test --coverage > "$tmp" 2>&1 || {
  echo "FAIL: the test suite did not pass; coverage is meaningless."
  tail -n 20 "$tmp"
  exit 1
}
tail -n 1 "$tmp"

python3 - "$floor" "$_exclude" <<'PYEOF'
import re
import sys

floor = float(sys.argv[1])
exclude = re.compile(sys.argv[2])

total_hit = 0
total_found = 0
current = None
skip = False
for line in open('coverage/lcov.info'):
    if line.startswith('SF:'):
        current = line.strip()[3:]
        skip = bool(exclude.search(current))
    elif line.startswith('LF:') and not skip:
        total_found += int(line.split(':')[1])
    elif line.startswith('LH:') and not skip:
        total_hit += int(line.split(':')[1])

pct = 100.0 * total_hit / total_found if total_found else 0.0
print(f"coverage: {pct:.2f}% ({total_hit}/{total_found} lines, floor {floor}%)")
if pct < floor:
    print(f"FAIL: coverage {pct:.2f}% is below the {floor}% floor.")
    sys.exit(1)
print("OK: coverage gate passed.")
PYEOF
