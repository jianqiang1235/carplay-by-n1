# 无线 CarPlay 尝试记录（未成功，留档给后来人）

结论先行：**蓝牙是通的，链路是不成立的**。想继续折腾的人可以从这里接手，能省掉一半排查。

## 已确认可行的一半

| 项 | 结果 |
|---|---|
| 硬件 | BCM43455（`BCM4345C0 Ampak 0073`），UART 挂在 `serial@84c0`（即 uart_A / ttyAML6） |
| 设备树 | 已写好了 `bluetooth` 子节点：`brcm,bcm43438-bt`、`shutdown-gpios=<0x16 0x60 0x00>`、`max-speed=2000000`、`clocks=<wifi32k>`，`status=okay`，带 `uart-has-rtscts` |
| 缺的东西 | 只是 `hci_uart` 模块没加载，内核从没去认领那路 UART —— **不需要改 dtb** |
| 加载后 | `modprobe hci_uart` → 日志 `hci_uart_bcm serial0-0`，自动读 `/lib/firmware/brcm/BCM4345C0.hcd`，出 `hci0` |
| 适配器能力 | `UP RUNNING`，支持 `le advertising`、`ssp br/edr`（无线 CarPlay 需要 LE advertising） |
| BlueZ | `opkg install bluez-daemon bluez-libs bluez-utils bluez-utils-extra dbus` 可用；官方 `/etc/init.d/bluetoothd`（START=62，注释写明在 dbus 之后） |
| DashPlay | 见到 hci0 后日志出 `bluetooth powered`，`config.json` 变 `"wireless": true`，适配器被改名为 `DashPlay` |

## 卡住的地方

### 1. 热点只有 5 GHz

```
iw dev wlan0 info   → ssid Phicomm_n1, type AP, channel 36 (5180 MHz), width: 80 MHz
```

想把热点降到 2.4 GHz（信道 6 / HT20）让兼容性更好的车机也能搜到，但 hostapd 起不来：

```
hostapd: wlan0: Unable to setup interface
netifd: radio0: Command failed: ubus call hostapd config_add {...} (Invalid argument)
netifd: radio0: Device setup failed: HOSTAPD_START_FAILED
```

而射频本身是支持的，矛盾就在这里：

```
iw phy phy0 info → Band 1: ... Band 2: ...
valid interface combinations: * #{ managed } <= 1, #{ AP } <= 1, ... total <= 4
iw reg get → country US: (2400 - 2472 @ 40), (N/A, 30)
```

`iw phy` 声明有 Band 1（2.4 GHz）、也声明支持 AP，reg 也没禁 2400–2472，
但 `hw_mode=g` 的 hostapd 落到 `nl80211` 就被拒。怀疑和 brcmfmac 的 board/nvram 里 AP 频段配置有关，
没有继续深挖（要动固件里的 Wi-Fi 参数，风险高于收益）。

### 2. 热点拿不到地址

N1 是旁路由，`dhcp.lan.ignore='1'`，盒子不发 DHCP。5 GHz 热点能让 iPhone 关联上（`station dump` 有、
收发几个 MB），但 iOS 只拿到 IPv6 链路本地，没有 IPv4 → 打不开页面。

试过在 `br-lan` 上开 DHCP：

```sh
uci set dhcp.lan.ignore='0'
uci set dhcp.lan.start='235'; uci set dhcp.lan.limit='20'
uci set dhcp.lan.force='1'
uci set dhcp.lan.dhcp_option='3,192.168.1.1'
uci set dhcp.lan.dhcp_option='6,192.168.1.1'
uci commit dhcp && /etc/init.d/dnsmasq restart
```

开了 `log-dhcp` 之后发现盒子**一条 DHCPDISCOVER 都没收到**——主路由在同一网段先应答了。
也就是说热点侧要靠主路由分配，但在车里没有主路由，这条路就断了。
**这是无线方案真正的死点：盒子和车机凑在一起时，谁来发地址。**

### 3. 有线占用会暂停无线

拔着线时页面直接提示：

> 无线连接是暂停的，所以暂时不能添加手机……要添加新手机，拔掉数据线再来。

想加新手机必须先拔线，这也意味着"插线充电 + 无线 CarPlay"不能共存。

## 如果想继续

按这个顺序反做就能回到无线可用状态：

```sh
# 1) 恢复蓝牙模块加载
mv /root/bak-dashplay/60-bluetooth /etc/modules.d/60-bluetooth
modprobe hci_uart

# 2) 恢复 bluetoothctl（DashPlay 靠 which bluetoothctl 判断能不能走无线）
mv /usr/bin/bluetoothctl.off /usr/bin/bluetoothctl

# 3) 开 bluetoothd 自启
/etc/init.d/bluetoothd enable && /etc/init.d/bluetoothd start

# 4) 重启服务，config.json 会自动变回 wireless: true
/etc/init.d/dashplay restart
```

然后要解决的两件事：**给车机一个 IPv4**（要么热点侧能拿到主路由的租约，要么做一层独立的 NAT 网段
并给 `18443` 绑到该网段），以及**确认车机能搜到 5 GHz**。

如果车机只支持 2.4 GHz，那在这套固件上就没有解——除非换固件（DashPlay 官方对 N1 的做法是刷专用
Armbian 镜像走 U 盘，那条路不受 Lean LEDE 的 hostapd 限制）。
