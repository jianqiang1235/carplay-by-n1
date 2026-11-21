# 发布与发版

仓库已上线：<https://github.com/jianqiang1235/carplay-by-n1>（public，单条 `init` 提交）

## 一、本地改动怎么推

本机装的是便携版 MinGit，没有全局 `git`：

```powershell
$git = "C:\Users\Administrator\Doubao\chats\2026-11-21\new-chat-2\mingit\cmd\git.exe"
$repo = "C:\Users\Administrator\Doubao\chats\2026-11-21\new-chat-2\carplay-by-n1"

& $git -C $repo add -A
& $git -C $repo commit --amend -m "init: DashPlay 在斐讯 N1（opkg 体系 OpenWrt / Lean LEDE）上的安装适配"
& $git -C $repo push --force "https://x-access-token:<TOKEN>@github.com/jianqiang1235/carplay-by-n1.git" main
```

用 `commit --amend` + `push --force` 是为了让仓库始终只有一条提交（历史干净，diff 一屏能看完）。
如果以后确实需要保留演进过程，就去掉 `--amend`，正常 `commit` + `push`。

**两个不能动的设置**：`.gitattributes`（`* text=auto eol=lf`）和 `core.autocrlf=false`。
少了任何一个，Windows 上提交的 `install.sh` 会带 CRLF，到 N1 上执行直接 `$'\r': not found`。

## 二、发一个 Release

### 网页法（推荐，最不容易错）

1. 打开 <https://github.com/jianqiang1235/carplay-by-n1/releases/new>
2. **Choose a tag** 输入 `v0.2.0` → 点 **Create new tag on publish**
3. 填标题，正文写清"这次改了什么、适配哪个上游版本"
4. 点 **Publish release**

### API 法

```powershell
$tok = "<TOKEN>"
$body = @{
  tag_name         = "v0.2.0"
  target_commitish = "main"
  name             = "v0.2.0 — 一句话说明"
  body             = "改动说明（markdown）"
  draft            = $false
  prerelease       = $false
  make_latest      = "true"     # 注意：必须是字符串 "true"，传布尔会 422
} | ConvertTo-Json -Depth 5

Invoke-RestMethod -Method Post `
  -Uri "https://api.github.com/repos/jianqiang1235/carplay-by-n1/releases" `
  -Headers @{ Authorization = "Bearer $tok"; Accept = "application/vnd.github+json" } `
  -ContentType "application/json; charset=utf-8" `
  -Body ([Text.Encoding]::UTF8.GetBytes($body))
```

### 要不要上传附件

**不用。** 每个 Release 页面底部 GitHub 会自动生成 `Source code (zip)` 和 `Source code (tar.gz)`，
指向那个 tag 的完整快照，够用。只有需要单独分发二进制（比如预编译好的 bundle）时才传附件。

下载地址规则：

```
https://github.com/jianqiang1235/carplay-by-n1/archive/refs/tags/v0.2.0.tar.gz
```

N1 上直连 GitHub 不通，套 gh-proxy：

```sh
curl -fL -o cbn.tar.gz https://gh-proxy.com/https://github.com/jianqiang1235/carplay-by-n1/archive/refs/tags/v0.2.0.tar.gz
```

### tag 命名

`v` + 主.次.修（`v0.1.0`、`v0.2.0`）。版本号只反映**这个仓库**的脚本演进，和上游 DashPlay 的
`2026.11.13` 不是一套东西，别混。适配的上游版本写进 Release 正文的表格里。

## 三、发版前自检

```powershell
$repo = "C:\Users\Administrator\Doubao\chats\2026-11-21\new-chat-2\carplay-by-n1"
# 1. 认证文件没混进来（期望无输出）
Get-ChildItem -Path $repo -Recurse -Include *.pk8,*.p7b,*.p12 | Select-Object FullName
# 2. root 密码没写进去（把 <密码> 换成真实密码原文查，期望无输出）
Select-String -Path (Get-ChildItem -Path $repo -Recurse -Include *.md,*.sh,*.py).FullName -Pattern "<密码>"
# 3. 换行全为 LF（期望每行 i/lf）
& $git -C $repo ls-files --eol
```

`password` 会命中，那是热点密码，文档里必须写，可以保留。
`*.pk8` / `*.p7b` 属于 Apple 的 MFi 身份，公开出去是法律风险，不是技术问题。

## 四、上游换版本时

1. 从 <https://github.com/yizhixiaoheigou/DashPlay/releases/latest> 拿新版本号和 bundle
2. 改 `install.sh` 顶部的 `DP_VER` 和 `BUNDLE_SHA`
3. 上游若改了代码结构，`patches/apply_patches.py` 会报 `[未找到目标]`，对照 README 的四条补丁
   人工更新匹配串
4. 在 N1 上用 `install.sh deps` 重跑一遍（脚本是幂等的），确认服务能起
5. 发新 Release
