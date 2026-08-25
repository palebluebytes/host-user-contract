#!/usr/bin/env bash
# Measure mkpasswd -m yescrypt at a range of costs: emitted prefix, wall clock, peak RSS.
set -u
PW='correct horse battery staple'
ITERS=${ITERS:-20}

# baseline: process startup cost of mkpasswd itself
t0=$(date +%s.%N)
for _ in $(seq 1 "$ITERS"); do mkpasswd --version >/dev/null 2>&1; done
t1=$(date +%s.%N)
BASE=$(echo "($t1 - $t0) / $ITERS * 1000" | bc -l)
printf 'baseline (mkpasswd --version, %d iters): %.2f ms\n\n' "$ITERS" "$BASE"

printf '%-4s %-10s %-12s %-12s %-10s\n' cost prefix 'mean ms' 'net ms' 'peakRSS KiB'
for R in 1 3 5 7 9 11; do
  hash=$(printf '%s' "$PW" | mkpasswd -m yescrypt -R "$R" -s 2>/dev/null)
  prefix=$(printf '%s' "$hash" | cut -d'$' -f1-4)
  n=$ITERS
  case "$R" in 11) n=5 ;; 9) n=10 ;; esac
  t0=$(date +%s.%N)
  for _ in $(seq 1 "$n"); do printf '%s' "$PW" | mkpasswd -m yescrypt -R "$R" -s >/dev/null; done
  t1=$(date +%s.%N)
  mean=$(echo "($t1 - $t0) / $n * 1000" | bc -l)
  net=$(echo "$mean - $BASE" | bc -l)
  rss=$(printf '%s' "$PW" | /usr/bin/time -f '%M' mkpasswd -m yescrypt -R "$R" -s 2>&1 >/dev/null | tail -1)
  printf '%-4s %-10s %-12.1f %-12.1f %-10s  (n=%d)\n' "$R" "\$$prefix\$" "$mean" "$net" "$rss" "$n"
done
