param(
  [string]$Name = 'wb2',
  [string]$Password = 'wb2@2026',
  [string]$FullName = 'WorkBuddy Instance 2'
)

# 需以管理员身份运行：创建用于双开 WorkBuddy 的第二个本地账户
$ErrorActionPreference = 'Stop'

$ident = [Security.Principal.WindowsIdentity]::GetCurrent()
$admin = (New-Object Security.Principal.WindowsPrincipal($ident)).IsInRole(
  [Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $admin) {
  Write-Host '当前不是管理员。请右键开始菜单 → 终端(管理员)，再执行本脚本。' -ForegroundColor Red
  Write-Host ''
  Write-Host '按回车键退出...'
  [void][System.Console]::ReadLine()
  exit 1
}

$secure = ConvertTo-SecureString $Password -AsPlainText -Force
$existing = Get-LocalUser -Name $Name -ErrorAction SilentlyContinue

if ($existing) {
  Set-LocalUser -Name $Name -Password $secure -PasswordNeverExpires $true
  Write-Host ('账户 ' + $Name + ' 已存在，已重置密码为：' + $Password) -ForegroundColor Yellow
} else {
  New-LocalUser -Name $Name -Password $secure -FullName $FullName `
    -Description 'Second WorkBuddy instance' `
    -PasswordNeverExpires -AccountNeverExpires | Out-Null
  Write-Host ('账户 ' + $Name + ' 已创建，密码：' + $Password) -ForegroundColor Green
}

Add-LocalGroupMember -Group 'Users' -Member $Name -ErrorAction SilentlyContinue

$u = Get-LocalUser -Name $Name
Write-Host ''
Write-Host ('账户   : ' + $u.Name) -ForegroundColor Cyan
Write-Host ('启用   : ' + $u.Enabled) -ForegroundColor Cyan
Write-Host ('密码   : ' + $Password + '（永不过期）') -ForegroundColor Cyan
Write-Host ''
Write-Host ('下一步：运行 launch-second.ps1 -User .\' + $Name + ' 打开第二个窗口。') -ForegroundColor Green
Write-Host '注意：首次启动约 30~90 秒，并且会要求重新登录 WorkBuddy 账号。' -ForegroundColor Yellow
Write-Host ''
Write-Host '按回车键退出...'
[void][System.Console]::ReadLine()
