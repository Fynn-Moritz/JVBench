#!/usr/bin/env bash
#
# run_all.sh - Runs all JVBench benchmarks for one or more JDKs
# and stores every result in its own JSON and log file.
#
# Usage (from the JVBench root directory):
#   bash run_all.sh                       # short run (default)
#   MODE=full bash run_all.sh             # configuration from the annotations (5 forks, 10/10)
#   FILTER=Blackscholes bash run_all.sh   # only benchmarks matching the regex
#   JDKS="jdk27" bash run_all.sh          # only one JDK
#   DRYRUN=1 bash run_all.sh              # only list what would run
#   VARIANTS='.*' bash run_all.sh         # disable the variant filter (all methods)
#   PIN_CPU=2-5 bash run_all.sh           # Linux: run all JVMs on CPUs 2-5 (taskset)
#
# Expects:
#   jars/JVBench-jdk19.jar, jars/JVBench-jdk27.jar
#   tools/SpeciesInfo.java
#
# Existing result files are skipped, so an interrupted run can be resumed.

set -u

# ---------- Configuration ----------
MODE="${MODE:-short}"
JDKS="${JDKS:-jdk27 jdk19}"
JDK19_HOME="${JDK19_HOME:-/c/Program Files/Java/jdk-19}"
JDK27_HOME="${JDK27_HOME:-/c/Program Files/Java/jdk-27}"
JAR_DIR="${JAR_DIR:-jars}"
RESULT_ROOT="${RESULT_ROOT:-results}"
MACHINE="${MACHINE:-$(hostname)}"
FILTER="${FILTER:-}"
# Only methods with these suffixes; VARIANTS='.*' disables the filter
VARIANTS="${VARIANTS:-(serial|autoVec|explicitVec|fullVec|[Ii]ndexInRange)\$}"
# DRYRUN=1 only lists the selected benchmarks without running them
DRYRUN="${DRYRUN:-0}"
# Linux only: CPU list for taskset, e.g. "2-5". Empty = no pinning.
# Use at least 2 CPUs: with fewer, the JVM picks different defaults (e.g. the GC).
PIN_CPU="${PIN_CPU:-}"

case "$MODE" in
  short) JMH_OPTS=(-f 1 -wi 1 -i 2) ;;
  full)  JMH_OPTS=() ;;
  *) echo "Unknown MODE '$MODE' (allowed: short, full)"; exit 1 ;;
esac

RUNNER=()
if [[ -n "$PIN_CPU" ]]; then
  if ! command -v taskset >/dev/null 2>&1; then
    echo "PIN_CPU is set, but taskset is not available (Linux only)"; exit 1
  fi
  RUNNER=(taskset -c "$PIN_CPU")
fi

# ---------- Helper functions ----------
jdk_home() {
  case "$1" in
    jdk19) echo "$JDK19_HOME" ;;
    jdk27) echo "$JDK27_HOME" ;;
    *) return 1 ;;
  esac
}

write_metadata() {
  local jdk="$1" java_bin="$2" jar="$3" out_dir="$4"
  local meta="$out_dir/_metadata_$(date '+%Y%m%d_%H%M%S').txt"
  {
    echo "Date:        $(date '+%Y-%m-%d %H:%M:%S %z')"
    echo "Machine:     $MACHINE"
    echo "JDK label:   $jdk"
    echo "Mode:        $MODE (JMH options: ${JMH_OPTS[*]:-from annotations})"
    echo "CPU pinning: ${PIN_CPU:-none} (available CPUs: $(${RUNNER[@]+"${RUNNER[@]}"} nproc))"
    echo "JAR:         $jar"
    echo "JAR sha256:  $(sha256sum "$jar" | cut -d' ' -f1)"
    echo "Git commit:  $(git rev-parse HEAD 2>/dev/null || echo unknown)"
    echo "Local changes:"
    git status --porcelain 2>/dev/null | sed 's/^/  /'
    echo
    echo "== java -version =="
    "$java_bin" -version 2>&1
    echo
    echo "== JVM vector flags =="
    # UseSVE/UseNeon exist only on aarch64, UseAVX only on x86; missing flags are simply not listed.
    # Run with the same pinning as the benchmarks, because CPU count affects JVM defaults (GC, heap).
    ${RUNNER[@]+"${RUNNER[@]}"} "$java_bin" -XX:+PrintFlagsFinal -version 2>/dev/null | tr -d '\r' \
      | grep -E '[[:space:]](UseSVE|UseNeon|MaxVectorSize|UseSuperWord|UseAVX|UseSSE|UseSerialGC|UseParallelGC|UseG1GC|UseZGC|MaxHeapSize)[[:space:]]'
    echo
    echo "== Vector species =="
    ${RUNNER[@]+"${RUNNER[@]}"} "$java_bin" --add-modules jdk.incubator.vector tools/SpeciesInfo.java 2>&1
    echo
    echo "== OS =="
    uname -a
    if [[ -r /etc/os-release ]]; then
      grep -E '^(PRETTY_NAME|VERSION_ID)=' /etc/os-release
    fi
    echo
    echo "== CPU =="
    if command -v lscpu >/dev/null 2>&1; then
      lscpu
    else
      grep -m1 '^model name' /proc/cpuinfo 2>/dev/null
      grep -m1 -E '^(flags|Features)' /proc/cpuinfo 2>/dev/null
    fi
  } > "$meta"
  echo "[$jdk] Metadata: $meta"
}

# ---------- Main loop ----------
total_ok=0; total_fail=0; total_skip=0
start_all=$SECONDS
summary_dir="$RESULT_ROOT/$MACHINE/$MODE"

for jdk in $JDKS; do
  home="$(jdk_home "$jdk")" || { echo "Unknown JDK label: $jdk"; continue; }
  java_bin="$home/bin/java"
  jar="$JAR_DIR/JVBench-$jdk.jar"
  out_dir="$summary_dir/$jdk"

  if ! "$java_bin" -version >/dev/null 2>&1; then
    echo "[$jdk] Java not found: $java_bin"; continue
  fi
  if [[ ! -f "$jar" ]]; then
    echo "[$jdk] JAR missing: $jar"; continue
  fi

  if [[ "$DRYRUN" != "1" ]]; then
    mkdir -p "$out_dir"
    write_metadata "$jdk" "$java_bin" "$jar" "$out_dir"
  fi

  # Get the benchmark list from the JAR (strip \r because of Windows line endings)
  mapfile -t benchmarks < <("$java_bin" --add-modules jdk.incubator.vector -jar "$jar" -l 2>/dev/null \
                              | tr -d '\r' | grep -E '^jvbench\.')
  if [[ -n "$FILTER" ]]; then
    mapfile -t benchmarks < <(printf '%s\n' "${benchmarks[@]}" | grep -E "$FILTER")
  fi
  mapfile -t benchmarks < <(printf '%s\n' "${benchmarks[@]}" | grep -E "$VARIANTS")
  echo "[$jdk] ${#benchmarks[@]} benchmarks, results in $out_dir"

  if [[ "$DRYRUN" == "1" ]]; then
    printf '  %s\n' "${benchmarks[@]}"
    continue
  fi

  for bm in "${benchmarks[@]}"; do
    out="$out_dir/$bm.json"
    log="$out_dir/$bm.log"

    if [[ -s "$out" ]]; then
      echo "  skipped (exists): $bm"
      total_skip=$((total_skip + 1))
      continue
    fi

    regex="^${bm//./\\.}\$"   # exactly this one method
    t0=$SECONDS
    printf '  %-60s ' "$bm"
    if ${RUNNER[@]+"${RUNNER[@]}"} "$java_bin" --add-modules jdk.incubator.vector -jar "$jar" "$regex" \
         ${JMH_OPTS[@]+"${JMH_OPTS[@]}"} -rf json -rff "$out" >"$log" 2>&1 \
       && [[ -s "$out" ]]; then
      echo "ok ($((SECONDS - t0)) s)"
      total_ok=$((total_ok + 1))
    else
      echo "FAILED ($((SECONDS - t0)) s), see $log"
      rm -f "$out"
      echo "$jdk $bm" >> "$summary_dir/failed.txt"
      total_fail=$((total_fail + 1))
    fi
  done
done

echo
echo "Finished after $(( (SECONDS - start_all) / 60 )) min: $total_ok ok, $total_fail failed, $total_skip skipped."
if [[ $total_fail -gt 0 ]]; then
  echo "Failed benchmarks: $summary_dir/failed.txt"
fi
