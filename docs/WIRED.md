# 有线方案（推荐，已实测出画）

## 链路

```
iPhone ──USB 数据线──> N1（iphone-usb-bridge.py 走 usbmuxd 协议）
                         │
                         └── PlayPort（7000）──> run-receiver / JVM 解码
                                                   │
车机浏览器 <──Wi-Fi────────────────────────────────┘  转成 H.264/HEVC 推给网页
             https://192.168.1.2:18443/
```

两个容易误解的点：

1. **数据线不负责画面**。线只把 CarPlay 数据送进盒子，画面是网页播放的流。所以车机必须能访问盒子。
2. **iPhone 不需要连盒子的 Wi-Fi**。有线模式下它走 USB。

## 操作步骤

1. iPhone 插 N1 的 USB 口，手机上点「信任」
2. 车机连 `Phicomm_n1`（WPA2 / `password`），确认拿到 `192.168.1.x`
3. 车机浏览器打开 `https://192.168.1.2:18443/`，自签证书警告点继续

## 怎么确认真的通了

页面上的"有线 CarPlay 正在使用"可能是**上一次插线的状态残留**，拔线后不会立刻刷新。以实际连接为准：

```sh
# 1) USB 上认到 iPhone
for d in /sys/bus/usb/devices/*; do [ -f "$d/idVendor" ] && echo "$(basename $d) $(cat $d/idVendor):$(cat $d/idProduct)"; done
# 期望：1-2 05ac:12a8（05ac = Apple，12a8 = iPhone）

# 2) 桥接进程在跑
ps | grep iphone-usb-bridge | grep -v grep

# 3) 最关键：7000 端口有 ESTABLISHED
netstat -tnp | grep :7000
# 期望类似：tcp 0 0 fe80::2:7000 fe80::18:8dad:9139:515f:58138 ESTABLISHED 7900/java
```

第 3 条才是"iPhone 已经在推流"的硬证据。只有 USB 枚举、没有 ESTABLISHED，说明握手没走完，
通常是认证文件不对或 iPhone 没点信任。

## 已验证的参数

| 项 | 值 |
|---|---|
| 画面尺寸 | 1312 × 1204，30 fps，HEVC |
| 端口 | PlayPort 7000、网页 18443、设置页 18080 |
| 车机端协议 | HTTPS，自签证书（或配好 DDNS 后换正式证书） |
| CPU | 4 核 A53，出画时 `java` 约 60%~80% |

## 旁路由环境下地址是怎么来的

N1 是旁路由：`eth0` 挂在主路由 `192.168.1.1` 的 LAN 上，`dhcp.lan.ignore='1'`，**盒子自己不发 DHCP**。

热点 `wlan0` 桥在 `br-lan` 里，所以车机连上热点后：

```
车机 DHCP 请求 → wlan0 → br-lan → eth0 → 主路由 192.168.1.1 → 分配 192.168.1.x
```

拿到地址后就能直连 `192.168.1.2`。

> 踩过的坑：一开始以为盒子要给车机发地址，在 `br-lan` 上开了 DHCP（池 250–254 + `force 1`），
> 结果 `log-dhcp` 显示盒子**一条请求都没收到**——主路由抢先应答了。实测车机拿到的是主路由给的
> `192.168.1.167`，访问盒子完全正常。已回滚，保持旁路由原状。

## 关于"域名访问"

`uci dashplay.main.name` 默认 `dashplay.lan`，dnsmasq 会把该名字解析到盒子地址，
所以 `https://dashplay.lan:18443/` 也能用——但前提是车机能用盒子的 DNS。
车机的 DNS 通常来自主路由，所以这条在旁路由环境下不一定成立，直接用 IP 更稳。
