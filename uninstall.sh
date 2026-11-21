#!/bin/sh
# carplay-by-n1 — 卸载
#
# 用法：sh uninstall.sh          # 停服务、删程序与 JRE，保留认证文件备份
#       sh uninstall.sh --purge  # 连 uci 与备份一起删

DP_ROOT="${DP_ROOT:-/opt/dashplay}"
PURGE=0
[ "${1:-}" = "--purge" ] && PURGE=1

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

say "停止服务"
/etc/init.d/dashplay stop 2>/dev/null
/etc/init.d/dashplay disable 2>/dev/null
rm -f /etc/rc.d/S99dashplay /etc/rc.d/K10dashplay

say "备份认证文件到 /root/dashplay-identity.bak"
mkdir -p /root/dashplay-identity.bak
[ -d "$DP_ROOT/identity" ] && cp -a "$DP_ROOT/identity/." /root/dashplay-identity.bak/ 2>/dev/null

say "删除程序目录 $DP_ROOT"
rm -rf "$DP_ROOT"

if [ "$PURGE" = "1" ]; then
    say "删除 JRE 与 libstdc++"
    rm -rf /usr/lib/dashplay-jre
    rm -rf /usr/lib/libstdc++.so.6 /usr/lib/libstdc++.so.6.0.32
    say "删除 uci 配置与启动脚本"
    rm -f /etc/config/dashplay /etc/init.d/dashplay
    rm -rf /root/dashplay-identity.bak
else
    say "保留 JRE（/usr/lib/dashplay-jre）、uci 配置和认证文件备份"
fi

say "完成。python3 等 opkg 依赖未动，需要的话自己 opkg remove python3"
