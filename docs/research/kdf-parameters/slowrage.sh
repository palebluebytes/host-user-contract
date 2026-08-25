#!/usr/bin/env bash
set -u
PW='correct horse battery staple'
for q in 100% 25% 10%; do
  rm -f rq.age
  systemd-run --user --scope -q -p CPUQuota=$q \
    script -qec "rage -p -o rq.age plain.txt" /dev/null <<<"$PW
$PW" >/dev/null 2>&1
  echo "CPUQuota=$q -> rage picked work factor $(sed -n '2p' rq.age | awk '{print $NF}')"
done
