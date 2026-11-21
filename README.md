# carplay-by-n1

把 **CarPlay 投到车机浏览器**的开源方案 [DashPlay](https://github.com/yizhixiaoheigou/DashPlay)，在**斐讯 N1**（Amlogic S905D）上跑起来的适配层。

官方 DashPlay 的 OpenWrt 插件是 `apk` 包，只支持 **OpenWrt 25.12**。而绝大多数 N1 刷的是 opkg 体系的 Lean LEDE 固件，插件装不上。本项目把插件的安装规则**手工还原成一套可复现的脚本**，并在真机上验证过完整链路。

> 适合人群：手上有一台吃灰的 N1、车机带浏览器、想让 iPhone 的 CarPlay 显示在车机大屏上的人。

## 它解决什么问题

| 问题 | 官方现状 | 本项目 |
|---|---|---|
| N1 固件是 opkg（Lean LEDE R23.6.x），插件是 apk | 装不上 | 按 Makefile 排除规则手工解包部署 |
| 固件里 Python 是 3.11 | 程序用了 3.12 才允许的 f-string 语法，`py_compile` 直接失败 | 两处语法补丁 |
| 固件 OpenSSL 是 1.1.1 | `pkcs12 -iter` 不被识别，keystore 生成失败，服务起不来 | 一处命令补丁 |
| OpenWrt 源里没有 Java | JRE 无包可装 | 拉 Temurin 21 musl 版放 `/usr/lib/dashplay-jre` |
| OpenWrt 源里没有 `libstdcpp` | JRE 缺 `libstdc++.so.6` | 从 Alpine 取同版本 so |
| `iphone-usb-bridge.py` 写死玩客云的 usb-role 路径 | N1 上是 `d0078080.usb-role-switch`，有线桥起不来 | 改成自动扫描 |

## 实测环境

| 项 | 值 |
|---|---|
| 盒子 | 斐讯 N1 / Amlogic S905D / AArch64 / 内存 1.9 GB |
| 固件 | Lean LEDE R23.6.6，内核 `6.1.33-flippy-84+`，opkg 体系 |
| 根分区 | `/dev/mmcblk2p2`，960 MB，btrfs + zstd（装完还能剩 400 MB 左右） |
| 网络 | 旁路由模式，`eth0` 挂在主路由 LAN，盒子地址 `192.168.1.2` |
| 车机 | 特斯拉 Model Y（车机自带浏览器） |
| 手机 | iPhone，有线连接（Lightning / USB-C 均可） |
| DashPlay | `v2026.11.13` |

## 快速开始

把整个仓库拷到 N1 上（`install.sh` 依赖同级的 `patches/` 目录，别只下单个脚本）：

```sh
# 在 N1 上，root 身份
cd /tmp
curl -fL -o cbn.tar.gz https://gh-proxy.com/https://github.com/jianqiang1235/carplay-by-n1/archive/refs/heads/main.tar.gz
tar -xzf cbn.tar.gz && cd carplay-by-n1-main
```

然后分阶段执行（每步都能单独重跑，幂等）：

```sh
sh install.sh deps     # 装 python3、拿 bundle、解包到 /opt/dashplay、打四条补丁
sh install.sh jre      # 装 JRE 21 (musl) + libstdc++
sh install.sh identity # 检查认证文件（需你自备，见下）
sh install.sh service  # 装 procd 启动脚本、写 uci、开机自启、启动
sh install.sh check    # 自检
```

`sh install.sh all` 可以一次跑完；认证文件缺失时它会停下来把自取步骤打印出来。

### 认证文件必须自备

CarPlay 需要一份 MFi 认证身份（`identity.pk8` + `certificate.p7b`）。**本项目不分发这个文件**，原因见下面的免责声明。

自取方式：下载 DiPlay 的 APK（`v0.2.22`，SHA256 `7d04db263834f22010a86847766928113d3503a273e4d2d3440d21552e173139`），从里面取出 `assets/offline-mfi/` 两个文件，放到：

```
/opt/dashplay/identity/offline-mfi/identity.pk8      (0600)
/opt/dashplay/identity/offline-mfi/certificate.p7b   (0600)
```

放好后可以自检公私钥是否配对：

```sh
openssl pkcs8 -inform DER -in identity.pk8 -nocrypt -out /tmp/k.pem
openssl pkey -in /tmp/k.pem -pubout -outform DER | openssl sha256
openssl pkcs7 -inform DER -in certificate.p7b -print_certs -out /tmp/c.pem
openssl x509 -in /tmp/c.pem -pubkey -noout | openssl pkey -pubin -outform DER | openssl sha256
# 两个值相同 → IDENTITY_MATCH
```

## 怎么用（有线方案，推荐）

1. iPhone 数据线插 N1 的 USB 口，手机点「信任」
2. 车机连 N1 的热点 `Phicomm_n1`（密码 `password`），浏览器打开 `https://192.168.1.2:18443/`
3. 自签证书警告点「继续」

数据线只负责把 CarPlay 数据送进盒子，**画面靠网页显示**，所以车机仍需和盒子在同一网段。

判断链路是否真的通了，别看页面文字，看这个：

```sh
netstat -tnp | grep :7000
# 有一条 ESTABLISHED（对端是 fe80::…）→ iPhone 已经在推流了
```

## 无线 CarPlay：实测能通，但链路不成立

这部分**没有跑通**，但排查过程有价值，省得别人再踩：

- 内置 BCM43455 的 dtb 节点其实是齐的（`brcm,bcm43438-bt` + 复位 GPIO + wifi32k 时钟 + 2 M 波特率，挂 `serial@84c0`），
  只是 `hci_uart` 模块从没被加载。`modprobe hci_uart` 后 hci0 正常起来（`BCM4345C0 Ampak 0073`），Bluetooth LE advertising 也支持。
- 卡住的是网络侧：热点只有 5 GHz（降到 2.4 GHz 时 hostapd 在 `nl80211` 阶段就 `Unable to setup interface`），
  且 N1 是旁路由不发 DHCP，车机拿不到地址就打不开页面。
- 另外有线占用时无线会被主动暂停（页面提示「拔掉数据线再来」）。

想自己继续折腾的话，看 [docs/WIRELESS.md](docs/WIRELESS.md)，里面有完整步骤和已排除的可能。

## 四条补丁

全部在 `patches/apply_patches.py`，幂等，跑第二遍不会重复改：

| 文件 | 原 | 改 |
|---|---|---|
| `settings_page.py` | `{'scope': scope}` | `{"scope": scope}`（f-string 内同引号嵌套，3.12 才允许） |
| `setup_wizard.py` | `", ".join(` | `', '.join(`（同上） |
| `boxnet.py` | `"-iter", "1",` 这一行 | 删掉（OpenSSL 1.1.1 不认 `-iter`，且与 `-nomaciter` 互斥） |
| `iphone-usb-bridge.py` | 写死 `c9040000.usb-role-switch` | 扫描 `/sys/class/usb_role/*/role` |

## 目录

```
├── install.sh               # 分阶段安装脚本（deps / jre / identity / service / all）
├── uninstall.sh             # 卸载
├── CHANGELOG.md             # 版本内容与提交历史说明
├── patches/apply_patches.py # 四条补丁
├── files/dashplay.init      # procd 启动脚本
├── files/dashplay.uci       # uci 默认配置
└── docs/
    ├── DEPENDENCIES.md      # 依赖来源与校验值
    ├── WIRED.md             # 有线方案细节
    ├── WIRELESS.md          # 无线尝试记录（未成功）
    ├── TROUBLESHOOT.md      # 排错表
    └── PUBLISH.md           # 本仓库的发布/上传方法
```

## 注意事项

- **别点设置页的「检查更新 / 安装其他版本」**。在线升级会整体替换 `/opt/dashplay`，四条补丁一起丢，服务直接起不来。
  本项目已把 `update_check` 设为 `0`，但别手动去点。
- **sysupgrade 保配置升级会丢 `/opt/dashplay` 和 JRE**，升级后重跑 `install.sh`。
- 旁路由模式下**不要**在盒子上开 DHCP（`dhcp.lan.ignore` 保持 `1`），否则会和主路由抢答。
  热点 `wlan0` 桥在 `br-lan` 里，车机的地址由主路由分配，这条路是通的。
- 在线播放吃 CPU，N1 是 4 核 A53，30 fps + HEVC 时 `java` 会占 60%~80%，属正常。

## 免责声明

本仓库只包含**安装适配脚本和文档**，不含 DashPlay 本体、不含 MFi 认证身份，也不含任何 Apple 私有密钥。

- DashPlay 的版权归其作者，请遵守上游许可证。
- 认证文件取自第三方公开分享的实验身份，**仅限个人测试**。Apple 可随时吊销，届时 CarPlay 会握手失败。
  请勿用于商业产品，也不要外传你手里的那份。由此产生的任何后果由使用者自行承担。
- 车机端观看行车的画面功能，请在**停车状态**调试；行车中操作车机违反交通法规，也可能违反车厂的使用条款。

## 致谢

- [yizhixiaoheigou/DashPlay](https://github.com/yizhixiaoheigou/DashPlay)：协议实现与安装说明
- DiPlay：认证文件的公开来源
- Temurin / Alpine：musl 环境的 JRE 与 libstdc++
