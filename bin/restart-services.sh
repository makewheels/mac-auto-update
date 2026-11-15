#!/bin/bash
# 每天 05:00 重启「当前正在运行」的 Homebrew 服务，让升级后的二进制生效。
# 没在跑的服务一律不动（不会顺手启动）。
# 成功：完全静默；失败才输出。
# 日志：~/Library/Logs/mac-auto-update/  保留 3 天

LOG_DIR="$HOME/Library/Logs/mac-auto-update"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/$(date +%Y%m%d).log"
BREW=/opt/homebrew/bin/brew

# 只取 brew services 里状态为 started 的；不信 LaunchAgents 文件名
SERVICES=$("$BREW" services list 2>/dev/null | awk 'NR>1 && $2=="started" {print $1}')

[ -z "$SERVICES" ] && exit 0

FAILED=""
{
  echo "=== restart $(date '+%F %T')"
  for s in $SERVICES; do
    echo "--- $s"
    if "$BREW" services restart "$s" >>"$LOG" 2>&1; then
      echo "  ok"
    else
      echo "  FAILED"
      FAILED="$FAILED $s"
    fi
  done
  echo "=== done $(date '+%F %T')"
} >>"$LOG" 2>&1

find "$LOG_DIR" -name '*.log' -type f -mtime +3 -delete 2>/dev/null

if [ -n "$FAILED" ]; then
  echo "⚠️ 服务重启失败：$FAILED"
  echo "日志：$LOG"
fi
# 成功时什么都不输出 → cron 不推送