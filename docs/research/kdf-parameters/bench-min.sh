#!/usr/bin/env bash
# Min-of-N: min approximates the uncontended cost, max shows what contention does.
set -u
export LC_ALL=C
PW='correct horse battery staple'
echo "load at start: $(cut -d' ' -f1-3 /proc/loadavg)"
echo
echo "== perl crypt verify (the greeter's real path), min/median/max of N =="
for R in 5 7 9 11; do
  hash=$(printf '%s' "$PW" | mkpasswd -m yescrypt -R "$R" -s)
  n=15
  [ "$R" = 11 ] && n=7
  perl -e '
    use Time::HiRes qw(time);
    my ($pw,$stored,$n,$R) = @ARGV;
    my @t;
    for (1..$n) { my $a=time; crypt($pw,$stored); push @t, (time-$a)*1000; }
    @t = sort { $a <=> $b } @t;
    printf("R=%-3s %-9s min=%7.1f ms  med=%7.1f ms  max=%7.1f ms  (n=%d)\n",
      $R, (split /\$/, $stored)[1].q{/}.(split /\$/, $stored)[2], $t[0], $t[int(@t/2)], $t[-1], $n);
  ' "$PW" "$hash" "$n" "$R"
done
echo
echo "== age -d (Go scrypt logN=18, 256 MiB), min/median/max, startup subtracted =="
printf 'age-identity-plaintext-stand-in\n' >plain.txt
script -qec "age -p -o k.age plain.txt" /dev/null <<<"$PW
$PW" >/dev/null 2>&1
best=999
worst=0
sum=0
n=7
for _ in $(seq 1 "$n"); do
  t0=$(date +%s.%N)
  script -qec "age -d k.age" /dev/null <<<"$PW" >/dev/null 2>&1
  t1=$(date +%s.%N)
  d=$(echo "$t1 - $t0 - 0.033" | bc -l)
  sum=$(echo "$sum + $d" | bc -l)
  best=$(echo "if ($d < $best) $d else $best" | bc -l)
  worst=$(echo "if ($d > $worst) $d else $worst" | bc -l)
done
printf "logN=18   min=%7.3f s   mean=%7.3f s   max=%7.3f s  (n=%d)\n" "$best" "$(echo "$sum/$n" | bc -l)" "$worst" "$n"
echo
echo "load at end: $(cut -d' ' -f1-3 /proc/loadavg)"
