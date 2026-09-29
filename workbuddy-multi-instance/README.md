# WorkBuddy 双开方案（Windows）

在 **一台 Windows 机器上同时开两个 WorkBuddy 桌面窗口**。

> 适用场景：需要两个独立登录态 / 独立数据目录并行工作。
> 仅依赖系统功能，不修改、不破解、不注入 WorkBuddy 任何文件。

## 为什么需要这个

WorkBuddy 桌面端主进程会调用 `app.requestSingleInstanceLock()`：第二次启动只会聚焦已有窗口然后退出。
常见网传办法（命令行 `--user-data-dir`、环境变量 `WORKBUDDY_INSTANCE_NUMBER`、复制安装目录等）**实测全部无效**，
本仓库验证过的失败清单见下方表格。

真正可行的路径是：**换一个 Windows 账户运行第二个实例** —— 进程身份、数据目录、单实例锁一起隔离。

## 快速开始

```powershell
# 1) 诊断（只读）
powershell -ExecutionPolicy Bypass -File .\scripts\diagnose.ps1

# 2) 创建第二账户（管理员，只需一次）
powershell -ExecutionPolicy Bypass -File .\scripts\new-second-account.ps1 -Name wb2 -Password 'wb2@2026'

# 3) 打开第二个 WorkBuddy
powershell -ExecutionPolicy Bypass -File .\scripts\launch-second.ps1 -User '.\wb2'
```

第 3 步会弹出凭据框，输入该账户密码即可（输入无任何回显）。首次启动约 30~90 秒，随后会要求重新登录 WorkBuddy 账号（新环境，正常）。

命令行党可用 `runas`：

```bat
runas /savecred /user:wb2 "Z:\软件\software\workbuddy\WorkBuddy.exe"
```

`/savecred` 会记住凭据，之后双击即开。或者用脚本的 `-UseRunAs` 参数。

## 脚本说明

| 脚本 | 作用 | 需要管理员 |
| --- | --- | --- |
| `scripts/diagnose.ps1` | 打印安装路径、版本、配置目录、环境变量、窗口数、第二账户状态 | 否 |
| `scripts/new-second-account.ps1` | 创建 / 重置第二账户并加入 Users 组 | 是 |
| `scripts/launch-second.ps1` | 检查账户 → 凭据框或 runas → 以该身份启动 WorkBuddy | 否 |

`SKILL.md` 是给 AI Agent 用的技能描述；`references/internals.md` 记录了单实例锁的代码级证据。

`extras/` 是本机实际使用过的早期版本（单文件启动器、桌面 bat、`runas` 备用启动器），
功能已被 `scripts/` 覆盖，仅作留档。

## 实测无效的方案（别再试了）

| 方式 | 结果 |
| --- | --- |
| `WorkBuddy.exe --user-data-dir=xxx` | 报 `bad option`，exe 不认该开关 |
| 环境变量 `WORKBUDDY_INSTANCE_NUMBER=2` | 无效 |
| `WORKBUDDY_USER_DATA_DIR` / `WORKBUDDY_CONFIG_DIR` 指向新目录 | 无效 |
| 安装目录改名或 junction 为 `workbuddy-2` | 无效 |
| 独立 `APPDATA` / `LOCALAPPDATA` | 进程可启动但建窗前退出 |
| 应用内「新建窗口」 | 不存在 |

## 已知坑

- **`.ps1` 必须带 UTF-8 BOM**。PowerShell 5.1 对无 BOM 文件按 GBK 解析，中文后的引号会被吞，报 `缺少右“)”`。
- **凭据框不回显**：输密码时屏幕上什么都没有，盲打后回车。
- **点「确定」无反应**：先点弹窗标题栏给焦点，再点确定，或直接按回车。
- **提示用户名或密码不正确**：密码不匹配。管理员执行
  `Set-LocalUser wb2 -Password (ConvertTo-SecureString 'wb2@2026' -AsPlainText -Force)`，
  并确认输密码前已切英文输入法（`@` 是半角，Shift+2）。

## 测试环境

- WorkBuddy 5.5.6（build 5f969292）/ Electron 37.10.3 / Node 22.21.1
- Windows 11，安装目录 `Z:\软件\software\workbuddy`

版本升级后若官方放开原生多开，先跑 `diagnose.ps1` 再决定是否需要本方案。

## 许可

MIT
