#!/usr/bin/env bash
# Check Approval.tla under each implementation choice, one property at a time.
# Needs Java 11+ and tla2tools.jar:
#   curl -LO https://github.com/tlaplus/tlaplus/releases/latest/download/tla2tools.jar
#   ./run.sh
# To check one configuration directly (both properties, first violation wins):
#   java -cp tla2tools.jar tlc2.TLC -workers 1 -config 1_after_snapshot.cfg Approval.tla
set -u
cd "$(dirname "$0")"
JAR="${TLA2TOOLS:-tla2tools.jar}"

# check <row> <property>: runs the row's .cfg with only that property; prints the verdict.
# Leaves _<row>_<property>.log behind — when a property fails, the log holds the interleaving.
check() {
  local row=$1 prop=$2 tmp="_${1}_${2}"
  awk -v p="$prop" '/^    (AtMostOnce|NoResurrection)$/ {next} {print} /^INVARIANTS$/ {print "    " p}' \
    "$row.cfg" > "$tmp.cfg"
  java -XX:+UseParallelGC -cp "$JAR" tlc2.TLC -workers 1 -cleanup -config "$tmp.cfg" Approval.tla \
    > "$tmp.log" 2>&1
  rm -f "$tmp.cfg" Approval_TTrace_*          # TLC's trace-spec files; the .log has the trace
  if grep -q "No error has been found" "$tmp.log"; then
    echo "holds"
  else
    printf 'violated in %s steps' "$(grep -c '^State [0-9]*:' "$tmp.log")"
  fi
}

for row in 1_after_snapshot 2_after_fresh 3_before_fresh 4_cas 5_before_serialized; do
  printf '%-22s AtMostOnce: %-21s NoResurrection: %s\n' \
    "$row" "$(check "$row" AtMostOnce)" "$(check "$row" NoResurrection)"
done
rm -rf states
