#!/bin/bash
# 每天自动更新：
#   1) Homebrew CLI 工具（brew upgrade --formula）+ 清缓存
#   2) Claude Code / Codex CLI（用它们自己的 update 命令）
# 不碰：GUI 应用（cask）、Clash 等网络工具、Hermes 本体
#
# 日志：~/Library/Logs/brew-autoupdate/  保留 3 天
# 输出：只有「有升级」或「有失败」时才打印（Hermes cron 用它决定是否通知）
# 用法：brew-autoupdate.sh [--dry-run]

LOG_DIR="$HOME/Library/Logs/brew-autoupdate"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/$(date +%Y%m%d-%H%M).log"
BREW=/opt/homebrew/bin/brew
PY=/usr/bin/python3
DIR="$(cd "$(dirname "$0")" && pwd)"
BOUNDED="$DIR/run_bounded.py"
DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

BEFORE=$("$BREW" outdated --formula 2>/dev/null)
NPM_BEFORE=$(/opt/homebrew/bin/npm ls -g --depth=0 2>/dev/null)

{
  echo "=== start $(date '+%F %T')"
  echo "--- brew update"
  "$BREW" update
  echo "--- outdated before:"
  "$BREW" outdated --formula

  if [ $DRY -eq 1 ]; then
    echo "--- dry-run：不执行升级"
  else
    echo "--- brew upgrade --formula"
    "$BREW" upgrade --formula
    echo "--- brew cleanup -s"
    "$BREW" cleanup -s

    echo "--- npm update -g（逐包排除正在运行的 codex/claude）"
    NPM=/opt/homebrew/bin/npm
    PKGS=$("$NPM" ls -g --depth=0 --json 2>/dev/null | "$PY" -c 'import json,sys;d=json.load(sys.stdin);print(" ".join(sorted(d.get("dependencies",{}))))')
    BUSY=""
    # npm / corepack 归 brew 的 node 管，不由 npm 自更新
    PKGS=$(echo "$PKGS" | sed 's|npm||; s|corepack||')
    if pgrep -f "/opt/homebrew/lib/node_modules/@openai/codex/bin" >/dev/null 2>&1; then
      PKGS=$(echo "$PKGS" | sed 's|@openai/codex||'); BUSY="$BUSY codex"
    fi
    if pgrep -f "/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/bin" >/dev/null 2>&1; then
      PKGS=$(echo "$PKGS" | sed 's|@anthropic-ai/claude-code||'); BUSY="$BUSY claude"
    fi
    [ -n "$BUSY" ] && echo "SKIP-busy:$BUSY （运行中，本次不动它，其余照常）"
    if [ -n "$(echo "$PKGS" | tr -d ' ')" ]; then
      "$PY" "$BOUNDED" "$NPM" update -g $PKGS
      echo "npm rc=$?"
    else
      echo "SKIP-none: 没有可更新的包"
    fi
  fi

  echo "--- outdated after:"
  "$BREW" outdated --formula
  echo "=== done $(date '+%F %T')"
} >>"$LOG" 2>&1
RC=$?

AFTER=$("$BREW" outdated --formula 2>/dev/null)
NPM_AFTER=$(/opt/homebrew/bin/npm ls -g --depth=0 2>/dev/null)

# 只保留最近 3 天
find "$LOG_DIR" -name '*.log' -type f -mtime +3 -delete 2>/dev/null

if [ $DRY -eq 1 ]; then
  [ -n "$BEFORE" ] && echo "待更新（dry-run）：$(echo "$BEFORE" | tr '\n' ' ')"
  exit 0
fi

OUT=""
if [ $RC -ne 0 ]; then
  OUT="⚠️ 每日自动更新有失败（rc=$RC）：$(grep -iE 'error|failed|fatal|TIMEOUT' "$LOG" | tail -3 | tr '\n' ' ')"
fi

if [ -n "$BEFORE" ] && [ "$BEFORE" != "$AFTER" ]; then
  UPGRADED=$(printf '%s\n' "$BEFORE" | grep -vxF "$AFTER" | tr '\n' ' ')
  OUT="$OUT
✅ Homebrew：$UPGRADED"
fi

if grep -q "^SKIP-busy:" "$LOG" 2>/dev/null; then
  BUSYLIST=$(grep "^SKIP-busy:" "$LOG" | sed 's/^SKIP-busy://' | sed 's/（.*//' | tr -d '\n')
  OUT="$OUT
⏭ 运行中、本次跳过：${BUSYLIST# }（其余包照常更新）"
fi
if [ -n "$NPM_AFTER" ] && [ "$NPM_BEFORE" != "$NPM_AFTER" ]; then
  CHANGED=$(printf '%s\n' "$NPM_AFTER" | grep -vxF "$NPM_BEFORE" | grep -E '──' | tr -d '├└─ ' | tr '\n' ' ')
  OUT="$OUT
✅ npm 全局包：$CHANGED"
fi

if [ -n "$OUT" ]; then
  echo "${OUT#?}"
  echo "日志：$LOG"
fi
# 没有升级、没有报错 → 完全静默，cron 不打扰