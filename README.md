# mac-auto-update

每天自动更新这台 Mac 的工具链，并在凌晨重启后台服务让新版本生效。带日志、3 天滚动、只在有事时通知。

## 两个任务

| 脚本 | 时间 | 做什么 |
|---|---|---|
| `bin/brew-autoupdate.sh` | 每天 03:30 | Homebrew CLI、npm 全局包、pip、指定 GUI 应用 |
| `bin/restart-services.sh` | 每天 05:00 | 重启当前在跑的 brew services（postgres / redis…） |

分成两步的原因：`brew upgrade` 只替换文件、**不会重启服务**，所以服务需要在没人用的时候单独重启（凌晨 5 点）。

## 更新范围

| 类别 | 具体 | 策略 |
|---|---|---|
| Homebrew formula | 所有 CLI 工具 | 全升 |
| npm 全局包 | claude-code、codex、happy-coder… 以及 **npm 自身** | 全升；**正在运行的那个单独跳过**；corepack 不升（跟 brew 的 node 走） |
| pip | 全局 Python 包 | **只升同一大版本**（补丁/次版本）；跨大版本只报告 |
| GUI cask | 脚本顶部白名单 | 见下 |
| brew services | postgres、redis… | 每天 05:00 重启（不会顺手启动没在跑的服务） |

> npm 自身也在升级范围内：只有 registry 上真有新版才升（否则 `update -g npm` 每次都会把 npm 重装一遍）。npm 12 起默认禁止拉远程包，脚本按主版本自动补 `--allow-remote=all`；`brew upgrade node` 会把 npm 换回 node 自带版本，第二天凌晨脚本再把它升回最新。脚本内部 PATH 前置了 `/opt/homebrew/bin`，避免用到 nvm 里更旧的 node。

## GUI 白名单

脚本顶部三组配置，改这三行就能加应用：

```bash
# 可杀可升：运行中也一样，先杀掉再升级
CASKS_KILLABLE="openscreen|Openscreen baidunetdisk|BaiduNetdisk_mac ..."

# 在跑就跳过：有状态、可能在执行长任务
CASKS_SKIP_IF_RUNNING="wechat|WeChat deepseek-harness|DeepSeek Harness"

# 升完重新打开
REOPEN="QQ"
```

三条原则：

1. **有状态 / 可能正在跑任务的应用，在跑就绝不更新**（微信、DeepSeek Harness）——中途替换文件会让正在进行的会话版本混用
2. **可随时关闭的应用，杀掉再升，不重开**（会议、网盘、剪辑、IDE）
3. **网络工具永不动**（Clash / 代理 / VPN）——升坏了整机断网

## 为什么 pip 只升同大版本

`pip list --outdated` 里经常出现 `anthropic 0.97 → 2.8`、`openai 2.15 → 3.51` 这种跨大版本跳级。这些包 API 会变，盲升会把现有脚本跑挂。所以脚本只升主版本号不变的，跨版本的列出来等人工确认：

```bash
bin/pip_safe_update.py --dry-run
```

## 日志

- `~/Library/Logs/brew-autoupdate/`：每次运行一个文件，**保留 3 天**
- `~/Library/Logs/mac-auto-update/`：服务重启日志，同样 3 天
- 升级失败先看里面的 `error|failed|fatal|TIMEOUT` 行

> 不用 `/var/log`：那是系统级目录、需要 root；用户级定时任务的标准位置就是 `~/Library/Logs`（Console.app 能直接打开）。

## 安装

### Hermes cron（本机在用）

`~/.hermes/scripts/` 里各放一个转发的启动器：

```bash
#!/bin/sh
exec /bin/bash /path/to/mac-auto-update/bin/brew-autoupdate.sh "$@"
```

然后 `30 3 * * *` 和 `0 5 * * *` 各建一个 `no_agent` 任务。stdout 只在「有升级」或「有失败」时输出 → 没动静就不打扰。

### launchd

```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/<job>.plist
```

> 在 Hermes gateway 里 `launchctl bootstrap` 会被安全策略拒绝（防网关重启循环），要在独立终端里执行。

## 升级正在运行的程序会怎样

- **CLI 工具**：文件被替换，运行中的进程继续用内存里的旧版，不崩；重启后生效
- **npm / pip 包**：同上；但**正在跑的那个包**会被脚本单独跳过，避免运行中版本混用
- **brew services**：升级不重启服务，由 05:00 的任务负责重启
- **GUI 应用**：brew 不检测是否在运行、也不跳过——所以必须在白名单里显式处理

## 手动试跑

```bash
bin/brew-autoupdate.sh --dry-run   # 只看有哪些待更新
bin/brew-autoupdate.sh             # 真升级
bin/restart-services.sh            # 立即重启服务
bin/pip_safe_update.py --dry-run   # pip 分类报告
```

## License

MIT