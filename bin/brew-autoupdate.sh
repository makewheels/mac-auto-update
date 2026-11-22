#!/bin/bash
# 每天自动更新这台 Mac 的工具链：
#   1) Homebrew CLI 工具（brew upgrade --formula）+ 清缓存
#   2) npm 全局包（claude-code / codex / happy-coder… 以及 npm 自身），运行中的单独跳过
#      corepack 不升（跟 brew 的 node 走）；npm 12+ 需 --allow-remote=all 才能拉自己的包
#   3) pip 包（只升同大版本；跨大版本只报告，等人工确认）
#   4) GUI 应用（白名单，升级前先退出；微信 / DeepSeek Harness 在跑就跳过）
#
# 绝不自动更新：Clash Party（网络命脉）、Hermes 本体
# 日志：~/Library/Logs/brew-autoupdate/  保留 3 天
# 输出：只有「有升级」或「有失败」时才打印（Hermes cron 用它决定是否通知）
# 用法：brew-autoupdate.sh [--dry-run]

LOG_DIR="$HOME/Library/Logs/brew-autoupdate"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/$(date +%Y%m%d-%H%M).log"
BREW=/opt/homebrew/bin/brew
NPM=/opt/homebrew/bin/npm
PY=/usr/bin/python3
GLOBAL_PY=/usr/local/bin/python3
DIR="$(cd "$(dirname "$0")" && pwd)"
BOUNDED="$DIR/run_bounded.py"

# 固定用 brew 的 node/node-gyp：用户 shell 里 nvm 的 node 可能更旧（npm 12 不认 node <24.15）
export PATH="/opt/homebrew/bin:$PATH"

# GUI 策略：cask|App 名
# 可杀可升（运行中也一样，升级前先杀掉）
CASKS_KILLABLE="openscreen|Openscreen baidunetdisk|BaiduNetdisk_mac tencent-meeting|TencentMeeting videofusion|VideoFusion-macOS intellij-idea|IntelliJ IDEA adrive|aDrive qq|QQ"
# 在跑就跳过（有状态 / 可能在跑长任务）
CASKS_SKIP_IF_RUNNING="wechat|WeChat deepseek-harness|DeepSeek Harness"
# 升完重新打开
REOPEN="QQ"

DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

BEFORE=$("$BREW" outdated --formula 2>/dev/null)
NPM_BEFORE=$("$NPM" ls -g --depth=0 2>/dev/null)

{
  echo "=== start $(date '+%F %T')"
  echo "--- brew update"
  "$BREW" update
  echo "--- outdated before:"
  "$BREW" outdated --formula

  if [ $DRY -eq 1 ]; then
    echo "--- dry-run：不执行升级"
    "$GLOBAL_PY" "$DIR/pip_safe_update.py" --dry-run
  else
    echo "--- brew upgrade --formula"
    "$BREW" upgrade --formula
    echo "--- brew cleanup -s"
    "$BREW" cleanup -s

    echo "--- npm update -g（含 npm 自身，逐包排除正在运行的 codex/claude）"
    PKGS=$("$NPM" ls -g --depth=0 --json 2>/dev/null | "$PY" -c 'import json,sys;d=json.load(sys.stdin);print(" ".join(sorted(d.get("dependencies",{}))))')
    BUSY=""
    # corepack 归 brew 的 node 管，不由 npm 自更新
    PKGS=$(echo "$PKGS" | sed 's|npm||; s|corepack||')
    # npm 12 起远程 tarball 默认禁止，自更新要显式放行；旧版 npm 不认这个参数
    ALLOW_REMOTE=""
    NPM_MAJOR=$("$NPM" -v 2>/dev/null | cut -d. -f1)
    if [ "${NPM_MAJOR:-0}" -ge 12 ] 2>/dev/null; then
      ALLOW_REMOTE="--allow-remote=all"
    fi
    # npm 自身真有新版才升（否则 update -g npm 每次都会把 npm 重装一遍）
    NPM_LATEST=$("$NPM" view npm version 2>/dev/null)
    if [ -n "$NPM_LATEST" ] && [ "$NPM_LATEST" != "$("$NPM" -v 2>/dev/null)" ]; then
      echo "npm 自身 $("$NPM" -v) -> $NPM_LATEST，一并升级"
      PKGS="$PKGS npm"
    fi
    if pgrep -f "/opt/homebrew/lib/node_modules/@openai/codex/bin" >/dev/null 2>&1; then
      PKGS=$(echo "$PKGS" | sed 's|@openai/codex||'); BUSY="$BUSY codex"
    fi
    if pgrep -f "/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/bin" >/dev/null 2>&1; then
      PKGS=$(echo "$PKGS" | sed 's|@anthropic-ai/claude-code||'); BUSY="$BUSY claude"
    fi
    [ -n "$BUSY" ] && echo "SKIP-busy:$BUSY （运行中，本次不动它，其余照常）"
    if [ -n "$(echo "$PKGS" | tr -d ' ')" ]; then
      "$PY" "$BOUNDED" "$NPM" update -g $ALLOW_REMOTE $PKGS
      echo "npm rc=$?"
    else
      echo "SKIP-none: 没有可更新的包"
    fi

    echo "--- pip 安全更新（只升同大版本）"
    PIP_OUT=$("$PY" "$BOUNDED" "$GLOBAL_PY" "$DIR/pip_safe_update.py")
    echo "$PIP_OUT"
    PIP_SUMMARY=$(echo "$PIP_OUT" | grep -E "^⚠️" | head -3)  # 只在失败时提示；升级明细只进日志

    echo "--- GUI 应用（白名单）"
    CASK_DONE=""
    for entry in $CASKS_KILLABLE; do
      c=${entry%%|*}; app=${entry##*|}
      "$BREW" outdated --cask --quiet 2>/dev/null | grep -qx "$c" || continue
      if pgrep -f "/Applications/$app.app/Contents/MacOS/" >/dev/null 2>&1; then
        echo "cask: $c 在运行，先退出"
        pkill -f "/Applications/$app.app/Contents/MacOS/" 2>/dev/null
        sleep 3
      fi
      "$PY" "$BOUNDED" "$BREW" upgrade --cask --greedy "$c"
      echo "cask $c rc=$?"
      CASK_DONE="$CASK_DONE $c"
      if echo " $REOPEN " | grep -q " $app "; then
        open -a "/Applications/$app.app" 2>/dev/null && echo "reopen $app"
      fi
    done
    for entry in $CASKS_SKIP_IF_RUNNING; do
      c=${entry%%|*}; app=${entry##*|}
      "$BREW" outdated --cask --quiet 2>/dev/null | grep -qx "$c" || continue
      if pgrep -f "/Applications/$app.app/Contents/MacOS/" >/dev/null 2>&1; then
        echo "SKIP-cask:$c （$app 正在运行）"
      else
        "$PY" "$BOUNDED" "$BREW" upgrade --cask --greedy "$c"
        echo "cask $c rc=$?"
        CASK_DONE="$CASK_DONE $c"
      fi
    done
  fi

  echo "--- outdated after:"
  "$BREW" outdated --formula
  echo "=== done $(date '+%F %T')"
} >>"$LOG" 2>&1
RC=$?

AFTER=$("$BREW" outdated --formula 2>/dev/null)
NPM_AFTER=$("$NPM" ls -g --depth=0 2>/dev/null)

# 只保留最近 3 天
find "$LOG_DIR" -name '*.log' -type f -mtime +3 -delete 2>/dev/null

if [ $DRY -eq 1 ]; then
  [ -n "$BEFORE" ] && echo "待更新（dry-run）：$(echo "$BEFORE" | tr '\n' ' ')"
  exit 0
fi

OUT=""
ERRS=$(grep -iE "^Error:|^fatal:|TIMEOUT|Download failed" "$LOG" 2>/dev/null | tail -3 | tr '\n' ' ')
if [ $RC -ne 0 ] || [ -n "$ERRS" ]; then
  OUT="⚠️ 自动更新有失败：${ERRS:-rc=$RC}"
fi

if [ -n "$PIP_SUMMARY" ]; then
  OUT="$OUT
$PIP_SUMMARY"
fi

FAILED_CASKS=$(grep -E "^cask .* rc=[1-9]" "$LOG" 2>/dev/null | sed -E 's/^cask ([^ ]+) rc=.*/\1/' | tr '\n' ' ')
if [ -n "$FAILED_CASKS" ]; then
  OUT="$OUT
⚠️ GUI 升级失败：$FAILED_CASKS"
fi

if [ -n "$OUT" ]; then
  echo "${OUT#?}"
  echo "日志：$LOG"
fi
# 成功（有升级也算成功）时完全静默，只有失败才推送