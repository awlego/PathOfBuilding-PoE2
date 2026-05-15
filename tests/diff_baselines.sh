#!/usr/bin/env bash
# Usage: ./diff_baselines.sh <step0.tsv> <step1.tsv>
# Joins on (build, stat), prints total_ms before/after and the delta.
# Also diffs the matching .fp.tsv files and prints a one-line pass/fail.
set -uo pipefail

a="$1"
b="$2"

printf "%-30s | %-22s | %8s | %8s | %s\n" "build" "stat" "before" "after" "delta"
printf -- "---------------------------------------------------------------------------------------\n"
# Compose a (build|stat) key so duplicate builds don't fan out in the join.
mk() { tail -n +2 "$1" | awk -F'\t' '{ printf "%s|%s\t%s\n", $1, $2, $4 }' | sort; }
join -t $'\t' <(mk "$a") <(mk "$b") \
| awk -F'\t' '{ split($1, k, "|"); d=$3-$2; pct=($2 ? int(100*d/$2) : 0); printf "%-30s | %-22s | %8d | %8d | %+d ms (%+d%%)\n", k[1], k[2], $2, $3, d, pct }'

printf "\n"

fa="${a%.tsv}.fp.tsv"
fb="${b%.tsv}.fp.tsv"
if diff -q "$fa" "$fb" >/dev/null 2>&1; then
  echo "FINGERPRINTS IDENTICAL: $fa == $fb"
else
  echo "FINGERPRINTS DIFFER — calc regression detected"
  diff "$fa" "$fb" | head -40
fi
