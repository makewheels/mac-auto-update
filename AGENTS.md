# AGENTS.md · 项目意图

## 为什么有这个东西

这台 Mac 装的东西分三类，更新方式各不相同：

1. **Homebrew CLI**（136 个）——该自动更，但从来没人更，越积越旧
2. **自带更新器的 GUI**（Chrome、飞书、Telegram）——自己会更新，不用管
3. **手动装的大件**（IntelliJ、VideoFusion、百度网盘）——动辄几 G，升级要退出应用

这个项目只解决第 1 类，用最小的代码：一个 bash 脚本 + 一个定时任务。

## 硬约束（改代码前先看）

- **只升 formula，绝不升 cask**：GUI 升级时 brew 不会退出应用，容易把正在用的应用搞坏
- **不碰 Clash / 任何网络配置**：更新断网工具的代价是整台机器失联
- **不碰 Hermes**：它有自己的 `hermes update`，且 gateway 在跑
- **日志写 `~/Library/Logs/brew-autoupdate/`，保留 3 天**：磁盘只有 ~18G，日志无限增长不行
- **stdout 只在有升级或失败时输出**：定时任务「没动静」才是正常

## 目录

```
bin/brew-autoupdate.sh   # 唯一脚本
README.md                # 说明 + 装法
```

## 排查

升级失败先看 `~/Library/Logs/brew-autoupdate/<时间>.log` 里的 `error|failed|fatal` 行；网络抖动（TLS EOF）很常见，重跑即可。