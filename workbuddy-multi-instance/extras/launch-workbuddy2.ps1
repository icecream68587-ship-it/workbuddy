$ErrorActionPreference = 'Stop'
$exe  = 'Z:\软件\software\workbuddy\WorkBuddy.exe'
$dir  = 'Z:\软件\software\workbuddy'
$user = '.\wb2'

Write-Host 'WorkBuddy 第二实例启动器' -ForegroundColor Cyan

if (-not (Test-Path $exe)) {
  Write-Host ('找不到程序：' + $exe) -ForegroundColor Red
  Read-Host '按回车键退出'
  exit 1
}

$acct = Get-LocalUser -Name 'wb2' -ErrorAction SilentlyContinue
if ($null -eq $acct) {
  Write-Host '账户 wb2 不存在，请先以管理员身份创建它。' -ForegroundColor Yellow
  Read-Host '按回车键退出'
  exit 1
}
if (-not $acct.Enabled) {
  Write-Host '账户 wb2 已停用，请管理员执行 Enable-LocalUser wb2。' -ForegroundColor Yellow
  Read-Host '按回车键退出'
  exit 1
}

Write-Host '账户检查通过：wb2 已启用' -ForegroundColor Green
Write-Host '提示：密码是 wb2@2026' -ForegroundColor Cyan

$cred = Get-Credential -UserName $user -Message 'WorkBuddy 第二实例 - 请输入 wb2 的密码'
if ($null -eq $cred) {
  Write-Host '已取消。' -ForegroundColor Yellow
  exit 1
}

try {
  Start-Process -FilePath $exe -WorkingDirectory $dir -Credential $cred
  Write-Host '已发起启动，第二个 WorkBuddy 窗口约 30~90 秒后出现。' -ForegroundColor Green
} catch {
  Write-Host ('启动失败：' + $_.Exception.Message) -ForegroundColor Red
}

Write-Host '完成。' -ForegroundColor Green
Start-Sleep -Seconds 2
