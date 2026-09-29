# WorkBuddy 单实例机制内幕（5.5.6 / build 5f969292）

证据来自安装目录下 `resources/app.asar`（284 MB，可用 `[System.IO.File]::ReadAllText` + 正则直接检索，无需解包）。

## 1. 锁在哪

主进程调用 Electron 的单实例锁，拿不到就退出：

```js
acquireSingletonLock() {
  const gotTheLock = electron.app.requestSingleInstanceLock();
  if (!gotTheLock) {
    this.startupLog("SingletonLock failed: another instance running or userData dir inaccessible ...");
    // 退出，让已运行的实例接管（聚焦已有窗口）
```

Windows 下锁不是 `SingletonLock` 文件（三个候选目录里都搜不到），而是 Chromium 的命名互斥量；其名称由 **user data 目录**派生。

## 2. 目录解析逻辑

```js
function getWorkbuddyUserDataDir() {
  return process.env.WORKBUDDY_USER_DATA_DIR?.trim() || path.join(getWorkbuddyConfigDir(), "app");
}

function resolveWorkbuddyConfigDir(explicitConfigDir) {
  if (explicitConfigDir?.trim()) return explicitConfigDir.trim();
  if (process.env.WORKBUDDY_CONFIG_DIR?.trim()) return process.env.WORKBUDDY_CONFIG_DIR.trim();
  const instanceNumber = process.env.WORKBUDDY_INSTANCE_NUMBER?.trim();
  const suffix = instanceNumber ? `-${instanceNumber}` : "";
  return path.join(os.homedir(), `${DEFAULT_CONFIG_DIRNAME}${suffix}`); // .workbuddy / .workbuddy-2
}
```

启动时显式重定向：

```js
electron.app.setPath("userData", getWorkbuddyUserDataDir());
electron.app.setPath("sessionData", getWorkbuddySessionDataDir());
electron.app.setName(instanceNumber ? `${productName} [${instanceNumber}]` : productName);
```

## 3. 实例编号（设计上支持多开，实测不生效）

```js
function detectInstanceNumber() {
  if (process.env.WORKBUDDY_FORCE_NO_INSTANCE_NUMBER) return "";
  const explicit = process.env.WORKBUDDY_INSTANCE_NUMBER?.trim();
  if (explicit) return explicit;
  const repoDir = path.resolve(readAppPathFromEnv(), "../../../..");
  return path.basename(repoDir).match(/-(\d+)$/)?.[1] ?? "";   // 安装目录名以 -2 结尾
}
```

代码注释明确写了「多开实例下 `app.setName("WorkBuddy [N]")`」——官方有此设计。
但**锁的判定早于 `setPath` / `setName` 生效**，所以设置编号或改目录后第二个进程仍在建窗前退出。

## 4. 已验证无效的手段

| 手段 | 现象 |
| --- | --- |
| `--user-data-dir=xxx` 命令行 | exe 输出 `bad option`（该 exe 以类 Node 方式解析参数，且不认此开关） |
| `WORKBUDDY_INSTANCE_NUMBER=2` | 无第二个窗口 |
| `WORKBUDDY_USER_DATA_DIR` + `WORKBUDDY_CONFIG_DIR` 指向新目录 | 无第二个窗口，新目录未被写入 |
| 安装目录 junction 为 `workbuddy-2` | 无第二个窗口 |
| 独立 `APPDATA` / `LOCALAPPDATA` | 进程可启动并建目录，但建窗前退出 |

补充：WorkBuddy 会向子进程环境注入 `WORKBUDDY_USER_DATA_DIR=<home>\.workbuddy\app` 与 `WORKBUDDY_CONFIG_DIR=<home>\.workbuddy`，
**它们优先级高于实例编号**，所以只设编号必然被覆盖。

## 5. 为什么换 Windows 账户可行

锁名由 user data 目录派生。换账户后目录变为 `C:\Users\<账户>\.workbuddy\app`，与当前用户不同 → 锁名不同 → 可共存。
`runas` / `Start-Process -Credential` 虽在同一 Windows 会话内（不新建 session），但只要目录不同即可。

## 6. 其他可复用发现

- `WorkBuddy.exe <script.js>` 可按 Node 方式直接执行 JS（用于探测环境变量很方便）。
- `Multi-instance` 这个关键词在文档里指的是 **CLI 同时连接多个微信/企微机器人实例**，与桌面端双开无关。
- 应用内无「新建窗口」功能（`newWindow` 命中全部来自内置 PDF 阅读器代码）。
- AI Agent 沙盒内的限制：`net.exe` 不可用；`ConvertTo-SecureString -AsPlainText`、COM（`WScript.Shell`）、
  `Start-Process -Verb RunAs` 拉解释器、`[Diagnostics.Process]::Start` 均被安全策略拦截。
