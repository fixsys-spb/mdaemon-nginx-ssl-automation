# MDaemon SSL Automation via Nginx Proxy Manager

[🇷🇺 Русская версия](README.ru.md)

Automated Let's Encrypt SSL certificate renewal for MDaemon Mail Servers (Windows Server) using Nginx Proxy Manager (Linux) and Samba.

## 📖 Problem Statement
MDaemon on Windows Server cannot natively fetch and apply certificates from Nginx Proxy Manager (NPM) or Certbot. Administrators are forced to manually convert `.pem` files to `.pfx`, import them into the Windows Certificate Store, update the thumbprint in `MDaemon.ini`, and restart the service.

This repository provides a fully automated solution:
1. **Nginx (NPM)** automatically issues and renews certificates.
2. **Samba** shares the certificate files over the local network.
3. **PowerShell script** on Windows fetches the files, safely updates the MDaemon configuration, restarts the service, and cleans up old certificates.

## 🏗 Architecture
* **Linux (e.g., 192.168.1.3):** Docker + Nginx Proxy Manager + Samba.
* **Windows (e.g., 192.168.1.9, 192.168.1.11):** MDaemon + OpenSSL + PowerShell.

## 🛠 Prerequisites

### Linux Server (Nginx):
1. Nginx Proxy Manager deployed (see `linux/docker-compose.yml`).
2. Proxy Hosts configured with Let's Encrypt SSL.
   * *Note on SAN Certificates:* If you have multiple domains for a single MDaemon server, list them all in the **Domain Names** field separated by **spaces** (e.g., `mail.domain.com domain2.com domain3.com`). NPM will generate a single SAN certificate containing all of them.
3. Samba installed and configured to share the `/data/letsencrypt/live` directory (see `linux/smb.conf.txt` and `linux/smb.conf.global.patch.txt`).

### Windows Server (MDaemon):

> ⚠️ **SECURITY WARNING:** The steps below enable insecure guest SMB access and SMB1 for compatibility with simple Samba setups. This should only be done in an isolated, trusted local network. For production, configure Samba with a dedicated user (`valid users`) and use `net use` in PowerShell to authenticate.
> 
> ⚠️ **PATH WARNING:** The scripts default to `D:\MDaemon`. If your MDaemon is installed on `C:\`, you **must** change the `$MDaemonPath` variable in both `Update-Cert.ps1` and `Install-CertTask.ps1`.

1. Enable insecure guest SMB access (if using Samba without passwords):
   ```powershell
   Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" -Name "AllowInsecureGuestAuth" -Value 1 -Type DWord
   ```
2. **OpenSSL** installed (recommended: `OpenSSL-x64-hybridCRT-4.1.0.exe` from OpenSSL Corporation).
3. SMB1 client enabled (if required for Samba compatibility):
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

## ⚙️ How It Works
* **Mutex Protection:** The script won't run if another instance is already running.
* **Smart Wait:** Uses a wait loop for the MDaemon service to fully stop (up to 2 minutes), critical for servers with slow disks.
* **Safe INI Write:** Uses the `WritePrivateProfileString` API (via C#) to prevent corrupting `MDaemon.ini`.
* **Cleanup:** Automatically removes old Let's Encrypt certificates for the same domain from the Windows Store to prevent clutter.

## ⚠️ Known Issues & Fixes
* **`certutil: ERROR_FILE_NOT_FOUND`**: Caused by spaces in file paths. Fixed by using native PowerShell `Import-PfxCertificate`.
* **MDaemon fails to start after update**: Caused by concurrent script runs. Fixed with Mutex and status waiting.
* **Files not visible over SMB**: Samba does not follow symlinks by default. The provided global patch enables `follow symlinks = yes` and `wide links = yes`.

## 📄 License
This project is licensed under the MIT License.
