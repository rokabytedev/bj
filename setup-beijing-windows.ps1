# setup-beijing-windows.ps1 — 北京新机【管理员 PowerShell】运行。基础开机自启(可靠性放宽:父母可重启兜底)。
$ErrorActionPreference = "Continue"   # 单项失败不中断,保证关键任务先落地

Write-Host "== [1/3] 关键:登录时自动拉起 WSL(让 systemd 带起 tailscaled) ==" -ForegroundColor Cyan
$action = 'wsl.exe -d Ubuntu -u root --exec /bin/sh -c "while true; do sleep 3600; done"'
schtasks /create /tn "Beijing-WSL-Tailnet" /tr $action /sc onlogon /rl highest /f
Write-Host "计划任务已创建(登录触发,保活 WSL 虚拟机)。" -ForegroundColor Green

Write-Host "== [2/3] .wslconfig:不让 WSL 空闲回收(无 BOM 写入) ==" -ForegroundColor Cyan
$wslcfg = Join-Path $env:USERPROFILE ".wslconfig"
[System.IO.File]::WriteAllText($wslcfg, "[wsl2]`nvmIdleTimeout=-1`n", (New-Object System.Text.UTF8Encoding($false)))
Write-Host "已写 $wslcfg"

Write-Host "== [3/3] 电源:插电永不睡/不休眠/关快速启动/合盖不操作(容错) ==" -ForegroundColor Cyan
try { powercfg /change standby-timeout-ac 0 } catch { Write-Warning "standby 设置失败,忽略" }
try { powercfg /change hibernate-timeout-ac 0 } catch {}
try { powercfg /h off } catch { Write-Warning "关休眠失败,忽略" }
try {
  powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
  powercfg /setactive SCHEME_CURRENT
} catch { Write-Warning "合盖设置失败(部分机型别名不认),可在 GUI 设'合盖不操作',忽略" }

Write-Host "`n手动项见清单:① 装 WSL 本体 ② 建议开自动登录(重启后免人工登录) ③ RustDesk 可选。" -ForegroundColor Yellow
