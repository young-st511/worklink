"""Finite, local-only lsof cost probe. Discards all socket/process listings."""
import json
import os
import resource
import subprocess
import sys
import time

if sys.platform != "darwin":
    raise SystemExit("This probe requires macOS; RSS units and lsof location are macOS-specific.")

duration, interval = 30, 5
before_self = resource.getrusage(resource.RUSAGE_SELF)
before_child = resource.getrusage(resource.RUSAGE_CHILDREN)
start = time.monotonic()
statuses = []
for index in range(duration // interval):
    time.sleep(max(0, start + index * interval - time.monotonic()))
    try:
        result = subprocess.run(
            ["/usr/sbin/lsof", "-nP", "-a", "-u", str(os.getuid()), "-iTCP", "-sTCP:LISTEN"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=3,
        )
        statuses.append(result.returncode)
    except subprocess.TimeoutExpired:
        statuses.append("timeout")
time.sleep(max(0, start + duration - time.monotonic()))
elapsed = time.monotonic() - start
after_self = resource.getrusage(resource.RUSAGE_SELF)
after_child = resource.getrusage(resource.RUSAGE_CHILDREN)

def cpu(value):
    return value.ru_utime + value.ru_stime

self_cpu = cpu(after_self) - cpu(before_self)
child_cpu = cpu(after_child) - cpu(before_child)
print(json.dumps({
    "mode": "local-lsof-current-user",
    "elapsed_seconds": elapsed,
    "interval_seconds": interval,
    "invocations": len(statuses),
    "exit_statuses": statuses,
    "parent_cpu_seconds_excluding_startup": self_cpu,
    "children_cpu_seconds": child_cpu,
    "combined_cpu_percent_one_core": (self_cpu + child_cpu) / elapsed * 100,
    "parent_peak_rss_bytes_including_startup": after_self.ru_maxrss,
    "child_peak_rss_bytes": after_child.ru_maxrss,
    "scope": "Local Python harness and its lsof children only; not the office Mac, SSH or Tailscale. No socket listing retained.",
}, indent=2, sort_keys=True))
