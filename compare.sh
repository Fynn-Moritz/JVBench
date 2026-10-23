#!/usr/bin/env bash
#
# compare.sh - Compares the JMH results of two JDKs taken from the log files
# written by run_all.sh and computes the speedups relative to the "serial" variant.
#
# Usage (from the JVBench root directory):
#   bash compare.sh                          # full, jdk19 vs. jdk27
#   MODE=short bash compare.sh               # evaluate a short run
#   MACHINE=graviton4-metal bash compare.sh  # a specific machine
#   JDK_A=jdk27 JDK_B=jdk27-preferred bash compare.sh
#
# Output: table on screen and in
#   results/<MACHINE>/<MODE>/comparison_<JDK_A>_<JDK_B>.txt (or OUT=...)

set -u

MODE="${MODE:-full}"
JDK_A="${JDK_A:-jdk19}"
JDK_B="${JDK_B:-jdk27}"
RESULT_ROOT="${RESULT_ROOT:-results}"
MACHINE="${MACHINE:-}"
OUT="${OUT:-}"

# Pick the machine automatically if there is exactly one
if [[ -z "$MACHINE" ]]; then
  mapfile -t machines < <(ls -1 "$RESULT_ROOT" 2>/dev/null)
  if [[ ${#machines[@]} -eq 1 ]]; then
    MACHINE="${machines[0]}"
  else
    echo "Please set MACHINE. Available in $RESULT_ROOT: ${machines[*]:-none}"
    exit 1
  fi
fi

base="$RESULT_ROOT/$MACHINE/$MODE"
[[ -d "$base" ]] || { echo "Directory missing: $base"; exit 1; }
OUT="${OUT:-$base/comparison_${JDK_A}_${JDK_B}.txt}"

# Extract the result lines from the logs of one JDK, prefixed with the JDK label
extract() {
  local dir="$base/$1"
  if [[ ! -d "$dir" ]]; then
    echo "Warning: $dir missing" >&2
    return
  fi
  grep -h -E '^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)+ .*(/op|ops/[a-z]+)[[:space:]]*$' "$dir"/*.log 2>/dev/null \
    | tr -d '\r' | sed "s/^/$1 /"
}

{ extract "$JDK_A"; extract "$JDK_B"; } | awk -v A="$JDK_A" -v B="$JDK_B" '
# Line layout: <jdk> <name> [params...] <mode> <cnt> <score> [<+-> <error>] <unit>
# The score can also be non-numeric (e.g. "≈ 10⁻⁴"); such values are reported as n/a.
# Throughput results (unit ops/<t>) are converted to time per operation (<t>/op),
# and the mode is shown next to the name whenever it is not "ss" (SingleShotTime).
function num(x) { return (x ~ /^[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?$/) }
{
  jdk = $1; key = $2; m = 0
  for (i = 3; i <= NF; i++) if ($i ~ /^(thrpt|avgt|sample|ss)$/) { m = i; break }
  if (!m) next
  for (i = 3; i < m; i++) key = key "(" $i ")"
  s = $(m+2); e = ""
  if (NF >= m + 5) e = $(m+4)          # score, +-, error, unit
  gsub(",", ".", s); gsub(",", ".", e)
  if (!num(s)) s = ""
  if (!num(e)) e = ""
  unit = $NF
  if (unit ~ /^ops\//) {                 # throughput -> time per operation
    tu = substr(unit, 5)
    if (s != "" && (s + 0) > 0) {
      if (e != "") e = sprintf("%.3f", (e + 0) / ((s + 0) * (s + 0)))
      s = sprintf("%.3f", 1 / (s + 0))
    }
    unit = tu "/op"
  }
  v[key, jdk] = s; err[key, jdk] = e; u[key, jdk] = unit; n[key] = 1
  if ($m != "ss") md[key] = md[key] (md[key] == "" ? "" : ",") jdk ":" $m
}

# Matching serial method: same class, pattern classes mapped to the standard class
function serialkey(k,   c) {
  c = k
  sub(/\.[^.]*$/, "", c)
  sub(/PatternBenchmark$/, "Benchmark", c)
  return c ".serial"
}

function valid(k, j) { return v[k, j] != "" && (v[k, j] + 0) > 0 }

function speedup(k, j,   sk) {
  sk = serialkey(k)
  if (valid(sk, j) && valid(k, j) && u[sk, j] == u[k, j])
    return sprintf("%6.2f", (v[sk, j] + 0) / (v[k, j] + 0))
  return "   n/a"
}

function show(x) { return (x == "") ? "n/a" : x }
function label(k) { return (md[k] == "") ? k : k " [" md[k] "]" }

END {
  for (k in n) {
    r = (valid(k, A) && valid(k, B) && u[k, A] == u[k, B]) \
        ? sprintf("%6.2f", (v[k, B] + 0) / (v[k, A] + 0)) : "   n/a"
    printf "1|%s|%-50s %9s +- %-7s %-6s %9s +- %-7s %-6s %s\n", \
      k, label(k), show(v[k, A]), show(err[k, A]), u[k, A], show(v[k, B]), show(err[k, B]), u[k, B], r
    mth = k; sub(/^.*\./, "", mth); sub(/\(.*$/, "", mth)
    if (mth != "serial")
      printf "2|%s|%-50s %10s %10s\n", k, label(k), speedup(k, A), speedup(k, B)
  }
}' | sort -t'|' -k1,1 -k2,2 | awk -F'|' -v A="$JDK_A" -v B="$JDK_B" '
$1 != sec {
  sec = $1
  if (sec == 1) {
    print "Absolute times (lower = faster), ratio = " B " / " A
    printf "%-50s %28s %28s %6s\n", "Benchmark", A, B, B "/" A
  } else {
    print ""
    print "Speedup relative to serial of the same JDK (higher = better)"
    printf "%-50s %10s %10s\n", "Benchmark", A, B
  }
}
{ print $3 }' | tee "$OUT"

echo
echo "Saved to: $OUT"
