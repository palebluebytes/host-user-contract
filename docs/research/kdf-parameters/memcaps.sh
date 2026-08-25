#!/usr/bin/env bash
# MemoryMax thresholds and the failure mode, for both sides of the pair.
# Hashes reach perl on STDIN, never as argv: systemd-run expands `$` in command
# arguments, which mangles a `$y$…` hash into a false pass. See ../README.md.
set -u
export LC_ALL=C
PW='correct horse battery staple'
here=$(cd "$(dirname "$0")" && pwd)

run() { systemd-run --user --scope -q -p MemoryMax="$1" -p MemorySwapMax=0 "${@:2}"; }

echo "== sanity: is MemoryMax applied at all? (200 MiB alloc under a 4 MiB cap) =="
# shellcheck disable=SC2016  # perl source, deliberately unexpanded by the shell
out=$(run 4M perl -e 'my $x = "a" x (200*1024*1024); print "ALLOCATED"' 2>/dev/null)
echo "  ${out:-<killed — cap is live>}"

for R in 7 9; do
  hash=$(printf '%s' "$PW" | mkpasswd -m yescrypt -R "$R" -s)
  printf '%s\n%s\n' "$PW" "$hash" >"in$R.txt"
  echo
  echo "== perl crypt, yescrypt cost $R ($(printf '%s' "$hash" | cut -d'$' -f1-3)\$) =="
  for cap in 1024M 512M 320M 288M 272M 256M 192M 128M 96M 80M 72M 64M 48M; do
    out=$(run "$cap" perl "$here/verify.pl" <"in$R.txt" 2>/dev/null)
    echo "  $cap -> ${out:-<killed, no diagnostic>}"
  done
done

echo
echo "== age -d, scrypt logN=18 (needs k.age from bench-min.sh) =="
for cap in 512M 384M 352M 320M 304M 288M 272M 256M 192M 128M; do
  out=$(run "$cap" script -qec "age -d k.age" /dev/null <<<"$PW" 2>&1)
  echo "  $cap -> $(echo "$out" | grep -q 'stand-in' && echo OK || echo '<killed, no diagnostic>')"
done
