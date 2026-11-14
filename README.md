# mac-auto-update

macOS 上的**自动更新小工具**：每天定时升级 Homebrew 的 CLI 工具，顺带更新 Claude Code 和 Codex，带日志和滚动清理。

只做这一件事——把命令行工具保持最新。**不碰图形应用、不碰网络工具、不碰 Hermes 本体。**

## 它管什么

- `brew update && brew upgrade --formula`：136 个 CLI 工具（ffmpeg、yt-dlp、node、postgres 等）
- `brew cleanup -s`：清下载缓存（这台机器磁盘小，能腾几个 G）
- `/opt/homebrew/bin/npm update -g`：全局 npm 包（claude-code、codex、happy-coder、corepack…），15 分钟超时。**必须用 `/opt/homebrew/bin/npm`**，PATH 里别的 npm 会把包装错 prefix

## 它不管什么（故意的）

| 对象 | 原因 |
|---|---|
| **Chrome / 飞书 Lark / Telegram** | Homebrew 把它们标成 `auto_updates`，它们自己更新，brew 接管会双重更新 |
| **Clash Party 等网络工具** | 网络关键路径，更新出问题会断网，改手动 |
| **Hermes Agent** | git 安装，用自己的 `hermes update` |
| **npm 全局包** | 已恢复正规通道：`brew install node` 后用 `/opt/homebrew/bin/npm update -g` 统一更新 |
| **大体积 GUI**（IntelliJ、VideoFusion…） | 动辄 3–4G，升级要退出应用，按需手动 |

## 日志

- 位置：`~/Library/Logs/brew-autoupdate/`（macOS 用户级日志目录，Console.app 能直接打开）
- 每次运行一个文件，**保留 3 天**，自动删除更早的
- 记录 `brew update` / 升级了哪些包 / 失败时的 error 行

> 为什么不用 `/var/log`：那是系统级目录，需要 root；用户级定时任务的标准位置就是 `~/Library/Logs`。

## 装法

### 方式 A：Hermes cron（本机在用）

```bash
# ~/.hermes/scripts/brew-autoupdate.sh 里放一个转发的启动器
exec /bin/bash /path/to/mac-auto-update/bin/brew-autoupdate.sh "$@"
```

然后每天 3:30 跑一次。stdout 只在「有升级」或「有失败」时输出 → 没动静就不打扰。

### 方式 B：launchd

```xml
<key>StartCalendarInterval</key>
<dict><key>Weekday</key><integer>0</integer><key>Hour</key><integer>3</integer><key>Minute</key><integer>30</integer></dict>
```

```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.mint.brew-autoupdate.plist
```

## 升级正在运行的程序会怎样

- **CLI 工具**：文件被替换，正在跑的进程继续用内存里的旧版，不崩；重启后生效
- **codex / claude 正在跑时**：脚本会 **跳过 npm 那次更新**（`pgrep` 检测进程），等下次没在跑时再更——npm 自己不会跳过，硬更可能让运行中的会话版本混用
- **brew services（postgres / redis）**：`brew upgrade` 只换文件，**不会重启服务**；要 `brew services restart` 才用新版
- **GUI 应用**：brew 不检测是否在运行，也不跳过——所以本工具**只升 formula，不升 cask**

## 手动试跑

```bash
bin/brew-autoupdate.sh            # 真升级
bin/brew-autoupdate.sh --dry-run  # 只看有哪些待更新
```

## License

MIT