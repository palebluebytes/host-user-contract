#!/usr/bin/env bash
# The full greeter cost the user pays: posture verify, then unwrap. Sequential.
set -u
t0=$(date +%s.%N)
perl verify.pl <in.txt
t1=$(date +%s.%N)
script -qec "age -d k.age" /dev/null <pw.txt >/dev/null 2>&1
t2=$(date +%s.%N)
echo "verify: $(echo "$t1-$t0" | bc -l) s"
echo "unwrap: $(echo "$t2-$t1" | bc -l) s"
echo "TOTAL : $(echo "$t2-$t0" | bc -l) s"
