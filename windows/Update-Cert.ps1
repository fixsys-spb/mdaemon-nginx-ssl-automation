param(
    [Parameter(Mandatory=$true)][string]$CertFolder, # Имя папки (npm-3 или npm-4)
    [string]$NginxShare = "\\192.168.1.3\certs",
    [string]$PfxPassword = [System.Guid]::NewGuid().ToString(),
    [string]$MDaemonPath = "D:\MDaemon"
)

$LogFile      = Join-Path $MDaemonPath "Logs\NginxCertUpdate.log"
$MdIniPath    = Join-Path $MDaemonPath "App\MDaemon.ini"
$TempPfx      = Join-Path $env:TEMP "$CertFolder-$(Get-Date -Format 'yyyyMMddHHmmss').pfx"
$ServiceName  = "MDaemon"
$SourceCertPath = Join-Path $NginxShare $CertFolder

# Безопасная функция для записи в INI
$signature = @'
[DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
public static extern bool WritePrivateProfileString(string section, string key, string val, string filePath);
'@
$iniWriter = Add-Type -MemberDefinition $signature -Name "IniWriter" -Namespace "Win32" -PassThru

function Write-Log { param([string]$msg) 
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): $msg"
    Add-Content $LogFile $line; Write-Host $line 
}

# --- ЗАЩИТА ОТ ОДНОВРЕМЕННОГО ЗАПУСКА (MUTEX) ---
$mutex = New-Object System.Threading.Mutex($false, "Global\MDaemonCertUpdateMutex")
if (-not $mutex.WaitOne(0, $false)) {
    Write-Host "Другой экземпляр скрипта уже выполняется. Выход." -ForegroundColor Yellow
    exit
}
# ------------------------------------------------

Write-Log "=== Обновление сертификата из папки $CertFolder ==="

try {
    $fullchain = Join-Path $SourceCertPath "fullchain.pem"
    $privkey   = Join-Path $SourceCertPath "privkey.pem"
    
    if (-not (Test-Path $SourceCertPath)) {
        throw "Сетевая папка $SourceCertPath недоступна. Проверьте Samba на Nginx."
    }
    if (-not (Test-Path $fullchain) -or -not (Test-Path $privkey)) {
        throw "Файлы сертификата не найдены в $SourceCertPath"
    }

    # Копируем локально
    $LocalChain = Join-Path $env:TEMP "fullchain.pem"
    $LocalKey   = Join-Path $env:TEMP "privkey.pem"
    Copy-Item $fullchain $LocalChain -Force
    Copy-Item $privkey $LocalKey -Force

    # --- ПУТЬ К OPENSSL ---
    $openssl = "C:\Program Files\OpenSSL Library\openssl-4.1\bin\openssl.exe"
    if (-not (Test-Path $openssl)) {
        throw "OpenSSL не найден по пути $openssl."
    }

    # Создание PFX
    Write-Log "Создание PFX файла..."
    & $openssl pkcs12 -export -in $LocalChain -inkey $LocalKey -out $TempPfx -passout "pass:$PfxPassword"
    
    if (-not (Test-Path $TempPfx)) {
        throw "Ошибка: OpenSSL не создал файл $TempPfx."
    }

    # Импорт в хранилище Windows
    Write-Log "Импорт в хранилище Windows..."
    $securePass = ConvertTo-SecureString -String $PfxPassword -AsPlainText -Force
    $importedCert = Import-PfxCertificate -FilePath $TempPfx -CertStoreLocation Cert:\LocalMachine\My -Password $securePass
    
    if (-not $importedCert) {
        throw "Не удалось импортировать сертификат в хранилище."
    }

    # Получение отпечатка
    $thumbRaw = $importedCert.Thumbprint
    $thumbIni = ($thumbRaw -replace '(..)', '$1 ').Trim()
    Write-Log "Новый отпечаток: $thumbIni"

    # --- УМНОЕ УПРАВЛЕНИЕ СЛУЖБОЙ ---
    $service = Get-Service -Name $ServiceName -ErrorAction Stop
    
    if ($service.Status -ne 'Stopped') {
        Write-Log "Остановка службы $ServiceName (текущий статус: $($service.Status))..."
        Stop-Service $ServiceName -Force -ErrorAction SilentlyContinue
        # Ждем полной остановки (максимум 60 секунд)
        $timeout = 60
        while ((Get-Service $ServiceName).Status -ne 'Stopped' -and $timeout -gt 0) {
            Start-Sleep -Seconds 2
            $timeout -= 2
        }
        if ((Get-Service $ServiceName).Status -ne 'Stopped') {
            throw "Служба $ServiceName не остановилась за 60 секунд. Обновление прервано."
        }
    } else {
        Write-Log "Служба $ServiceName уже остановлена. Пропуск шага остановки."
    }
    
    # Запись нового отпечатка в INI
    $success = $iniWriter::WritePrivateProfileString("SSL", "CertificateHash", $thumbIni, $MdIniPath)
    if (-not $success) {
        Write-Log "ПРЕДУПРЕЖДЕНИЕ: Не удалось записать через API. Используем резервный метод..."
        (Get-Content $MdIniPath) -replace 'CertificateHash\s*=.*', "CertificateHash=$thumbIni" | Set-Content $MdIniPath
    }
    
    # Запуск службы
    Write-Log "Запуск службы $ServiceName..."
    try {
        $service.Start()
        $service.WaitForStatus('Running', '00:01:00')
        Write-Log "Сертификат успешно активирован."
    } catch {
        throw "Не удалось запустить службу $ServiceName. Ошибка: $($_.Exception.Message)"
    }
    # ----------------------------------------------

    # --- ОЧИСТКА СТАРЫХ СЕРТИФИКАТОВ LET'S ENCRYPT ДЛЯ ЭТОГО ДОМЕНА ---
    Write-Log "Запуск очистки старых сертификатов для домена $($importedCert.Subject)..."
    
    $oldCerts = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { 
        $_.Issuer -match "Let's Encrypt" -and $_.Subject -eq $importedCert.Subject -and $_.Thumbprint -ne $thumbRaw
    }

    if ($oldCerts) {
        foreach ($cert in $oldCerts) {
            try {
                Remove-Item -Path $cert.PSPath -Force -ErrorAction Stop
                Write-Log "✅ Удален старый неактивный сертификат: $($cert.Thumbprint)"
            } catch {
                Write-Log "❌ Не удалось удалить сертификат $($cert.Thumbprint): $($_.Exception.Message)"
            }
        }
    } else {
        Write-Log "Старые сертификаты для этого домена не найдены (хранилище чистое)."
    }
    # --------------------------------------------------------------------------
}
catch {
    Write-Log "КРИТИЧЕСКАЯ ОШИБКА: $($_.Exception.Message)"
    if ((Get-Service $ServiceName).Status -ne 'Running') { 
        Write-Log "Попытка аварийного запуска службы..."
        Start-Service $ServiceName -ErrorAction SilentlyContinue
    }
}
finally {
    if (Test-Path $TempPfx)    { Remove-Item $TempPfx -Force }
    if (Test-Path $LocalChain) { Remove-Item $LocalChain -Force }
    if (Test-Path $LocalKey)   { Remove-Item $LocalKey -Force }
    
    # --- ОСВОБОЖДЕНИЕ MUTEX ---
    if ($mutex) {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }
    # ---------------------------
}