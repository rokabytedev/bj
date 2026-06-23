# setup-beijing-windows.ps1 - Beijing exit-node basic autostart.
# ASCII-only on purpose: Windows PowerShell 5.1 on a Chinese-locale system reads .ps1 as GBK,
# so any non-ASCII (Chinese) comment/string would become mojibake and break the parser.
# Run from a normal PowerShell; it will self-elevate via UAC if not already admin.
$ErrorActionPreference = "Continue"   # don't stop on a single failure; land the critical task first

# Self-elevate: if not admin, relaunch this script elevated via UAC, then exit.
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
  Write-Host "Need admin rights. Relaunching via UAC (click Yes)..." -ForegroundColor Yellow
  Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
  exit
}
Write-Host "== Running as admin, configuring ==" -ForegroundColor Green

Write-Host "== [1/3] Scheduled task: start WSL at logon (systemd brings up tailscaled) ==" -ForegroundColor Cyan
$action = 'wsl.exe -d Ubuntu -u root --exec /bin/sh -c "while true; do sleep 3600; done"'
schtasks /create /tn "Beijing-WSL-Tailnet" /tr $action /sc onlogon /rl highest /f
Write-Host "Scheduled task created (logon-triggered, keeps WSL VM alive)." -ForegroundColor Green

Write-Host "== [2/3] .wslconfig: keep WSL VM from idle-shutdown (written without BOM) ==" -ForegroundColor Cyan
$wslcfg = Join-Path $env:USERPROFILE ".wslconfig"
[System.IO.File]::WriteAllText($wslcfg, "[wsl2]`nvmIdleTimeout=-1`n", (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Wrote $wslcfg"

Write-Host "== [3/3] Power: never sleep/hibernate on AC, disable fast startup, lid=do nothing (best-effort) ==" -ForegroundColor Cyan
try { powercfg /change standby-timeout-ac 0 } catch { Write-Warning "standby setting failed, ignore" }
try { powercfg /change hibernate-timeout-ac 0 } catch {}
try { powercfg /h off } catch { Write-Warning "disable hibernate/fast-startup failed, ignore" }
try {
  powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0
  powercfg /setactive SCHEME_CURRENT
} catch { Write-Warning "lid setting failed (alias unknown on some models); set 'do nothing on lid close' in GUI, ignore" }

Write-Host "`nDone. Manual items: 1) install WSL  2) (recommended) enable auto-logon (netplwiz)  3) RustDesk optional." -ForegroundColor Yellow
Write-Host "Next: WSL step 5 (join tailnet) - ask Claude for the 1-hour preauth key." -ForegroundColor Yellow
