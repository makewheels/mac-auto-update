#!/usr/bin/env python3
"""安全升级 pip 包：只升「同一大版本内」的补丁/次版本。

- 大版本跳级（如 anthropic 0.97 → 2.8、fastapi 0.115 → 0.162）**不自动升**，
  只列出来让人确认，避免依赖被破坏。
- 用法：pip-safe-update.py [--dry-run] [--python /path/to/python3]
"""
import argparse
import json
import re
import subprocess
import sys


def run(cmd, timeout=900):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    return r.returncode, (r.stdout or "") + (r.stderr or "")


def major(v):
    m = re.match(r"(\d+)", v or "")
    return int(m.group(1)) if m else -1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--python", default=sys.executable)
    args = ap.parse_args()

    rc, out = run([args.python, "-m", "pip", "list", "--outdated", "--format=json", "--disable-pip-version-check"])
    try:
        pkgs = json.loads(out[out.find("["):out.rfind("]") + 1])
    except Exception:
        print("读取 pip 过期列表失败")
        return

    safe, risky = [], []
    for p in pkgs:
        name, cur, latest = p.get("name"), p.get("version"), p.get("latest_version")
        (safe if major(cur) == major(latest) else risky).append((name, cur, latest))

    if args.dry_run:
        print(f"同大版本可升（{len(safe)}）：" + ", ".join(f"{n} {c}->{l}" for n, c, l in safe[:40]))
        print(f"跨大版本需确认（{len(risky)}）：" + ", ".join(f"{n} {c}->{l}" for n, c, l in risky[:40]))
        return

    upgraded, failed = [], []
    for name, cur, latest in safe:
        rc, out = run([args.python, "-m", "pip", "install", "--upgrade", "--disable-pip-version-check", f"{name}=={latest}"])
        (upgraded if rc == 0 else failed).append(f"{name} {cur}->{latest}")

    if upgraded:
        print(f"✅ pip 同大版本升级 {len(upgraded)} 个：" + ", ".join(upgraded[:15]) + (" …" if len(upgraded) > 15 else ""))
    if failed:
        print(f"⚠️ pip 升级失败 {len(failed)} 个：" + ", ".join(failed[:8]))
    if risky:
        print(f"⏸ 跨大版本未动（需手动确认）{len(risky)} 个：" + ", ".join(f"{n} {c}->{l}" for n, c, l in risky[:10]) + (" …" if len(risky) > 10 else ""))


if __name__ == "__main__":
    main()