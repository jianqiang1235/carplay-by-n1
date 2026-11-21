# CHANGELOG

## v0.1.0 — 2026-11-21

首个版本。基于真机（斐讯 N1 + Lean LEDE R23.6.6 + 特斯拉 Model Y）验证后的完整安装方案。

### 包含

| 内容 | 说明 |
|---|---|
| `install.sh` | 五阶段安装：deps / jre / identity / service / check / all，幂等可重跑 |
| `uninstall.sh` | 卸载，默认保留认证文件备份 |
| `patches/apply_patches.py` | 四条补丁，带 `--check` 只读模式，幂等 |
| `files/dashplay.init` | procd 启动脚本（来自上游插件，原样保留） |
| `files/dashplay.uci` | uci 默认配置，`update_check` 已设 0 |
| `docs/DEPENDENCIES.md` | 依赖来源与 SHA256 |
| `docs/WIRED.md` | 有线方案细节与验证方法 |
| `docs/WIRELESS.md` | 无线尝试记录（未成功） |
| `docs/TROUBLESHOOT.md` | 排错表 |
| `docs/PUBLISH.md` | 本仓库的发布/上传方法 |

### 适配的上游版本

- DashPlay `v2026.11.13`（`dashplay-bundle-2026.11.13.tar`，SHA256 `b5661d53…2898d`）
- JRE：Temurin `21.0.9+10`，`aarch64 alpine-linux`（musl）
- libstdc++：Alpine v3.20 / aarch64 / GCC 13.2

### 关注的四件事

1. 上游插件是 `apk`（apk-tools 3，ADBd + zstd），opkg 固件装不上 → 按 Makefile 排除规则手工部署
2. 固件 Python 是 3.11，程序用了 3.12 才允许的 f-string 内同引号嵌套 → 两处语法补丁
3. 固件 OpenSSL 是 1.1.1，不认 `pkcs12 -iter` → 删掉该参数
4. `iphone-usb-bridge.py` 写死玩客云 usb-role 路径 → 改为自动扫描

## 关于提交历史

本仓库只有**一条提交**（`init`），2026-11-21 建立。

最初的版本是通过 GitHub REST API 逐文件上传生成的，API 的 contents 接口每次只能提交一个文件，
所以当时产生了 16 条 `add 文件名` 之类的碎片提交。后来用 git 重写并强推覆盖，整理成现在的单条提交。

顺带记一个踩过的坑：Windows 上 `git add` 默认会把文本文件转成 CRLF，那样 `install.sh` 到 Linux 上执行会报
`$'\r': not found`。仓库已加 `.gitattributes` 锁定 `eol=lf`，并设 `core.autocrlf=false`。
如果你在 Windows 上继续维护，别动这两项。
