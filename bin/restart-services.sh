#!/bin/bash
# 每天 05:00 重启 Homebrew 服务，让升级后的二进制生效。
# 只重启「当前是 started」的服务；没在跑的不动（不会顺手启动）。
# 日志：~/Library/Logs/mac-auto-update/services.log  保留 3 天
# 输出：只有重启过或失败时才打印

LOG_DIR="$HOME/Library/Logs/mac-auto-update"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/$(date +%Y%m%d).log"
BREW=/opt/homebrew/bin/brew

SERVICES=$(/bin/ls "$HOME/Library/LaunchAgents" 2>/dev/null | sed -n 's/^homebrew\.mxcl\.\(.*\)\.plist$/\1/p' | sort -u)

[ -z "$SERVICES" ] && { echo "没有正在运行的 brew 服务"; exit 0; }

{
  echo "=== restart $(date '+%F %T')"
  for s in $SERVICES; do
    echo "--- $s"
    "$BREW" services restart "$s" 2>&1
  done
  echo "=== done $(date '+%F %T')"
} >>"$LOG" 2>&1
RC=$?

find "$LOG_DIR" -name '*.log' -type f -mtime +3 -delete 2>/dev/null

if [ $RC -ne 0 ]; then
  echo "⚠️ 服务重启有失败（rc=$RC）：$(grep -iE 'error|failed' "$LOG" | tail -3 | tr '\n' ' ')"
  echo "日志：$LOG"
else
  echo "✅ 已重启服务：$(echo $SERVICES | tr '\n' ' ')"
fi