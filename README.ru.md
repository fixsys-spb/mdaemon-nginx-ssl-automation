
---

### 2. `README.ru.md` (Russian Version)

```markdown
# Автоматизация SSL для MDaemon через Nginx Proxy Manager

[🇬🇧 English version](README.md)

Автоматическое обновление SSL-сертификатов Let's Encrypt для почтовых серверов MDaemon (Windows Server) с помощью Nginx Proxy Manager (Linux) и Samba.

## 📖 Описание проблемы
MDaemon на Windows Server не умеет автоматически забирать сертификаты из Nginx Proxy Manager (NPM). Администраторам приходится вручную конвертировать файлы `.pem` в `.pfx`, импортировать их в хранилище Windows, менять отпечаток в `MDaemon.ini` и перезапускать службу.

Этот репозиторий содержит готовое решение:
1. **Nginx (NPM)** сам выпускает и обновляет сертификаты.
2. **Samba** отдает файлы сертификатов в локальную сеть.
3. **PowerShell-скрипт** на Windows забирает файлы, безопасно обновляет конфигурацию MDaemon, перезапускает службу и удаляет старые сертификаты.

## 🏗 Архитектура
* **Linux (например, 192.168.1.3):** Docker + Nginx Proxy Manager + Samba.
* **Windows (например, 192.168.1.9, 192.168.1.11):** MDaemon + OpenSSL + PowerShell.

## 🛠 Предварительные требования

### Linux-сервер (Nginx):
1. Развернут Nginx Proxy Manager (см. `linux/docker-compose.yml`).
2. Настроены Proxy Hosts с получением SSL Let's Encrypt.
   * *Примечание по SAN-сертификатам:* Если у вас несколько доменов для одного сервера MDaemon, перечислите их все в поле **Domain Names** через **пробел** (например, `mail.domain.com domain2.com domain3.com`). NPM сгенерирует один общий сертификат, содержащий их все.
3. Установлена и настроена Samba для раздачи папки `/data/letsencrypt/live` (см. `linux/smb.conf.txt` и `linux/smb.conf.global.patch.txt`).

### Windows-сервер (MDaemon):
> ⚠️ **ВНИМАНИЕ (БЕЗОПАСНОСТЬ):** Шаги ниже включают небезопасный гостевой доступ SMB и SMB1 для совместимости с простой настройкой Samba. Это следует делать только в изолированной доверенной локальной сети. Для производственной среды настройте Samba с выделенным пользователем (`valid users`) и используйте `net use` в PowerShell для авторизации.
> 
> ⚠️ **ВНИМАНИЕ (ПУТИ):** В скриптах по умолчанию указан путь `D:\MDaemon`. Если ваш MDaemon установлен на диск `C:\`, вы **обязаны** изменить переменную `$MDaemonPath` в файлах `Update-Cert.ps1` и `Install-CertTask.ps1`.

1. Включен гостевой доступ SMB (если используется Samba без пароля):
   ```powershell
   Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" -Name "AllowInsecureGuestAuth" -Value 1 -Type DWord

    Установлен OpenSSL (рекомендуется OpenSSL-x64-hybridCRT-4.1.0.exe от OpenSSL Corporation).

    Включен клиент SMB1 (если требуется для совместимости с Samba):
    powershell

    Enable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol-Client -All -NoRestart

🚀 Установка и настройка

    Скопируйте папку windows на сервер MDaemon (например, в D:\MDaemon\Scripts\).

    Откройте Update-Cert.ps1 и проверьте пути:

        $MDaemonPath (по умолчанию D:\MDaemon).

        $NginxShare (сетевой путь к шаре Samba).

    Откройте Install-CertTask.ps1 и проверьте переменную $CertFolder (например, npm-3 для Сервера 1, npm-4 для Сервера 2). Скрипт автоматически определяет свой путь.

    Запустите Install-CertTask.ps1 от имени Администратора, чтобы создать задачу в Планировщике Windows на ежедневный запуск в 04:00.

⚙️ Как это работает

    Mutex (Защита от дурака): Скрипт не запустится, если предыдущий экземпляр еще работает.

    Умное ожидание: Используется цикл ожидания полной остановки службы MDaemon (до 2 минут), что критически важно для серверов с медленными дисками.

    Безопасная запись INI: Используется API WritePrivateProfileString (через C#), чтобы не повредить MDaemon.ini.

    Очистка: Скрипт автоматически удаляет из хранилища Windows старые сертификаты Let's Encrypt для этого же домена.

⚠️ Известные проблемы и их решения

    Ошибка certutil: ERROR_FILE_NOT_FOUND: Возникает из-за пробелов в путях. Заменено на нативный PowerShell Import-PfxCertificate.

    Служба MDaemon не запускается после обновления: Возникает при одновременном запуске двух копий скрипта. Решено с помощью Mutex и ожидания статуса Stopped.

    Файлы не видны по SMB: Samba по умолчанию не отдает симлинки. Применение глобального патча включает follow symlinks = yes и wide links = yes.

📄 Лицензия