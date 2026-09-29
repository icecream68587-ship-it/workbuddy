param(
  [string]$User = '.\wb2',
  [string]$Exe  = 'Z:\软件\software\workbuddy\WorkBuddy.exe',
  [switch]$UseRunAs
)

# 以第二个 Windows 账户的身份启动 WorkBuddy，绕过单实例锁
$ErrorActionPreference = 'Stop'

Write-Host '=== WorkBuddy 第二实例启动器 ===' -ForegroundColor Cyan

if (-not (Test-Path $Exe)) {
  Write-Host ('找不到程序：' + $Exe) -ForegroundColor Red
  Write-Host '请用 -Exe 参数指定正确路径。' -ForegroundColor Red
  Write-Host ''
  Write-Host '按回车键退出...'
  [void][System.Console]::ReadLine()
  exit 1
}

$name = ($User -split '\\')[-1]
$acct = Get-LocalUser -Name $name -ErrorAction SilentlyContinue

if (-not $acct) {
  Write-Host ('账户 ' + $name + ' 不存在。请先以管理员身份运行 new-second-account.ps1。') -ForegroundColor Yellow
  Write-Host ''
  Write-Host '按回车键退出...'
  [void][System.Console]::ReadLine()
  exit 1
}
if (-not $acct.Enabled) {
  Write-Host ('账户 ' + $name + ' 已停用。管理员执行：Enable-LocalUser ' + $name) -ForegroundColor Yellow
  Write-Host ''
  Write-Host '按回车键退出...'
  [void][System.Console]::ReadLine()
  exit 1
}

Write-Host ('账户检查通过：' + $name + '（已启用）') -ForegroundColor Green
$dir = Split-Path $Exe -Parent

if ($UseRunAs) {
  # 命令行模式：密码盲打（屏幕无任何回显），/savecred 会记住凭据
  Write-Host '命令行模式：输入密码时屏幕不会显示任何字符，盲打后回车。' -ForegroundColor Cyan
  $plain = $User -replace '^\.\\', ''
  & runas.exe /savecred /user:$plain "`"$Exe`""
  if ($LASTEXITCODE -ne 0) {
    Write-Host ('runas 失败，退出码 ' + $LASTEXITCODE + '（常见原因：密码错误）') -ForegroundColor Red
  } else {
    Write-Host '已发起启动，第二个窗口约 30~90 秒后出现。' -ForegroundColor Green
  }
} else {
  # 图形凭据框：密码不回显，点确定前可先点标题栏确保焦点
  Write-Host '请在弹出的凭据框中输入该账户的密码（输入无任何回显，属正常）。' -ForegroundColor Cyan
  Write-Host '若点确定无反应：先点弹窗标题栏给焦点，再点确定，或直接按回车。' -ForegroundColor Cyan

  $cred = Get-Credential -UserName $User -Message 'WorkBuddy 第二实例 - 请输入密码'
  if ($null -eq $cred) {
    Write-Host '已取消。' -ForegroundColor Yellow
    exit 1
  }

  try {
    Start-Process -FilePath $Exe -WorkingDirectory $dir -Credential $cred
    Write-Host '已发起启动，第二个 WorkBuddy 窗口约 30~90 秒后出现。' -ForegroundColor Green
  } catch {
    Write-Host ('启动失败：' + $_.Exception.Message) -ForegroundColor Red
    Write-Host '若是「用户名或密码不正确」，请管理员重置密码：' -ForegroundColor Yellow
    Write-Host ('  Set-LocalUser ' + $name + ' -Password (ConvertTo-SecureString ''wb2@2026'' -AsPlainText -Force)') -ForegroundColor White
    Write-Host '并确认输密码前已切换为英文输入法（@ 为半角，Shift+2）。' -ForegroundColor Yellow
  }
}

Write-Host ''
Write-Host '按回车键退出...'
[void][System.Console]::ReadLine()
