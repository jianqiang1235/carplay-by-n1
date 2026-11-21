#!/usr/bin/env python3
"""carplay-by-n1 — DashPlay 在 OpenWrt / Python 3.11 / OpenSSL 1.1.1 上的四补丁。

幂等：已经补过的文件再跑一遍不会重复改，也不会报错。

用法：
    python3 apply_patches.py /opt/dashplay            # 打补丁
    python3 apply_patches.py /opt/dashplay --check     # 只检查不改
"""
import sys
import pathlib

# (文件, 原文片段, 替换为, 说明)
# 文件里已经找不到原文、但能匹配到结果 → 视为已打过
PATCHES = [
    (
        "settings_page.py",
        "{'scope': scope}",
        '{"scope": scope}',
        "f-string 内同引号嵌套（Python 3.12 才允许）",
    ),
    (
        "setup_wizard.py",
        '", ".join(str(a) for a in local_addresses)',
        "', '.join(str(a) for a in local_addresses)",
        "f-string 内同引号嵌套（Python 3.12 才允许）",
    ),
    (
        "boxnet.py",
        '"-iter", "1",',
        "",
        "OpenSSL 1.1.1 不认 pkcs12 -iter，且与 -nomaciter 互斥",
    ),
    # iphone-usb-bridge.py 的结构改动较大，放在下面单独处理
]

# iphone-usb-bridge.py 的替换是"整块"，单独处理：把写死的 ROLE 定义换成扫描
BRIDGE_OLD = 'ROLE = Path("/sys/class/usb_role/c9040000.usb-role-switch/role")'
BRIDGE_NEW = (
    '_ROLES = sorted(Path("/sys/class/usb_role").glob("*/role"))\n'
    'ROLE = _ROLES[0] if _ROLES else Path("/sys/class/usb_role/c9040000.usb-role-switch/role")'
)


def evaluate(text: str, old: str, new: str) -> str:
    """在文本上判断状态：done（待补）/ already（已补）/ missing（结构不符）"""
    if old in text:
        return "done"
    if new:
        # 有替换内容：新内容在，说明补过了
        return "already" if new in text else "missing"
    # 删除型补丁（new 是空串）：原文不存在就没法二次确认，一律当作已补
    return "already"


def patch_file(path: pathlib.Path, old: str, new: str) -> str:
    text = path.read_text(encoding="utf-8")
    state = evaluate(text, old, new)
    if state == "done":
        path.write_text(text.replace(old, new), encoding="utf-8")
    return state


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    root = pathlib.Path(sys.argv[1])
    check_only = "--check" in sys.argv[2:]
    if not root.is_dir():
        print(f"不是目录：{root}")
        return 2

    failed = []
    for name, old, new, why in PATCHES:
        path = root / name
        if not path.exists():
            print(f"  [跳过] {name} 不存在")
            continue
        if check_only:
            state = evaluate(path.read_text(encoding="utf-8"), old, new)
        else:
            state = patch_file(path, old, new)

        mark = {"done": "已修补", "already": "本就已补", "missing": "未找到目标"}[state]
        print(f"  [{mark}] {name} — {why}")
        if state == "missing":
            failed.append(name)

    # iphone-usb-bridge.py 单独一段
    bridge = root / "iphone-usb-bridge.py"
    if bridge.exists():
        text = bridge.read_text(encoding="utf-8")
        if BRIDGE_OLD in text:
            if not check_only:
                bridge.write_text(text.replace(BRIDGE_OLD, BRIDGE_NEW), encoding="utf-8")
                print("  [已修补] iphone-usb-bridge.py — usb-role 自动扫描")
            else:
                print("  [待修补] iphone-usb-bridge.py")
        elif "_ROLES" in text and "_ROLES[0]" in text:
            print("  [本就已补] iphone-usb-bridge.py — usb-role 自动扫描")
        elif 'c9040000' in text:
            failed.append("iphone-usb-bridge.py")
            print("  [未找到目标] iphone-usb-bridge.py — 结构变了，需要人工看")
        else:
            print("  [本就已补] iphone-usb-bridge.py")

    if failed:
        print("\n以下文件没补上，程序很可能起不来：", ", ".join(failed))
        print("上游代码结构可能变了，请对照 README 的四条补丁人工处理。")
        return 1
    print("\n补丁全部就位。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
