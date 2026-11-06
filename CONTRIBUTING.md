# Contributing to MDaemon SSL Automation

First off, thanks for taking the time to contribute! 

## How Can I Contribute?

### Reporting Bugs
This project involves multiple environments (Linux/Docker, Windows Server, Samba). When reporting a bug, please include:
* Your OS versions (Linux distro, Windows Server version).
* Nginx Proxy Manager version.
* MDaemon version.
* The exact error message or the last 20 lines of `NginxCertUpdate.log`.
* A description of your network setup (e.g., are you using LXC, bare metal, etc.).

### Suggesting Enhancements
If you have an idea to make the scripts more robust (e.g., better error handling, adding support for different directory structures), please open an issue with the `enhancement` tag.

### Pull Requests
1. Fork the repo and create your branch from `main`.
2. If you've added code that should be tested, add tests or describe how you tested it manually.
3. Ensure your code passes standard PowerShell/POSIX linting.
4. Update the `README.md` and `README.ru.md` if you change functionality.
5. Issue that pull request!

## Code Style
* **PowerShell:** Use clear variable names, comment complex logic, and ensure `try/catch` blocks are used for external calls (like OpenSSL or Service management).
* **Bash/Samba:** Keep configurations minimal and well-commented.
