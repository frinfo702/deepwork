#!/bin/sh
# Before/after benchmark: bench/run.sh [base-ref]   (default base: main)
# Builds Sources/ at the base ref and in the working tree, runs bench/Bench.swift against
# each, and prints a Markdown table. Tab rows need a running browser this terminal is
# already allowed to script under Automation (it never asks); it only reads tab URLs.
set -e
cd "$(dirname "$0")/.."
BASE=${1:-main}
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"; defaults delete deepwork-bench 2>/dev/null || true' EXIT

run() { # $1 = name, $2 = Sources dir
  dir=$OUT/$1; mkdir -p "$dir"
  flags=""; grep -q 'actor TabGuard' "$2"/*.swift && flags="-D HAS_TABGUARD"
  swiftc -O -parse-as-library -swift-version 5 -enable-testing -module-name Deepwork \
    -emit-library -emit-module -emit-module-path "$dir/Deepwork.swiftmodule" \
    -Xfrontend -entry-point-function-name -Xfrontend deepwork_main \
    "$2"/*.swift -o "$dir/libDeepwork.dylib" 2>/dev/null
  swiftc -O -parse-as-library -swift-version 5 $flags -I "$dir" -L "$dir" -lDeepwork \
    -Xlinker -rpath -Xlinker "$dir" bench/Bench.swift -o "$dir/deepwork-bench" 2>/dev/null
  echo "running $1..." >&2
  "$dir/deepwork-bench" > "$OUT/$1.tsv"
}

mkdir -p "$OUT/base-src"
git archive "$BASE" Sources | tar -x -C "$OUT/base-src"
run before "$OUT/base-src/Sources"
run after Sources

v() { awk -F'\t' -v k="$2" '$1 == k { printf "%.2f", $2; f = 1 } END { if (!f) printf "n/a" }' "$OUT/$1.tsv"; }
row() { # $1 = label, $2 = key
  b=$(v before "$2"); a=$(v after "$2")
  d=$(awk -v b="$b" -v a="$a" 'BEGIN { if (b == "n/a" || a == "n/a") print "–"; else if (a == 0 && b > 0) print "eliminated"; else if (b > a * 1.05) printf "%.1f× less", b / a; else if (a > b * 1.05) printf "%.1f× more", a / b; else print "same" }')
  echo "| $1 | $b | $a | $d |"
}

echo
echo "Base: \`$(git rev-parse --short "$BASE")\` vs working tree · $(sysctl -n machdep.cpu.brand_string) · $(sw_vers -productVersion)"
echo
echo "| Metric | Before | After | Change |"
echo "|---|---|---|---|"
row "Tab check: main thread blocked per tick (ms)" tab_main_ms
row "Tab check: total time per tick (ms, off main after)" tab_total_ms
row "Idle Store invalidations per second" idle_changes_per_s
row "\`ASCIIArt.cloud\` 52×17 per frame (µs)" ascii_us
row "\`Store.activeSchedule\`, 5 schedules (µs)" active_schedule_us
echo "| Timer tolerance (s, lets macOS coalesce wakeups) | $(v before timer_tolerance_s) | $(v after timer_tolerance_s) | – |"
echo
echo "Browsers scripted in tab rows: $(v after tab_browsers | cut -d. -f1)"
