# age's scrypt stanza params: r=8, p=1, dkLen=32, salt = "age-encryption.org/v1/scrypt" || 16 random bytes
import hashlib
import os
import time
import resource

pw = b"correct horse battery staple"
label = b"age-encryption.org/v1/scrypt"
print(f"{'logN':<6}{'memory':<12}{'mean s':<10}{'peak RSS MiB':<14}")
for logN in (14, 16, 17, 18, 19):
    N = 1 << logN
    salt = label + os.urandom(16)
    n = 3 if logN <= 18 else 1
    t0 = time.perf_counter()
    for _ in range(n):
        hashlib.scrypt(pw, salt=salt, n=N, r=8, p=1, dklen=32, maxmem=2147483646)
    t1 = time.perf_counter()
    rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024
    mem = 128 * N * 8 / (1 << 20)
    print(f"{logN:<6}{mem:>6.0f} MiB   {(t1 - t0) / n:<10.3f}{rss:<14.0f}")
