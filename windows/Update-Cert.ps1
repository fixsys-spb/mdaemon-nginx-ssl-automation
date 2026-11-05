param(
    [Parameter(Mandatory=$true)][string]$CertFolder, # Folder name (e.g., npm-3 or npm-4)
    [string]$NginxShare = "\\192.168.1.3\certs",
    [string]$PfxPassword = [System.Guid]::NewGuid().ToString(),
    [string]$MDaemonPath = "D:\MDaemon"
)

$LogFile      = Join-Path $MDaemonPath "Logs\NginxCertUpdate.log"
$MdIniPath    = Join-Path $MDaemonPath "App\MDaemon.ini"
$TempPfx      = Join-Path $env:TEMP "$CertFolder-$(Get-Date -Format 'yyyyMMddHHmmss').pfx"
$ServiceName  = "MDaemon"
$SourceCertPath = Join-Path $NginxShare $CertFolder

# Safe function for writing to INI (WritePrivateProfileString)
$signature = @'
[DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
public static extern bool WritePrivateProfileString(string section, string key, string val, string filePath);
'@
$iniWriter = Add-Type -MemberDefinition $signature -Name "IniWriter" -Namespace "Win32" -PassThru

function Write-Log { param([string]$msg) 
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): $msg"
    Add-Content $LogFile $line; Write-Host $line 
}

# --- CONCURRENT EXECUTION PROTECTION (MUTEX) ---
$mutex = New-Object System.Threading.Mutex($false, "Global\MDaemonCertUpdateMutex")
if (-not $mutex.WaitOne(0, $false)) {
    Write-Host "Another instance of the script is already running. Exiting." -ForegroundColor Yellow
    exit
}
# ------------------------------------------------

Write-Log "=== Updating certificate from folder $CertFolder ==="

try {
    $fullchain = Join-Path $SourceCertPath "fullchain.pem"
    $privkey   = Join-Path $SourceCertPath "privkey.pem"
    
    if (-not (Test-Path $SourceCertPath)) {
        throw "Network path $SourceCertPath is unreachable. Check Samba on Nginx."
    }
    if (-not (Test-Path $fullchain) -or -not (Test-Path $privkey)) {
        throw "Certificate files not found in $SourceCertPath"
    }

    # Copy locally to avoid network locks
    $LocalChain = Join-Path $env:TEMP "fullchain.pem"
    $LocalKey   = Join-Path $env:TEMP "privkey.pem"
    Copy-Item $fullchain $LocalChain -Force
    Copy-Item $privkey $LocalKey -Force

    # --- OPENSSL PATH ---
    $openssl = "C:\Program Files\OpenSSL Library\openssl-4.1\bin\openssl.exe"
    if (-not (Test-Path $openssl)) {
        throw "OpenSSL not found at $openssl."
    }

    # Create PFX
    Write-Log "Creating PFX file..."
    & $openssl pkcs12 -export -in $LocalChain -inkey $LocalKey -out $TempPfx -passout "pass:$PfxPassword"
    
    if (-not (Test-Path $TempPfx)) {
        throw "Error: OpenSSL failed to create $TempPfx."
    }

    # Import to Windows Store
    Write-Log "Importing to Windows Store..."
    $securePass = ConvertTo-SecureString -String $PfxPassword -AsPlainText -Force
    $importedCert = Import-PfxCertificate -FilePath $TempPfx -CertStoreLocation Cert:\LocalMachine\My -Password $securePass
    
    if (-not $importedCert) {
        throw "Failed to import certificate."
    }

    # Get thumbprint
    $thumbRaw = $importedCert.Thumbprint
    $thumbIni = ($thumbRaw -replace '(..)', '$1 ').Trim()
    Write-Log "New thumbprint: $thumbIni"

    # --- SMART SERVICE MANAGEMENT ---
    $service = Get-Service -Name $ServiceName -ErrorAction Stop
    
    if ($service.Status -ne 'Stopped') {
        Write-Log "Stopping service $ServiceName (current status: $($service.Status))..."
        Stop-Service $ServiceName -Force -ErrorAction SilentlyContinue
        # Wait for full stop (max 60 seconds)
        $timeout = 60
        while ((Get-Service $ServiceName).Status -ne 'Stopped' -and $timeout -gt 0) {
            Start-Sleep -Seconds 2
            $timeout -= 2
        }
        if ((Get-Service $ServiceName).Status -ne 'Stopped') {
            throw "Service $ServiceName failed to stop within 60 seconds. Update aborted."
        }
    } else {
        Write-Log "Service $ServiceName is already stopped. Skipping stop step."
    }
    
    # Write new thumbprint to INI
    $success = $iniWriter::WritePrivateProfileString("SSL", "CertificateHash", $thumbIni, $MdIniPath)
    if (-not $success) {
        Write-Log "WARNING: Failed to write via API. Using fallback method..."
        (Get-Content $MdIniPath) -replace 'CertificateHash\s*=.*', "CertificateHash=$thumbIni" | Set-Content $MdIniPath
    }
    
    # Start service
    Write-Log "Starting service $ServiceName..."
    try {
        $service.Start()
        $service.WaitForStatus('Running', '00:02:00')
        Write-Log "Certificate successfully activated."
    } catch {
        throw "Failed to start service $ServiceName. Error: $($_.Exception.Message)"
    }
    # ----------------------------------------------

    # --- CLEANUP OLD LET'S ENCRYPT CERTIFICATES FOR THIS DOMAIN ---
    Write-Log "Cleaning up old certificates for domain $($importedCert.Subject)..."
    
    $oldCerts = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { 
        $_.Issuer -match "Let's Encrypt" -and $_.Subject -eq $importedCert.Subject -and $_.Thumbprint -ne $thumbRaw
    }

    if ($oldCerts) {
        foreach ($cert in $oldCerts) {
            try {
                Remove-Item -Path $cert.PSPath -Force -ErrorAction Stop
                Write-Log "✅ Removed old inactive certificate: $($cert.Thumbprint)"
            } catch {
                Write-Log "❌ Failed to remove certificate $($cert.Thumbprint): $($_.Exception.Message)"
            }
        }
    } else {
        Write-Log "No old certificates found for this domain (store is clean)."
    }
    # --------------------------------------------------------------------------
}
catch {
    Write-Log "CRITICAL ERROR: $($_.Exception.Message)"
    if ((Get-Service $ServiceName).Status -ne 'Running') { 
        Write-Log "Attempting emergency service start..."
        Start-Service $ServiceName -ErrorAction SilentlyContinue
    }
}
finally {
    if (Test-Path $TempPfx)    { Remove-Item $TempPfx -Force }
    if (Test-Path $LocalChain) { Remove-Item $LocalChain -Force }
    if (Test-Path $LocalKey)   { Remove-Item $LocalKey -Force }
    
    # --- MUTEX RELEASE ---
    if ($mutex) {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }
    # ---------------------------
}