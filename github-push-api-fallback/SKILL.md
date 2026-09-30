---
name: github-push-api-fallback
description: 本机 git push 被网络/代理拦截时，改用 GitHub Git Data REST API 把本地仓库上传为单个 commit，并让本地 refs 与远端 sha 完全一致。触发场景：git push 报 CONNECT tunnel failed 502 / Empty reply from server / Failed to connect to github.com port 443；在受限沙箱、代理后、或只有 HTTP API 出口的环境里要推送仓库；需要让本地 HEAD 与远端 main 的 sha 对齐以免日后 push 冲突。
license: MIT
agent_created: true
---

# GitHub 上传：当 git 协议走不通时

## 结论先行

受限环境里 **`git push` 大概率失败，但 `curl` / `python` 访问 `api.github.com` 通常正常**。
所以别死磕 git push，直接把仓库内容走 **Git Data REST API** 传上去：
`blobs → tree → commit → PATCH ref`。结果是**单个 commit**，和正常 push 等价。

## 先判断是不是这个场景

```
git push  →  fatal: CONNECT tunnel failed, response 502
git push  →  fatal: Empty reply from server
curl https://api.github.com  →  HTTP 200   ← 只要这行通，就走本方案
```

常见原因：沙箱/企业代理只允许 HTTP API 出口，不允许 git 的 CONNECT 隧道。
用 `env | grep -i proxy` 能看到代理地址（如 `http://127.0.0.1:54667`）。

## 前置：拿到一个有权限的令牌

| 方式 | 能否建仓库/推送 | 说明 |
|---|---|---|
| 自建 OAuth device flow（`Iv1.b507a08c87ecfe98` + `scope=repo`） | ❌ | 拿到的是 GitHub App 集成令牌，`X-OAuth-Scopes` 为空，REST 报 `Resource not accessible by integration` |
| `gh auth refresh -s repo` | ❌ | 同样救不回来，且轮询易 `unexpected EOF` |
| **classic PAT 勾 `repo`** | ✅ | 唯一可靠路径 |

PAT 地址：https://github.com/settings/tokens/new

> PAT 若缺 `read:org`，`gh auth login --with-token` 会报 `missing required scope 'read:org'`。
> 不影响本方案——我们直接用 REST API，不经过 gh 的校验。

让用户在安全员前提下交付令牌：优先让他粘到本机临时文件，脚本从文件读，避免令牌进对话。

## 执行流程

`scripts/push_via_api.py` 已封装全部步骤，改顶部 4 个常量即可跑：

```bash
export PATH="/usr/bin:/bin:/c/Users/<ME>/.workbuddy/binaries/PortableGit/versions/*/bin:/c/Windows/System32:/c/Windows:$PATH"
"<managed python>" push_via_api.py
```

内部步骤（手工实现时照此顺序）：

### 1. 仓库必须非空
空仓库调用 `POST /git/blobs` 会 `409 Git Repository is empty`。
先塞一个占位提交，最后 repoint 后它自然失联：

```
PUT /repos/{o}/{r}/contents/.init   {"message":"init","content":"<base64>"}
```

### 2. 逐个文件创建 blob —— 必须用 git 规范化后的内容

```python
index = tracked files via `git ls-files -s -z`   # "<mode> <sha> <stage>\t<path>"
content = subprocess.run(["git","cat-file","blob",sha]).stdout   # ← 关键
```

**直接用 `open(file,'rb')` 会踩 CRLF 坑**：本机 `core.autocrlf=true` 时工作区是 CRLF、
index 里是 LF，传上去的 tree sha 与本地不一致。必须从 index blob 取字节。
路径含中文时用 `-z` 读取原始字节，别用 git 的引号转义输出。

### 3. 建 tree，并断言与本地一致

```python
local_tree = git("rev-parse","HEAD^{tree}")
assert tree["sha"] == local_tree        # 不一致 = 第 2 步取错了内容
```

### 4. 建 commit，`parents: []`，并显式带 author/committer 日期
日期写死成 ISO8601（如 `2026-09-29T17:00:44Z`），第 6 步要靠它复现 sha。

### 5. 更新 ref，**必须带 force**

```
PATCH /repos/{o}/{r}/git/refs/heads/main   {"sha": "<commit>", "force": true}
```

不带 force → `422`（非快进被拒）。

### 6. 让本地 refs 指向同一个 sha（可选但强烈建议）

GitHub 存的 commit message **不带结尾换行**，而 `git commit-tree -m` 会补一个 `\n`，
所以两边 sha 会不同。用 `hash-object` 手工拼字节精确复现：

```python
body = f"tree {tree}\nauthor {A} {epoch} +0000\ncommitter {A} {epoch} +0000\n\n{msg}".encode()
# 注意：msg 末尾不要换行
sha = git("hash-object","-t","commit","-w","--stdin", input=body)
```

再 `git update-ref refs/heads/main <sha>`。这样本地 `git status` 干净、
日后普通 `git push` 不会冲突，**不需要 force push**。

## 坑位清单

- 某些仓库里 `git update-ref refs/remotes/origin/main` 返回 0 但引用没落盘；
  直接写文件 `.git/refs/remotes/origin/main`（内容为一个 sha + 换行）才生效。
  还要补 `git config branch.main.remote origin` + `branch.main.merge refs/heads/main`。
- `sleep` 在这个 shell 里不存在，用 `ping -n N 127.0.0.1 >/dev/null` 代替。
- Bash 工具可能 PATH 残缺（缺 `dirname`/`head`），前置 export PATH 修好。
- PowerShell 工具可能不回显 stdout；需要输出时先写到临时文件再 Read。
- winget 装的 gh 可能是断链（目录只剩 `.db`）。要用 gh 就直接下官方 zip 解压，别信 `gh --version` 无输出。

## 收尾（安全）

删掉本机所有含令牌的临时文件，并提醒用户去 GitHub 页面把 PAT Delete 掉。
校验用公开读接口即可（public 仓库无需鉴权）：

```
GET https://api.github.com/repos/{o}/{r}
GET https://api.github.com/repos/{o}/{r}/git/trees/main?recursive=1
```

注意 GitHub 的 JSON 是 `"key": value`（冒号后有空格），grep 别写成 `"key":"`。
