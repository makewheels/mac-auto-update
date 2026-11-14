#!/bin/bash
# 每周自动更新 Homebrew CLI 工具（不碰 GUI 应用、不碰 Hermes、不碰 Clash）
# 日志：~/Library/Logs/brew-autoupdate/  保留 3 天
# 行为：stdout 只在「有升级」或「有报错」时输出摘要（Hermes cron 用它决定要不要通知）
# 用法：brew-autoupdate.sh [--dry-run]

LOG_DIR="$HOME/Library/Logs/brew-autoupdate"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/$(date +%Y%m%d-%H%M).log"
BREW=/opt/homebrew/bin/brew

BEFORE=$("$BREW" outdated --formula 2>/dev/null)

{
  echo "=== start $(date '+%F %T')"
  "$BREW" update
  if [ "${1:-}" = "--dry-run" ]; then
    echo "--- dry-run：不执行升级"
  else
    echo "--- upgrade"
    "$BREW" upgrade --formula
    echo "--- cleanup"
    "$BREW" cleanup -s
  fi
  echo "--- outdated after:"
  "$BREW" outdated --formula
  echo "=== done $(date '+%F %T')"
} >>"$LOG" 2>&1
RC=$?

AFTER=$("$BREW" outdated --formula 2>/dev/null)

# 保留最近 3 天
find "$LOG_DIR" -name '*.log' -type f -mtime +3 -delete 2>/dev/null

if [ "${1:-}" = "--dry-run" ]; then
  [ -n "$BEFORE" ] && echo "待更新（dry-run）：$BEFORE"
  exit 0
fi

if [ $RC -ne 0 ]; then
  echo "⚠️ 自动更新失败（rc=$RC）"
  grep -iE "error|failed|fatal" "$LOG" | tail -5
  echo "日志：$LOG"
  exit 0
fi

if [ -n "$BEFORE" ] && [ "$BEFORE" != "$AFTER" ]; then
  UPGRADED=$(printf '%s\n' "$BEFORE" | grep -vxF "$AFTER" | tr '\n' ' ')
  echo "✅ Homebrew 自动更新完成：$UPGRADED"
  echo "日志：$LOG"
fi
# 没有升级、没有报错 → 不输出，cron 不打扰