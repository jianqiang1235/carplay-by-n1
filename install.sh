#!/bin/sh
# carplay-by-n1 — 在斐讯 N1（opkg 体系 OpenWrt / Lean LEDE）上部署 DashPlay
#
# 用法（root，在 N1 上执行）：
#   sh install.sh deps       安装 python3、下载 bundle 并解包到 /opt/dashplay、打补丁
#   sh install.sh jre        安装 JRE 21 (musl) 与 libstdc++
#   sh install.sh identity   检查 MFi 认证文件（需自备）
#   sh install.sh service    安装 procd 启动脚本、写 uci、开机自启并启动
#   sh install.sh all        依次执行以上全部
#   sh install.sh check      自检（进程/端口/HTTP/配置）
#
# 环境变量可覆盖：
#   DP_VER     DashPlay 版本，默认 2026.11.13
#   DP_ROOT    安装目录，默认 /opt/dashplay
#   DP_MIRROR  下载代理前缀，默认 https://gh-proxy.com/
#   SKIP_SHA   设为 1 可跳过校验（不推荐）

set -u

DP_VER="${DP_VER:-2026.11.13}"
DP_ROOT="${DP_ROOT:-/opt/dashplay}"
DP_MIRROR="${DP_MIRROR:-https://gh-proxy.com/}"
SKIP_SHA="${SKIP_SHA:-0}"

BUNDLE="dashplay-bundle-${DP_VER}.tar"
BUNDLE_SHA="b5661d53cc4c3743878c91db2b04bf5c64f65a6b93e068dded1334e178b2898d"
BUNDLE_URL="https://github.com/yizhixiaoheigou/DashPlay/releases/download/v${DP_VER}/${BUNDLE}"

JRE_TAR="OpenJDK21U-jre_aarch64_alpine-linux_hotspot_21.0.9_10.tar.gz"
JRE_SHA="7f8c230ba505b418e4288e2b34758a6e4da32470944740e5ba0cfaae02271c22"
JRE_URL="https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.9%2B10/${JRE_TAR}"

STDCXX_APK="libstdc++-13.2.1_git20240309-r1.apk"
STDCXX_URL="https://dl-cdn.alpinelinux.org/alpine/v3.20/main/aarch64/${STDCXX_APK}"

HERE=$(cd "$(dirname "$0")" && pwd)

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

# curl 先直连，失败再走镜像前缀。N1 上的 curl 一般预装。
fetch() {
    _url="$1"; _out="$2"
    for u in "$_url" "${DP_MIRROR}${_url}"; do
        say "下载 $_out"
        if curl -fL --connect-timeout 15 --retry 3 --retry-delay 5 -o "$_out.part" "$u"; then
            mv "$_out.part" "$_out"
            return 0
        fi
        rm -f "$_out.part"
    done
    rm -f "$_out.part"
    die "下载失败：$_url（可设 DP_MIRROR 换镜像，例如 https://ghfast.top/）"
}

sha_check() {
    _file="$1"; _want="$2"
    [ "$SKIP_SHA" = "1" ] && { warn "已跳过校验：$_file"; return 0; }
    _got=$(sha256sum "$_file" | awk '{print $1}')
    if [ "$_got" != "$_want" ]; then
        die "SHA256 不匹配：$_file
  期望 $_want
  实际 $_got"
    fi
    say "校验通过 $(basename "$_file")"
}

preflight() {
    [ "$(id -u)" = "0" ] || die "请用 root 执行"
    [ -f /etc/openwrt_release ] || warn "没检测到 openwrt_release，仍继续"
    command -v opkg >/dev/null 2>&1 || die "本机没有 opkg，这套脚本只适用于 opkg 体系的固件"
    command -v curl >/dev/null 2>&1 || { say "安装 curl"; opkg update >/dev/null 2>&1; opkg install curl >/dev/null 2>&1 || die "装不上 curl"; }
}

stage_deps() {
    preflight
    if command -v python3 >/dev/null 2>&1; then
        say "python3 已存在：$(python3 -V 2>&1)"
    else
        say "安装 python3（约 100 MB，btrfs 压缩后占盘不多）"
        opkg update || true
        opkg install python3 || die "python3 安装失败"
    fi
    python3 -c 'import asyncio, ctypes, ssl' 2>/dev/null || die "python3 缺少 asyncio/ctypes/ssl，换固件或补包"

    # 常见缺件，装了不亏
    for p in ip-full iw openssl-util curl; do
        opkg list-installed 2>/dev/null | grep -q "^$p " || opkg install "$p" >/dev/null 2>&1 || true
    done

    tmp="/tmp/dp.$$"
    mkdir -p "$tmp"
    fetch "$BUNDLE_URL" "$tmp/$BUNDLE"
    sha_check "$tmp/$BUNDLE" "$BUNDLE_SHA"

    say "解包到 $DP_ROOT"
    mkdir -p "$tmp/x"
    tar -xf "$tmp/$BUNDLE" -C "$tmp/x" || die "解包失败，bundle 可能不完整"

    # bundle 的层级在各版本间不一致，这里自动识别
    if [ -d "$tmp/x/opt/dashplay" ]; then SRC="$tmp/x/opt/dashplay"
    elif [ -d "$tmp/x/dashplay" ]; then SRC="$tmp/x/dashplay"
    else SRC="$tmp/x"; fi
    [ -d "$SRC" ] || die "解包后没找到程序目录"

    mkdir -p "$DP_ROOT"
    cp -a "$SRC/." "$DP_ROOT/"

    # 这些是运行时状态与本地身份，不能从包里带过来
    for junk in state identity firmware service.json dashplay.service supervisor.py; do
        [ -e "$DP_ROOT/$junk" ] && rm -rf "$DP_ROOT/$junk"
    done
    mkdir -p "$DP_ROOT/state"

    say "打补丁"
    if [ -f "$HERE/patches/apply_patches.py" ]; then
        python3 "$HERE/patches/apply_patches.py" "$DP_ROOT" || die "补丁失败"
    else
        die "找不到 patches/apply_patches.py，请把整个仓库一起拷进来"
    fi

    say "语法自检"
    ( cd "$DP_ROOT" && python3 -m py_compile ./*.py ) || die "py_compile 未通过，补丁可能没打全"
    say "deps 阶段完成"
    rm -rf "$tmp"
}

stage_jre() {
    [ -d "$DP_ROOT" ] || die "还没解包程序，先跑 deps"
    need=0
    [ -x /usr/lib/dashplay-jre/bin/java ] || need=1
    if [ "$need" = 0 ] && /usr/lib/dashplay-jre/bin/java -version >/dev/null 2>&1; then
        say "JRE 已就绪：$(/usr/lib/dashplay-jre/bin/java -version 2>&1 | head -1)"
    else
        tmp="/tmp/dpjre.$$"
        mkdir -p "$tmp"
        fetch "$JRE_URL" "$tmp/$JRE_TAR"
        sha_check "$tmp/$JRE_TAR" "$JRE_SHA"
        say "解压 JRE 到 /usr/lib/dashplay-jre"
        mkdir -p "$tmp/x"
        tar -xzf "$tmp/$JRE_TAR" -C "$tmp/x" || die "JRE 解压失败"
        top=$(ls "$tmp/x" | head -1)
        rm -rf /usr/lib/dashplay-jre
        mv "$tmp/x/$top" /usr/lib/dashplay-jre || die "JRE 落地失败"
        /usr/lib/dashplay-jre/bin/java -version 2>&1 | head -1
        rm -rf "$tmp"
    fi

    # JRE 不自带 libstdc++，而 OpenWrt 源里没有 libstdcpp
    if [ -e /usr/lib/libstdc++.so.6 ]; then
        say "libstdc++ 已存在"
    else
        say "从 Alpine 取 libstdc++（musl 环境同源）"
        tmp="/tmp/dpcxx.$$"
        mkdir -p "$tmp"
        fetch "$STDCXX_URL" "$tmp/apk"
        tar -xzf "$tmp/apk" -C "$tmp" usr/lib/libstdc++.so.6.0.32 2>/dev/null \
            || tar -xzf "$tmp/apk" -C "$tmp" 2>/dev/null \
            || die "解开 apk 失败"
        so=$(find "$tmp" -name 'libstdc++.so.6*' -type f | head -1)
        [ -n "$so" ] || die "apk 里没找到 libstdc++.so.6"
        cp -f "$so" /usr/lib/ || die "拷 so 失败"
        ln -sf "$(basename "$so")" /usr/lib/libstdc++.so.6
        rm -rf "$tmp"
    fi
    ls -l /usr/lib/libstdc++.so.6
    say "jre 阶段完成"
}

stage_identity() {
    ID="$DP_ROOT/identity/offline-mfi"
    mkdir -p "$ID"
    chmod 700 "$DP_ROOT/identity" "$ID" 2>/dev/null || true

    if [ ! -f "$ID/identity.pk8" ] || [ ! -f "$ID/certificate.p7b" ]; then
        warn "认证文件缺失，CarPlay 会握手失败"
        cat <<'EOF'

  CarPlay 需要一份 MFi 认证身份，本项目不分发。自取方式：

    1. 下载 DiPlay v0.2.22 APK
       SHA256 7d04db263834f22010a86847766928113d3503a273e4d2d3440d21552e173139
    2. 解出 assets/offline-mfi/identity.pk8 与 certificate.p7b
    3. 放到下面的位置并设成 0600：

EOF
        echo "       $ID/identity.pk8"
        echo "       $ID/certificate.p7b"
        echo
        echo "  放好后重跑：sh install.sh identity"
        return 1
    fi

    chmod 600 "$ID/identity.pk8" "$ID/certificate.p7b"
    say "验证公私钥配对"
    python3 - "$ID" <<'PY'
import subprocess, sys, pathlib, tempfile, os
d = pathlib.Path(sys.argv[1])
with tempfile.TemporaryDirectory() as t:
    k = os.path.join(t, "k.pem"); c = os.path.join(t, "c.pem")
    subprocess.run(["openssl", "pkcs8", "-inform", "DER", "-in", str(d / "identity.pk8"),
                    "-nocrypt", "-out", k], check=True, capture_output=True)
    priv = subprocess.run(["openssl", "pkey", "-in", k, "-pubout", "-outform", "DER"],
                          check=True, capture_output=True).stdout
    subprocess.run(["openssl", "pkcs7", "-inform", "DER", "-in", str(d / "certificate.p7b"),
                    "-print_certs", "-out", c], check=True, capture_output=True)
    cert = subprocess.run(["openssl", "x509", "-in", c, "-pubkey", "-noout"],
                          check=True, capture_output=True).stdout
    cert_der = subprocess.run(["openssl", "pkey", "-pubin", "-outform", "DER"],
                              input=cert, capture_output=True)
    a = subprocess.run(["sha256sum"], input=priv, capture_output=True).stdout.split()[0]
    b = subprocess.run(["sha256sum"], input=cert_der.stdout, capture_output=True).stdout.split()[0]
    print(("IDENTITY_MATCH" if a == b else "IDENTITY_MISMATCH"), a[:16], b[:16])
    sys.exit(0 if a == b else 1)
PY
    [ $? -eq 0 ] || die "私钥与证书不配对，换一组认证文件"
    ls -l "$ID"
    say "identity 阶段完成"
}

stage_service() {
    [ -f "$HERE/files/dashplay.init" ] || die "找不到 files/dashplay.init"

    if [ ! -f /etc/init.d/dashplay ]; then
        say "安装 /etc/init.d/dashplay"
        cp -f "$HERE/files/dashplay.init" /etc/init.d/dashplay
        chmod 755 /etc/init.d/dashplay
    else
        say "启动脚本已存在，跳过"
    fi

    if [ ! -f /etc/config/dashplay ]; then
        say "写入 /etc/config/dashplay"
        cp -f "$HERE/files/dashplay.uci" /etc/config/dashplay
    else
        say "uci 配置已存在，保留现场"
    fi

    say "开机自启"
    /etc/init.d/dashplay enable
    say "启动服务"
    /etc/init.d/dashplay restart
    sleep 20
    stage_check
}

stage_check() {
    say "自检"
    echo "--- 进程"
    ps | grep -E "supervisor_openwrt|run-receiver|dashplay-jre" | grep -v grep | cut -c1-100
    echo "--- 端口"
    netstat -ltnp 2>/dev/null | grep -E ":18080|:18443|:7000" || echo "端口未监听！"
    echo "--- HTTP"
    printf '  设置页 : ' ; curl -s -o /dev/null -w '%{http_code}\n' -m 6 http://127.0.0.1:18080/
    printf '  画面页 : ' ; curl -sk -o /dev/null -w '%{http_code}\n' -m 8 https://127.0.0.1:18443/
    echo "--- 配置"
    grep -E '"wireless"|"httpPort"|"airPlayPort"' "$DP_ROOT/state/receiver/config.json" 2>/dev/null
    echo "--- 有线占用（插了 iPhone 时应有一条 ESTABLISHED）"
    netstat -tnp 2>/dev/null | grep ":7000" || echo "  暂无连接（iPhone 未插线）"
}

case "${1:-all}" in
    deps)     stage_deps ;;
    jre)      stage_jre ;;
    identity) stage_identity ;;
    service)  stage_service ;;
    check)    stage_check ;;
    all)
        stage_deps
        stage_jre
        if stage_identity; then
            stage_service
        else
            warn "先把认证文件放好，再执行：sh install.sh service"
        fi
        ;;
    *) die "未知阶段：$1（可用 deps / jre / identity / service / check / all）" ;;
esac
