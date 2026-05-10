# HTB Toolkit Workflow Paths

This guide outlines practical, repeatable paths for using this toolkit during authorized HTB machine work.

## 1) Standard Initial Path (Most Boxes)

1. Initialize box workspace and baseline scans:
```bash
htb-init <box_name> <target_ip>
box <box_name>
```
2. Build service-specific plan from discovered ports:
```bash
enum-ports --mode quick
enum-ports --mode deep --service http --service smb
```
3. Run broader automated follow-up:
```bash
auto-recon
```
4. Parse outputs and seed credential store:
```bash
loot-parse scans
creds import-loot parsed
```
5. Re-run targeted enum with new auth context as needed.

## 2) Web-Heavy Path

Use when primary surface is HTTP/HTTPS.

1. Deep web enumeration:
```bash
enum-ports --service http --service https --mode deep --execute
```
2. Host payloads/scripts for transfer:
```bash
host-payload loot --file <payload_or_script>
```
3. Generate shell/listener quickly:
```bash
rshell --search php
rshell bash --listener rlwrap-nc
```
4. Stabilize foothold shell:
```bash
upgrade-shell linux-pty-python3
```

## 3) SMB/AD-Style Path

Use when SMB/LDAP/Kerberos/WinRM ports are open.

1. Focused service planning/execution:
```bash
enum-ports --service smb --service ldap --service kerberos --service winrm --execute
```
2. Parse candidate usernames/hashes/secrets:
```bash
loot-parse scans
```
3. Store and query creds:
```bash
creds import-loot parsed
creds search --type ntlm
creds search --protocol smb
```
4. Generate reuse command templates:
```bash
creds cmd <id>
```

## 4) Post-Foothold Linux Path

1. Run target-side looting:
```bash
./loot-linux.sh
```
2. Run target-side privesc triage:
```bash
./privesc-linux.sh --mode normal
./privesc-linux.sh --mode stealth --validate-safe
```
3. Run staged privesc tooling when needed:
```bash
deploy-privesc --bundle linux-full
```
4. Parse/extract actionable findings:
```bash
loot-parse privesc
loot-parse loot
```

## 5) Post-Foothold Windows Path

1. Run target-side looting:
```powershell
powershell -ExecutionPolicy Bypass -File .\loot-windows.ps1
```
2. Run target-side privesc triage:
```powershell
powershell -ExecutionPolicy Bypass -File .\privesc-windows.ps1 -Mode normal
powershell -ExecutionPolicy Bypass -File .\privesc-windows.ps1 -Mode stealth -ValidateSafe
```
3. Stage and transfer privesc tooling:
```bash
deploy-privesc --bundle windows-full
```
4. Parse and import discovered auth material:
```bash
loot-parse .
creds import-loot parsed
```

## 6) PrivEsc Tool Deployment Path

Use when you need fast, controlled delivery of trusted enum tools.

1. Stage + host tools:
```bash
deploy-privesc --bundle minimal
```
2. If cache missing, explicitly refresh:
```bash
deploy-privesc --tool linpeas --refresh
```
3. Grab one copy-ready command for script automation:
```bash
deploy-privesc --tool linpeas --quiet command --cmd-platform linux --cmd-tool linpeas
```

## 7) Credential Intelligence Path

1. Add/import creds as soon as found:
```bash
creds add --type password --username <user> --host <target> --protocol smb
creds import-loot parsed
```
2. Track validated success and tags:
```bash
creds update <id> --success --tags local-admin,validated
```
3. Export for reports/hand-off:
```bash
creds export --format md --out creds_report.md
```

## 8) Output/Storage Conventions

- Recon: `scans/`
- Parsed intelligence: `parsed/`
- Local payloads/transfer material: `loot/`, `www/`
- PrivEsc run output: `privesc/`
- Documentation/checklists: project root markdown files

## 9) Recommended Fast Loop

Use this loop continuously:

1. Enumerate (`enum-ports`, `auto-recon`)
2. Foothold/stabilize (`rshell`, `upgrade-shell`)
3. Loot/privesc triage (`loot-*.sh`, `privesc-*.ps1/.sh`, `deploy-privesc`)
4. Parse/store (`loot-parse`, `creds`)
5. Re-enumerate authenticated surfaces

## 10) OPSEC and Safety Defaults

- Prefer plan-first modes (`enum-ports` without `--execute` first).
- Use `--validate-safe` privesc modes before noisier checks.
- Keep destructive actions out unless explicitly required by lab objective.
- Preserve raw outputs for later review and reproducibility.
