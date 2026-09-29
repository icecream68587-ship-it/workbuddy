---
name: workbuddy-multi-instance
description: 在同一台 Windows 上双开 / 多开 WorkBuddy 桌面端（5.5.x）：诊断单实例锁、用第二个 Windows 账户隔离启动第二个窗口，含已知无效方案与踩坑清单。当用户问「WorkBuddy 能不能双开 / 多实例 / 开两个窗口 / 同时跑两个账号」时使用。
metadata:
  version: 1.0.0
  tested-on: WorkBuddy 5.5.6 (build 5f969292), Windows 11, Electron 37.10.3
---

# WorkBuddy 桌面端双开

## 结论先行

WorkBuddy 桌面端**默认只能开一个窗口**：主进程调用 `app.requestSingleInstanceLock()`，第二次启动会聚焦已有窗口后退出。

可行方案只有一类：**换 Windows 账户**（进程身份 + 数据目录 + 锁一起隔离）。
以下方式**全部验证无效**，不要浪费时间：

| 方式 | 结果 |
| --- | --- |
| `WorkBuddy.exe --user-data-dir=xxx` | exe 报 `bad option`，且不认这个 Electron 开关 |
| 环境变量 `WORKBUDDY_INSTANCE_NUMBER=2` | 无效（程序读它，但锁没跟着隔离） |
| `WORKBUDDY_USER_DATA_DIR` / `WORKBUDDY_CONFIG_DIR` 指向新目录 | 无效 |
| 安装目录改名 / 目录联接为 `workbuddy-2` | 无效 |
| 独立的 `APPDATA` / `LOCALAPPDATA` | 进程能起来并建目录，但建窗前退出 |
| 应用内「新建窗口」 | 不存在（代码里无此功能） |

## 标准流程

### 1. 诊断（只读，安全）

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\diagnose.ps1
```

输出：安装目录、exe 路径、版本、配置目录 / userData 目录、相关环境变量、当前窗口数、第二账户是否存在。

### 2. 创建第二账户（需管理员，一次性）

右键开始菜单 → 终端(管理员)：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\new-second-account.ps1 -Name wb2 -Password 'wb2@2026'
```

等价单行（不给脚本时用）：

```powershell
$p=ConvertTo-SecureString 'wb2@2026' -AsPlainText -Force; New-LocalUser wb2 -Password $p -PasswordNeverExpires -AccountNeverExpires -FullName 'WorkBuddy 2'; Add-LocalGroupMember -Group Users -Member wb2
```

### 3. 启动第二个窗口

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\launch-second.ps1 -User '.\wb2'
```

脚本会检查账户 → 弹图形凭据框 → `Start-Process -Credential` 启动。
首次 30~90 秒（为该账户建配置），之后要求**重新登录 WorkBuddy 账号**（新环境，正常）。

命令行备选（无弹窗，密码盲打）：

```bat
runas /savecred /user:wb2 "Z:\软件\software\workbuddy\WorkBuddy.exe"
```

`/savecred` 会记住凭据，之后双击即可。

### 4. 验证

两个窗口同时存在、任务栏出现两个 WorkBuddy 图标、两边数据目录不同（`C:\Users\<名>\.workbuddy\app`）。

## 关键坑

- **`.ps1` 必须带 UTF-8 BOM**。PowerShell 5.1 无 BOM 时按 GBK 解析，中文后的引号会被吞掉，报 `缺少右“)”` / 乱码 `'瀹屾垚銆?`。
  修复：`[System.IO.File]::WriteAllText($p, $txt, (New-Object System.Text.UTF8Encoding($true)))`。
- **凭据框不回显**：输入密码时没有任何字符（连星号都没有）。盲打后回车即可。
- **点「确定」没反应**：先点弹窗标题栏给焦点，再点确定，或直接按回车。
- **报「用户名或密码不正确」**：密码不匹配。管理员执行 `Set-LocalUser wb2 -Password (ConvertTo-SecureString 'wb2@2026' -AsPlainText -Force)` 重置，输密码前切英文输入法（`@` = Shift+2，半角）。
- **在 AI Agent 环境里**：`ConvertTo-SecureString -AsPlainText` 常被安全策略拦截，最后输密码必须由人完成。
- **代码里的实例编号机制**：`detectInstanceNumber()` 可从安装目录名 `-2` 或 `WORKBUDDY_INSTANCE_NUMBER` 得到编号，配置目录变 `~/.workbuddy-2`、`app.setName("WorkBuddy [N]")` —— 设计上支持多开，但锁判定早于这些生效，实测仍打不开。详见 `references/internals.md`。

## 已验证环境

- WorkBuddy 5.5.6 / build 5f969292 / Electron 37.10.3 / Node 22.21.1
- Windows 11，安装目录 `Z:\软件\software\workbuddy`（非系统盘亦可）

版本升级后若官方放开多开，先跑 `diagnose.ps1` 看锁与目录，再决定是否还用本方案。
