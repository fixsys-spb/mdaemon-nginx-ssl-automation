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
*   **Linux (e.g., 192.168.1.3):** Docker + Nginx Proxy Manager + Samba.
*   **Windows (e.g., 192.168.1.9, 192.168.1.11):** MDaemon + OpenSSL + PowerShell.

## 🛠 Prerequisites

### Linux Server (Nginx):
1. Nginx Proxy Manager deployed (see `linux/docker-compose.yml`).
2. Proxy Hosts configured with Let's Encrypt SSL.
3. Samba installed and configured to share the `/data/letsencrypt/live` directory (see `linux/smb.conf.txt`).

### Windows Server (MDaemon):
1. Insecure guest SMB access enabled (if using Samba without passwords):
   ```powershell
   Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" -Name "AllowInsecureGuestAuth" -Value 1 -Type DWord

    OpenSSL installed (recommended: OpenSSL-x64-hybridCRT-4.1.0.exe from OpenSSL Corporation).
    Default path: C:\Program Files\OpenSSL Library\openssl-4.1\bin\openssl.exe

    SMB1 client enabled (if required for Samba compatibility):
    powershell

    Enable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol-Client -All -NoRestart

🚀 Installation & Setup

    Copy the windows folder to your MDaemon server (e.g., to D:\MDaemon\Scripts\).

    Open Update-Cert.ps1 and verify the paths:

        $MDaemonPath (default: D:\MDaemon).

        $openssl (path to your OpenSSL installation).

        $NginxShare (UNC path to the Samba share).

    Run Install-CertTask.ps1 as Administrator to create a daily Scheduled Task (runs at 04:00 AM).

⚙️ How It Works

    Mutex Protection: The script won't run if another instance is already running.

    Smart Wait: Uses a wait loop for the MDaemon service to fully stop (up to 2 minutes), critical for servers with slow disks.

    Safe INI Write: Uses the WritePrivateProfileString API (via C#) to prevent corrupting MDaemon.ini.

    Cleanup: Automatically removes old Let's Encrypt certificates for the same domain from the Windows Store to prevent clutter.

⚠️ Known Issues & Fixes

    certutil: ERROR_FILE_NOT_FOUND: Caused by spaces in file paths. Fixed by using native PowerShell Import-PfxCertificate.

    MDaemon fails to start after update: Caused by concurrent script runs. Fixed with Mutex and status waiting.

    Files not visible over SMB: Samba does not follow symlinks by default. The provided smb.conf.txt includes follow symlinks = yes and wide links = yes.

📄 License

This project is licensed under the MIT License.