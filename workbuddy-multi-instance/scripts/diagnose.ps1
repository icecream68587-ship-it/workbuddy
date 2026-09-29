param(
  [string]$ExpectedExe = 'Z:\软件\software\workbuddy\WorkBuddy.exe'
)

$ErrorActionPreference = 'Stop'

function Info($label, $value) {
  '{0,-22} {1}' -f $label, $value
}

Write-Host '=== WorkBuddy 双开诊断 ===' -ForegroundColor Cyan

# 1. 定位安装目录：优先用已运行进程的路径，其次用默认值
$exe = $null
$running = Get-Process -Name WorkBuddy -ErrorAction SilentlyContinue | Select-Object -First 1
if ($running) { $exe = $running.Path }
if (-not $exe -or -not (Test-Path $exe)) { $exe = $ExpectedExe }

if (Test-Path $exe) {
  Info '程序路径' $exe
  $ver = (Get-Item $exe).VersionInfo
  Info '文件版本' $ver.FileVersion
  $asar = Join-Path (Split-Path $exe -Parent) 'resources\app.asar'
  Info 'app.asar 存在' (Test-Path $asar)
  if (Test-Path $asar) { Info 'app.asar 大小(MB)' ('{0:N0}' -f ((Get-Item $asar).Length / 1MB)) }
} else {
  Write-Host ('未找到 WorkBuddy.exe：' + $exe) -ForegroundColor Yellow
  Write-Host '请先用 -ExpectedExe 参数指定正确路径。' -ForegroundColor Yellow
}

# 2. 目录解析（与程序内部逻辑一致）
$home_ = $env:USERPROFILE
$cfgEnv = $env:WORKBUDDY_CONFIG_DIR
$udEnv  = $env:WORKBUDDY_USER_DATA_DIR
$instNo = $env:WORKBUDDY_INSTANCE_NUMBER
$suffix = if ($instNo) { '-' + $instNo } else { '' }
$cfgDir = if ($cfgEnv) { $cfgEnv } else { Join-Path $home_ ('.workbuddy' + $suffix) }
$udDir  = if ($udEnv)  { $udEnv  } else { Join-Path $cfgDir 'app' }

Write-Host ''
Write-Host '=== 目录 / 环境变量 ===' -ForegroundColor Cyan
Info '当前用户' $env:USERNAME
Info 'WORKBUDDY_CONFIG_DIR' ($(if ($cfgEnv) { $cfgEnv } else { '(未设置)' }))
Info 'WORKBUDDY_USER_DATA_DIR' ($(if ($udEnv) { $udEnv } else { '(未设置)' }))
Info 'WORKBUDDY_INSTANCE_NUMBER' ($(if ($instNo) { $instNo } else { '(未设置)' }))
Info '推算 配置目录' $cfgDir
Info '推算 userData' $udDir
Info 'userData 已存在' (Test-Path $udDir)

# 3. 窗口与进程
$wins = @(Get-Process -Name WorkBuddy -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -ne '' })
$procs = @(Get-Process -Name WorkBuddy -ErrorAction SilentlyContinue)
Write-Host ''
Write-Host '=== 运行状态 ===' -ForegroundColor Cyan
Info 'WorkBuddy 进程数' $procs.Count
Info '有标题的窗口数' $wins.Count

# 4. 第二账户
Write-Host ''
Write-Host '=== 第二账户 ===' -ForegroundColor Cyan
$acct = Get-LocalUser -Name 'wb2' -ErrorAction SilentlyContinue
if ($acct) {
  Info 'wb2 存在' ('是（启用：' + $acct.Enabled + '）')
  Info 'wb2 上次登录' $(if ($acct.LastLogon) { $acct.LastLogon } else { '从未登录' })
  # 别人的用户目录默认拒绝访问，必须吞掉异常
  $wb2Dir = 'C:\Users\wb2\.workbuddy\app'
  $wb2State = '未知（无访问权限）'
  try { $wb2State = if (Test-Path $wb2Dir -ErrorAction Stop) { '已建立' } else { '尚未建立' } } catch { }
  Info ('wb2 数据目录') ($wb2Dir + ' → ' + $wb2State)
} else {
  Info 'wb2 存在' '否 —— 需管理员运行 new-second-account.ps1 创建'
}

# 5. 结论
Write-Host ''
Write-Host '=== 结论 ===' -ForegroundColor Cyan
if ($wins.Count -ge 2) {
  Write-Host '已经有两个 WorkBuddy 窗口在运行。' -ForegroundColor Green
} elseif ($acct) {
  Write-Host ('当前 1 个窗口；账户 wb2 就绪 → 运行 launch-second.ps1 开第二个。') -ForegroundColor Yellow
} else {
  Write-Host '当前 1 个窗口；尚未创建第二账户 → 管理员运行 new-second-account.ps1。' -ForegroundColor Yellow
}

Write-Host ''
Write-Host '按回车键退出...'
[void][System.Console]::ReadLine()
