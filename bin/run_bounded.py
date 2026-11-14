#!/usr/bin/env python3
"""带超时运行一个命令：超时返回 124，不阻塞定时任务。"""
import subprocess
import sys

if len(sys.argv) < 2:
    sys.exit(2)

try:
    r = subprocess.run(sys.argv[1:], capture_output=True, text=True, timeout=900)
    sys.stdout.write(r.stdout or "")
    sys.stderr.write(r.stderr or "")
    sys.exit(r.returncode)
except subprocess.TimeoutExpired:
    print("TIMEOUT (900s)")
    sys.exit(124)
except FileNotFoundError:
    print("NOT_FOUND")
    sys.exit(127)