# 排错表

全部是实测踩过的，按"症状 → 原因 → 处理"排。

## 服务起不来

### 日志里 `Unrecognized flag iter`

```
pkcs12: Unrecognized flag iter
```

**原因**：OpenSSL 1.1.1 不认 `pkcs12 -iter`，而且它和 `-nomaciter` 本来就互斥。
**处理**：`boxnet.py` 里删掉 `"-iter", "1",` 那一行，然后重启。

### 日志里 `SyntaxError: f-string ... unmatched '{'`

**原因**：程序用了 Python 3.12 才允许的 f-string 内同引号嵌套，而固件里是 3.11。
**处理**：两处（`settings_page.py` 的 `{'scope': scope}`、`setup_wizard.py` 的 `", ".join(`），
`patches/apply_patches.py` 会一次搞定。

自查：

```sh
cd /opt/dashplay && python3 -m py_compile ./*.py
```

全部静默通过才算补全。有报错就先修再重启，不然服务会一直 crash 循环。

### `java: not found` 或 `libstdc++.so.6: cannot open shared object file`

**原因**：JRE 缺失，或者 JRE 找到了但缺 C++ 运行库。
**处理**：`sh install.sh jre`。校验：

```sh
/usr/lib/dashplay-jre/bin/java -version       # 应输出 openjdk 21.0.9
ls -l /usr/lib/libstdc++.so.6                  # 应指向 libstdc++.so.6.0.32
```

注意 OpenWrt 源里**没有** `libstdcpp` 包，别浪费时间 `opkg install libstdcpp`。

### 服务反复重启

```sh
logread | grep -i dashplay | tail -30
tail -40 /opt/dashplay/state/receiver/receiver.log
```

常见是认证文件缺失或公私钥不配对，见下一节。

## CarPlay 连不上

### 插了线，USB 认到了，但页面一直"未连接"

先看 7000 有没有连接：

```sh
netstat -tnp | grep :7000
```

- **没有 ESTABLISHED** → 握手没走完。检查认证文件，以及 iPhone 上有没有点「信任」
- **有 ESTABLISHED 但车机还是黑屏** → 问题在车机侧（地址不对或证书没点继续）

### `IDENTITY_MISMATCH`

私钥和证书不是一对。用这两条确认（注意两边都用 DER 算哈希，混用 PEM 会得到不同的值，很容易看错）：

```sh
openssl pkcs8 -inform DER -in identity.pk8 -nocrypt -out /tmp/k.pem
openssl pkey -in /tmp/k.pem -pubout -outform DER | openssl sha256

openssl pkcs7 -inform DER -in certificate.p7b -print_certs -out /tmp/c.pem
openssl x509 -in /tmp/c.pem -pubkey -noout | openssl pkey -pubin -outform DER | openssl sha256
```

两个 SHA256 相同才对。`certificate.p7b` 是 PKCS7 容器，直接 `openssl x509 -in certificate.p7b` 会读不出来，
必须先 `-print_certs` 转一道。

### 有线桥报 usb_role 相关错误

**原因**：`iphone-usb-bridge.py` 里写死了玩客云的 `c9040000.usb-role-switch`，N1 上是 `d0078080.usb-role-switch`。
**处理**：补丁改成扫描 `/sys/class/usb_role/*/role`。自查：

```sh
cat /sys/class/usb_role/*/role     # 期望 host
grep -n "_ROLES" /opt/dashplay/iphone-usb-bridge.py
```

## 车机打开页面失败

### 转圈 / 打不开

1. 车机到底有没有连上盒子热点

```sh
iw dev wlan0 station dump        # 有没有 Station
cat /proc/net/arp               # 车机拿到的 IPv4
```

2. 车机拿到的地址是不是 `192.168.1.x`

旁路由环境下地址由**主路由**分配。如果车机拿的是别的网段（比如主路由改过），就访问不到 `192.168.1.2`。

3. 证书警告没点「继续」

自签证书第一次一定拦一次，找不到"继续访问"的入口就会一直白屏。

### 页面打开但没画面

```sh
netstat -ltnp | grep -E ":18443|:7000"   # 两个都在监听？
```

`18443` 是 IPv6 双栈监听（`:::18443`），IPv4 也能连，不是问题。
`7000` 是 `::ffff:192.168.1.2:7000`，**只绑在盒子 LAN 地址**——所以车机必须在 `192.168.1.x` 网段，
跨网段访问不了。这条限制很重要，想改成独立网段要先解决它。

## 升级与维护

### 「检查更新」点了之后服务全挂

在线升级会整体替换 `/opt/dashplay`，四条补丁全丢。
**不要点**。真点了就重新跑 `sh install.sh deps`（bundle 会重新解包 + 打补丁），
`state` 目录（含配对与证书）不会被覆盖。

### sysupgrade 之后 DashPlay 没了

保配置升级会保留 `/etc/config`，但 `/opt/dashplay`、`/usr/lib/dashplay-jre`、`/usr/lib/libstdc++.so.6`
都在根分区里，可能丢。升级后重跑 `sh install.sh all`。

### 磁盘满

```sh
df -h /
du -sh /opt/dashplay/state/*
```

`state/receiver` 下的 `.jsa` 归档和日志会涨。清掉旧的 `.jsa` 不影响启动（会重建）。

## 其它

### 手机能搜到热点但连不上

检查 `iwinfo wlan0 info` 的 Encryption 是不是 `mixed WPA/WPA2 PSK`。个别老设备对 WPA/WPA2 混合模式挑剔，
改成纯 `psk2` 试试。

### 出画卡顿

N1 是 4 核 A53，30 fps + HEVC 已经接近上限。可以降到 720p / 非 HEVC：

设置页 → 画面参数，或者在 `config.json` 里把 `display.width/height` 调小、`hevc` 设为 false。
改完重启服务。
