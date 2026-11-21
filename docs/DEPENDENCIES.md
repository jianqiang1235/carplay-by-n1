# 依赖清单与校验值

所有下载项都能在 N1 上直接 `curl` 拿到；GitHub 直连慢或不通时，装脚本会自动改走 `https://gh-proxy.com/` 前缀。

| 用途 | 文件 | 大小 | SHA256 |
|---|---|---|---|
| DashPlay 程序 | `dashplay-bundle-2026.11.13.tar` | 29,097,472 | `b5661d53cc4c3743878c91db2b04bf5c64f65a6b93e068dded1334e178b2898d` |
| JRE | `OpenJDK21U-jre_aarch64_alpine-linux_hotspot_21.0.9_10.tar.gz` | 51,095,612 | `7f8c230ba505b418e4288e2b34758a6e4da32470944740e5ba0cfaae02271c22` |
| libstdc++ | `libstdc++-13.2.1_git20240309-r1.apk` | 885,578 | 未固定（Alpine v3.20 main/aarch64，随源小版本变动） |
| MFi 认证 | `identity.pk8` + `certificate.p7b` | 67 + 607 | **不提供**，需自备 |

## 下载地址

```
https://github.com/yizhixiaoheigou/DashPlay/releases/download/v2026.11.13/dashplay-bundle-2026.11.13.tar
https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.9%2B10/OpenJDK21U-jre_aarch64_alpine-linux_hotspot_21.0.9_10.tar.gz
https://dl-cdn.alpinelinux.org/alpine/v3.20/main/aarch64/libstdc++-13.2.1_git20240309-r1.apk
```

## 为什么要这么选

### JRE 选 Alpine 版而不是 glibc 版

OpenWrt 是 musl 环境。Adoptium 默认的 `linux` 版是 glibc 链接，跑不起来。必须用 `alpine-linux` 那份。
解压后放 `/usr/lib/dashplay-jre`，启动脚本用绝对路径调用，不需要 `java` 在 PATH 里。

### libstdc++ 必须单独找

JRE 依赖 `libstdc++.so.6`，而 Lean LEDE 的 opkg 源里**根本没有** `libstdcpp` 这个包
（`opkg list` 全量 9146 个包里搜不到）。Alpine 跟 OpenWrt 同属 musl，直接从 Alpine 取同版本 GCC 编出来的 so，
放 `/usr/lib/` 再建一个 `libstdc++.so.6` 软链即可。

### python3 用 opkg 的就够

Lean LEDE 的 `python3` 是 3.11.7，自带 `asyncio` / `ctypes` / `ssl`，DashPlay 需要的模块都全。
但**程序是按 3.12 写的**，所以要打语法补丁（见 README）。

## 磁盘占用

根分区 960 MB（btrfs + zstd），装完实测：

```
/dev/mmcblk2p2   960M   453M   411M   52%  /
```

JRE 解压后 `du` 显示 155 MB，但 btrfs 压缩后 `df` 只涨了几十兆。仍然建议留 300 MB 以上余量，
JVM 运行时要在 `/opt/dashplay/state/receiver` 下写 class 共享归档（`.jsa`）。
