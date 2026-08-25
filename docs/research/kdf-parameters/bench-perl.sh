#!/usr/bin/env bash
# The greeter's real verification path: perl crypt($password, $stored).
# Measures verify cost + peak RSS at each yescrypt cost, and confirms round-trip.
set -u
PW='correct horse battery staple'
for R in 5 7 9 11; do
  hash=$(printf '%s' "$PW" | mkpasswd -m yescrypt -R "$R" -s)
  n=10
  [ "$R" = 11 ] && n=5
  out=$(perl -e '
    use Time::HiRes qw(time);
    my ($pw,$stored,$n) = @ARGV;
    my $c;
    my $t0 = time;
    for (1..$n) { $c = crypt($pw, $stored); }
    my $t1 = time;
    printf("%.1f %s", ($t1-$t0)/$n*1000, ($c eq $stored) ? "MATCH" : "MISMATCH($c)");
  ' "$PW" "$hash" "$n")
  # negative case: wrong password must not match
  neg=$(perl -e 'my ($pw,$stored)=@ARGV; print((crypt($pw,$stored) eq $stored) ? "BAD-ACCEPTED" : "rejected");' "wrong password" "$hash")
  # shellcheck disable=SC2016  # perl source, deliberately unexpanded
  rss=$(/usr/bin/time -f '%M' perl -e 'crypt($ARGV[0],$ARGV[1])' "$PW" "$hash" 2>&1 >/dev/null | tail -1)
  echo "R=$R prefix=$(echo "$hash" | cut -d'$' -f1-3)\$ verify_ms=${out%% *} roundtrip=${out##* } wrongpw=$neg peakRSS_KiB=$rss (n=$n)"
done
echo "---"
perl -e 'print "perl $] libc crypt via ", (eval { require Config; $Config::Config{libs} } // "?"), "\n"' 2>/dev/null
perl -V:version 2>/dev/null
