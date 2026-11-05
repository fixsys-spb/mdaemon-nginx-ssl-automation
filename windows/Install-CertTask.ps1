<#
.SYNOPSIS
    Script to create a Scheduled Task for MDaemon certificate updates.
.DESCRIPTION
    Creates a daily task that runs Update-Cert.ps1 with specified arguments.
    The task runs with highest privileges regardless of user login.
#>

# --- Parameters ---
$TaskName        = "MDaemon Cert Update"
$TaskDescription = "Daily Let's Encrypt SSL update from Nginx Proxy Manager"

# Auto-detect the path where this script is located
$ScriptPath      = Join-Path $PSScriptRoot "Update-Cert.ps1" 

$CertFolder      = "npm-3" # CHANGE THIS: For Server 1: "npm-3", for Server 2: "npm-4"
$MDaemonPath     = "D:\MDaemon" # CHANGE THIS if MDaemon is on another drive
$RunAt           = "04:00" # Daily execution time
# ------------------

# Check Admin privileges
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "This script must be run as Administrator!"
    Exit 1
}

# Build argument list
$ArgumentList = "-ExecutionPolicy Bypass -File `"$ScriptPath`" -CertFolder `"$CertFolder`" -MDaemonPath `"$MDaemonPath`""

# 1. Create Action
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $ArgumentList

# 2. Create Trigger
$Trigger = New-ScheduledTaskTrigger -Daily -At $RunAt

# 3. Create Principal (S4U allows running without password, Highest privileges)
$CurrentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$Principal = New-ScheduledTaskPrincipal -UserId $CurrentUser -LogonType S4U -RunLevel Highest

# 4. Create Settings
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

# 5. Register Task
try {
    Register-ScheduledTask -TaskName $TaskName -Description $TaskDescription -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings -Force -ErrorAction Stop
    Write-Host "✅ Task '$TaskName' created/updated successfully." -ForegroundColor Green
    Write-Host "   Schedule: Daily at $RunAt" -ForegroundColor Gray
    Write-Host "   Script: $ScriptPath" -ForegroundColor Gray
    Write-Host "   Arguments: $ArgumentList" -ForegroundColor Gray
}
catch {
    Write-Error "❌ Failed to create task: $($_.Exception.Message)"
    Write-Host "Try running the script again as Administrator." -ForegroundColor Yellow
}