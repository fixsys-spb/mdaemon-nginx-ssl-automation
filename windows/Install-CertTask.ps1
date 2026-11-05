<#
.SYNOPSIS
    Скрипт для создания задачи в Планировщике заданий для обновления сертификатов MDaemon.
.DESCRIPTION
    Создает ежедневную задачу, которая запускает Update-Cert.ps1 с указанными аргументами.
    Задача выполняется с наивысшими правами и независимо от входа пользователя в систему.
    Запуск скрипта:
     powershell.exe -ExecutionPolicy Bypass -File .\Install-CertTask.ps1
#>

# --- Параметры (при необходимости измените) ---
$TaskName        = "MDaemon Cert Update"
$TaskDescription = "Ежедневное обновление SSL-сертификатов Let's Encrypt из Nginx Proxy Manager"
$ScriptPath      = "D:\MDaemon\Scripts\Update-Cert.ps1"
#$CertFolder      = "npm-3" # Для Сервера 1: "npm-3", для Сервера 2: "npm-4"
$CertFolder = "npm-3"
$MDaemonPath     = "D:\MDaemon"
$RunAt           = "04:00" # Время ежедневного запуска
# ----------------------------------------------

# Проверка прав администратора
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "Этот скрипт необходимо запускать от имени Администратора!"
    Exit 1
}

# Формируем аргументы для запуска Update-Cert.ps1
$ArgumentList = "-ExecutionPolicy Bypass -File `"$ScriptPath`" -CertFolder `"$CertFolder`" -MDaemonPath `"$MDaemonPath`""

# 1. Создаем действие (что запускать)
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $ArgumentList

# 2. Создаем триггер (когда запускать)
$Trigger = New-ScheduledTaskTrigger -Daily -At $RunAt

# 3. Настраиваем принципала (от чьего имени и с какими правами)
# LogonType S4U позволяет запускать задачу без сохранения пароля и без активного входа пользователя.
# Для этого учетная запись должна обладать правом "Вход в качестве пакетного задания" (Log on as a batch job).
$CurrentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$Principal = New-ScheduledTaskPrincipal -UserId $CurrentUser -LogonType S4U -RunLevel Highest

# 4. Настраиваем параметры задачи (например, не останавливать при переходе на батарею)
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

# 5. Регистрируем задачу в системе
try {
    Register-ScheduledTask -TaskName $TaskName -Description $TaskDescription -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings -Force -ErrorAction Stop
    Write-Host "✅ Задача '$TaskName' успешно создана/обновлена." -ForegroundColor Green
    Write-Host "   Запуск: Ежедневно в $RunAt" -ForegroundColor Gray
    Write-Host "   Скрипт: $ScriptPath" -ForegroundColor Gray
    Write-Host "   Аргументы: $ArgumentList" -ForegroundColor Gray
}
catch {
    Write-Error "❌ Не удалось создать задачу: $($_.Exception.Message)"
    Write-Host "Попробуйте запустить скрипт еще раз от имени Администратора." -ForegroundColor Yellow
}