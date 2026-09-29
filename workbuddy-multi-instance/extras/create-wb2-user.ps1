# 创建用于双开 WorkBuddy 的第二账户 wb2（需管理员权限运行）
$ErrorActionPreference = 'Stop'
$name  = 'wb2'
$plain = 'wb2@2026'
$log   = 'C:\Users\MECHREVO\WorkBuddy\2026-09-16-18-38-30\_wb_create_user.log'
function Write-Log($msg) { Add-Content -Path $log -Value ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $msg) -Encoding UTF8 }

try {
  $pwd = ConvertTo-SecureString $plain -AsPlainText -Force
  if (Get-LocalUser -Name $name -ErrorAction SilentlyContinue) {
    Set-LocalUser -Name $name -Password $pwd -PasswordNeverExpires $true
    Write-Log "user $name already existed, password reset"
  } else {
    New-LocalUser -Name $name -Password $pwd -FullName 'WorkBuddy Instance 2' `
      -Description 'Second WorkBuddy instance for multi-open' `
      -PasswordNeverExpires -AccountNeverExpires | Out-Null
    Write-Log "user $name created"
  }
  Add-LocalGroupMember -Group 'Users' -Member $name -ErrorAction SilentlyContinue
  Write-Log "added to Users group"
  Write-Log "DONE"
} catch {
  Write-Log ("ERROR: " + $_.Exception.Message)
}
