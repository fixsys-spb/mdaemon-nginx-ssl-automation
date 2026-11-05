# MDaemon SSL Automation via Nginx Proxy Manager

[🇷🇺 Русская версия](README.ru.md)

Automated Let's Encrypt SSL certificate renewal for backend services (like MDaemon Mail Server on Windows Server 2019) using Nginx Proxy Manager (Linux) and Samba.

## 📖 Use Case & Problem Statement
**The Problem:** Backend services (like MDaemon on Windows) often cannot directly obtain Let's Encrypt certificates. Ports **80** and **443** are typically already occupied by a frontend reverse proxy (Nginx) or blocked by firewalls. Manually renewing certificates every 90 days, converting `.pem` to `.pfx`, importing them into the Windows Certificate Store, updating `MDaemon.ini`, and restarting services is tedious and prone to human error.

**The Solution:** This repository provides a "Push-Pull" architecture:
1. **Frontend (Nginx Proxy Manager):** Listens on ports 80/443, handles the Let's Encrypt ACME challenge, and securely obtains/renews the certificates.
2. **File Transfer (Samba):** Shares the renewed certificate files over the local network.
3. **Backend (Windows Server):** A scheduled PowerShell script pulls the files, converts them, safely updates the service configuration, restarts it, and cleans up old certificates.

## 🏗 Architecture
* **Linux Gateway (e.g., 192.168.1.3):** Docker + Nginx Proxy Manager + Samba.
* **Windows Backend (e.g., 192.168.1.9):** Windows Server 2019 + MDaemon + OpenSSL + PowerShell.

## 🛠 Prerequisites

### Linux Server (Nginx):
1. **Nginx Proxy Manager** deployed via Docker (see `linux/docker-compose.yml`).
2. **Proxy Hosts configured** with Let's Encrypt SSL.
   * *Note on SAN Certificates:* If you have multiple domains for a single backend server, list them all in the **Domain Names** field separated by **spaces** (e.g., `mail.domain.com domain2.com domain3.com`). NPM will generate a single SAN certificate containing all of them.
3. **Samba** installed and configured to share the `/data/letsencrypt/live` directory (see `linux/smb.conf.txt` and `linux/smb.conf.global.patch.txt`).

### Windows Server (MDaemon):
> ⚠️ **SECURITY WARNING:** The steps below enable insecure guest SMB access and SMB1 for compatibility with simple Samba setups. This should only be done in an isolated, trusted local network. For production, configure Samba with a dedicated user (`valid users`) and use `net use` in PowerShell to authenticate.
> 
> ⚠️ **PATH WARNING:** The scripts default to `D:\MDaemon`. If your MDaemon is installed on `C:\`, you **must** change the `$MDaemonPath` variable in both `Update-Cert.ps1` and `Install-CertTask.ps1`.

1. **Enable SMB access** (if using Samba without passwords). Run in PowerShell:
   ```powershell
   Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" -Name "AllowInsecureGuestAuth" -Value 1 -Type DWord
   ```
2. **Install OpenSSL:** MDaemon on Windows Server 2019 does not ship with OpenSSL. Download and install `OpenSSL-x64-hybridCRT-4.1.0.exe` from the [official OpenSSL GitHub](https://github.com/openssl/installer/releases).
3. **Enable SMB1** (if required for Samba compatibility):
   ```powershell
   Enable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol-Client -All -NoRestart
   ```

## 🚀 Installation & Setup

1. Copy the `windows` folder to your MDaemon server (e.g., to `D:\MDaemon\Scripts\`).
2. Open `Update-Cert.ps1` and verify the paths:
   * `$MDaemonPath` (default: `D:\MDaemon`).
   * `$NginxShare` (UNC path to the Samba share).
3. Open `Install-CertTask.ps1` and verify the `$CertFolder` variable (e.g., `npm-3` for Server 1, `npm-4` for Server 2). The script automatically detects its own path.
4. Run `Install-CertTask.ps1` as Administrator to create a daily Scheduled Task (runs at 04:00 AM).

## 🛠 Manual Operations & Troubleshooting

If you need to test components manually or if something fails, use these commands:

**1. Test Samba Connectivity (from Windows):**
```powershell
# Open network share in Explorer
\\192.168.1.3\certs

# Or test via command line
net use \\192.168.1.3\certs
dir \\192.168.1.3\certs\npm-3
```

**2. Test Scheduled Task Manually:**
```powershell
# Run the task immediately
Start-ScheduledTask -TaskName "MDaemon Cert Update"

# Check the logs for execution results
Get-Content D:\MDaemon\Logs\NginxCertUpdate.log -Tail 20
```

**3. Test OpenSSL Path:**
```powershell
# Check if OpenSSL is accessible
& "C:\Program Files\OpenSSL Library\openssl-4.1\bin\openssl.exe" version
```

**4. Check MDaemon Service Status:**
```powershell
Get-Service -Name MDaemon
```

## ⚙️ How It Works (Script Logic)
* **Mutex Protection:** The script creates a system-wide Mutex. If it runs while another instance is active (e.g., Task Scheduler overlaps with a manual run), the second instance exits immediately to prevent service corruption.
* **Smart Wait:** The script waits for the MDaemon service to fully stop (up to 2 minutes). This is critical for servers with slow disks to ensure databases are closed before updating the INI file.
* **Safe INI Write:** Uses the Windows API `WritePrivateProfileString` (via embedded C#) to update only the specific `CertificateHash` key without corrupting the rest of `MDaemon.ini`.
* **Cleanup:** Automatically removes older Let's Encrypt certificates for the same domain from the Windows Store to prevent clutter.

## ⚠️ Known Issues & Fixes
* **`certutil: ERROR_FILE_NOT_FOUND`**: Caused by spaces in temporary file paths. Fixed by using native PowerShell `Import-PfxCertificate`.
* **MDaemon fails to start after update**: Caused by concurrent script runs. Fixed with Mutex and status waiting.
* **Files not visible over SMB**: Certbot stores certificates as symlinks. Samba ignores them by default. The provided global patch (`smb.conf.global.patch.txt`) enables `follow symlinks = yes` and `wide links = yes`.
* **OpenSSL not found**: The script uses a smart fallback to search `C:\Program Files` if the default path doesn't exist.

## 📄 License
This project is licensed under the MIT License.
