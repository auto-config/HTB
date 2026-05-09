# HTB

Hack The Box automation helpers for machine workflow setup, quick serving, and shell quality-of-life improvements.

## Scripts

- `htb-init`: Creates a per-box workspace, updates `/etc/hosts`, generates `.env`, and runs baseline nmap scans.
- `serve`: Starts a simple HTTP file server for payload transfer.
- `auto-recon`: Performs automatic service enumeration using `target`/`ports` from `.env` (or CLI overrides).
- `rshell`: Fast reverse shell helper with payload/listener generation, `.env` defaults, encoding, and clipboard support.
- `upgrade-shell`: Shell stabilization assistant with step-by-step Linux/Windows upgrade flows.
- `host-payload`: Temporary payload HTTP hosting helper with copy-ready Linux/Windows download commands.
- `loot-parse`: Recursive loot parser that extracts credentials, hashes, URLs, shares, privesc indicators, and summary notes.
- `creds`: Local credential intelligence store for organizing, searching, reusing, importing, and exporting discovered credentials.
- `deploy-privesc`: Privilege-escalation toolkit staging/hosting assistant with transfer command generation and bundle presets.
- `enum-ports`: Port-driven service enumeration planner/executor with safe plan-first behavior and structured scan output.

## `htb-init`

Initialize a Hack The Box target workspace and kick off reconnaissance.

### Syntax

```bash
htb-init <box_name> <ip_address>
```

### Arguments

- `box_name`: Box identifier used for the folder name and host mapping (for example `Lame` or `lame.htb`).
- `ip_address`: Target IPv4 address.

### What It Does

1. Creates `~/Desktop/HTB/<box_name>/` with:
   - `scans/`
   - `loot/`
   - `exploits/`
   - `privesc/`
2. Writes `~/Desktop/HTB/<box_name>/.env` with exported variables:
   - `target`, `box`, `htb_host`, `tun0_ip`, `lhost`, `RHOST`, `LHOST`
3. Updates `/etc/hosts` so `<ip_address> <box_name>.htb` exists (deduplicated/replaced if needed).
4. Runs a full TCP scan:
   - `nmap -Pn -p- --min-rate 5000 -T4 -oA ./scans/allports <ip_address>`
5. Extracts open TCP ports and appends `ports` to `.env` if any are found.
6. Runs enumeration scan against discovered ports:
   - `nmap -Pn -sC -sV -O -p <ports> -oA ./scans/enum <ip_address>`

### Example

```bash
htb-init lame 10.10.10.3
```

After completion:

```bash
box lame
```

## `serve`

Serve files over HTTP from a chosen directory (default current directory).

### Syntax

```bash
serve [directory] [port]
```

### Arguments

- `directory` (optional): Directory to serve. Defaults to `.`.
- `port` (optional): TCP port to bind. Defaults to `8000`.

### Behavior

- Validates that `directory` exists.
- Prints the resolved path and URL.
- Runs:

```bash
python3 -m http.server <port>
```

### Examples

```bash
serve
serve ./loot 8080
```

## `auto-recon`

Automatic recon and service-aware enumeration based on discovered or provided open ports.

### Syntax

```bash
auto-recon [target_ip_or_host] [ports_csv]
```

### Arguments

- `target_ip_or_host` (optional): Target host/IP. If omitted, reads `target` from `.env`.
- `ports_csv` (optional): Comma-separated ports. If omitted, reads `ports` from `.env`; if still missing, runs full TCP discovery first.

### `.env` Integration

When run inside a box directory (for example after `box lame`), `auto-recon` sources local `.env` automatically.

Variable precedence:

1. CLI args (`target`, `ports`)
2. `.env` values (`target`, `ports`)

### Behavior

1. Creates output under `./scans/auto-recon-<timestamp>/`.
2. Resolves `target` and `ports` from args and/or `.env`.
3. If no `ports` were provided or found, runs:
   - `nmap -Pn -p- --min-rate 4000 -T4 -oA ./scans/auto-recon-<timestamp>/nmap/allports <target>`
4. Runs base enum scan:
   - `nmap -Pn -sC -sV -O -p <ports> -oA ./scans/auto-recon-<timestamp>/nmap/enum <target>`
5. Runs service-specific follow-up enumeration for common ports (web, smb, dns, snmp, ldap, nfs, rpc, ftp, ssh, mail, dbs, rdp, winrm, etc.).

### Examples

```bash
# Use .env target and .env ports
auto-recon

# Override target, use .env ports if present
auto-recon 10.10.11.10

# Override both target and ports
auto-recon 10.10.11.10 22,80,443
```

## `rshell`

Fast reverse shell and listener generation utility for HTB/CPTS/OSCP-style workflows.

### Syntax

```bash
rshell <payload_id> [options]
```

### Core Features

- Generates reverse shell payloads for:
  - `bash`, `sh`, `nc-mkfifo`, `nc-e`, `ncat-e`, `socat`, `python`, `python3`, `perl`, `php`, `ruby`, `awk`, `lua`, `powershell`, `cmd`
- Generates web shell stubs:
  - `php-web`, `jsp-web`, `aspx-web`
- Generates bind shells:
  - `bind-bash`, `bind-python3`
- Generates listener commands:
  - `nc`, `rlwrap-nc`, `ncat`, `socat`, `pwncat-cs`
- Shows shell upgrade/stabilization suggestions.

### Networking Defaults

- Auto-detects callback IP from `tun0` first.
- Falls back to another active non-loopback IPv4 interface when `tun0` is unavailable.
- Manual override with `--lhost`.
- Default port via `--lport` (or `RSHELL_DEFAULT_PORT`, fallback `4444`).

### `.env` Integration

If `.env` exists in the current directory, `rshell` auto-loads values like:

- `target`
- `box`
- `tun0_ip`

These are used as defaults where applicable.

### Useful Options

- `--list`: List all payload IDs
- `--search <keyword>`: Search payloads
- `--quiet`: Output payload only
- `--url`: URL-encode payload
- `--b64`: Base64-encode payload
- `--copy`: Copy payload to clipboard (if `xclip`, `xsel`, or `wl-copy` is installed)
- `--listener <name|all>`: Choose listener format
- `--stabilize`: Print stabilization cheat sheet
- `--cradle <bash|powershell> --file <filename>`: Generate HTTP download cradle

### Examples

```bash
# List payloads
rshell --list

# Search payloads
rshell --search php

# Generate bash reverse shell using defaults from .env
rshell bash

# Quiet payload-only output with encoding
rshell python3 --quiet --url
rshell powershell --b64

# Listener preference
rshell bash --listener rlwrap-nc --lport 9001

# Bind shell helper
rshell bind-bash --target 10.10.11.10 --lport 4444

# Stabilization cheat sheet
rshell --stabilize
```

## `upgrade-shell`

Shell upgrade and stabilization reference/helper for fragile reverse shells.

### Syntax

```bash
upgrade-shell <technique_id> [options]
```

### Core Coverage

- Linux:
  - Python3 PTY spawn
  - Python2 PTY spawn
  - `script`-based TTY upgrade
  - `stty raw -echo` handling
  - TERM and terminal resize fixes
  - bash interactive respawn
  - socat full-TTY workflow
  - rlwrap listener usage
  - restricted shell handling tips
- Windows:
  - PowerShell shell improvement tips
  - ConPtyShell guidance
  - Nishang-style guidance
  - winpty usage notes

### Features

- `--list`: List available upgrade techniques
- `--search <keyword>`: Search by keyword
- `--flow <technique_id>`: Show step-by-step flow
- `--quiet`: Commands only output
- `--copy <n>`: Copy Nth attacker/victim command to clipboard
- `--explain`: Beginner-friendly explanations
- Expert-focused concise output by default
- Optional ANSI color output
- Optional interactive selection mode: `--menu`

### HTB `.env` Integration

If `.env` exists in the current directory, `upgrade-shell` loads:

- `target`
- `box`
- `tun0_ip`

These values are used in callback/listener examples (for example socat/PowerShell callback guidance).

### Useful Options

- `--lhost <ip>`: Override callback IP
- `--lport <port>`: Override callback/listener port (default from `UPGRADE_SHELL_DEFAULT_PORT` or `4444`)
- `--rows <n> --cols <n>`: Override terminal sizing values
- `--platform linux|windows|mixed|all`: Filter techniques in list/search
- `--no-color`: Disable ANSI formatting

### Examples

```bash
# Show all techniques
upgrade-shell --list

# Search for Windows techniques
upgrade-shell --search windows

# Standard Linux PTY upgrade flow
upgrade-shell linux-pty-python3

# Command-only output for copy/paste
upgrade-shell linux-socat-fulltty --quiet

# Beginner mode with explanations
upgrade-shell linux-pty-python3 --explain

# Copy first command from chosen flow
upgrade-shell linux-pty-python3 --copy 1
```

## `host-payload`

Temporary payload hosting utility for quickly serving files and generating target download commands.

### Syntax

```bash
host-payload [path] [options]
```

### Core Features

- Start a local HTTP server from:
  - current directory (`.`)
  - `loot`
  - `exploits`
  - `www`
  - `payloads`
  - or any custom path
- Auto-detect hosting IP from `tun0`, with fallback to another active non-loopback interface
- Manual IP override with `--ip`
- Port override with `--port`
- Optional automatic free-port selection with `--auto-port`
- Generate Linux and Windows download/execution commands for a selected file
- Clipboard integration (`xclip`, `xsel`, or `wl-copy` when installed)
- Optional request logging and one-shot mode

### HTB `.env` Integration

If `.env` exists in the current directory, `host-payload` loads:

- `target`
- `box`
- `tun0_ip`

`tun0_ip` is preferred for generated external payload URLs.

### Generated Command Coverage

- Linux:
  - `wget`
  - `curl`
  - bash cradle (`curl | bash`)
  - chmod-and-run example
- Windows:
  - PowerShell download cradle
  - `Invoke-WebRequest` / `iwr`
  - `certutil`
  - `curl.exe`
  - download-and-execute example

### Useful Options

- `--list`: List files available for hosting in the target directory
- `--filter <text>`: Filter file list by substring
- `--file <path>`: Select file for URL/command generation
- `--command <type>`: Output one selected command template
- `--quiet url|command`: Print URL or command only
- `--copy`: Copy URL or selected command to clipboard
- `--bind <addr>`: Bind to specific interface/address (default `0.0.0.0`)
- `--log`: Enable timestamped request logging
- `--oneshot`: Exit after first successful GET request

### Examples

```bash
# Host current directory
host-payload

# Host loot directory on port 8080
host-payload loot --port 8080

# List payloads in exploits directory
host-payload exploits --list

# Generate single Windows certutil command
host-payload . --file rev.exe --command certutil

# Quiet mode for copy/paste
host-payload . --file linpeas.sh --quiet url
host-payload . --file linpeas.sh --command wget --quiet command

# Auto-pick next available port if requested port is in use
host-payload payloads --port 8000 --auto-port
```

## `loot-parse`

Parse raw enumeration/exploitation output into structured, deduplicated loot artifacts.

### Syntax

```bash
loot-parse [input_path] [options]
```

### Core Features

- Recursively parses a directory tree or a single file
- Extracts and deduplicates:
  - usernames
  - passwords/credential lines
  - hashes
  - API-token style secrets
  - URLs
  - domains
  - IP addresses
  - ports
  - SMB shares
  - interesting file/path indicators
  - privilege escalation indicators
- Supports common sources including:
  - nmap output
  - crackmapexec/netexec output
  - enum4linux-ng
  - ldapsearch
  - kerbrute
  - responder logs
  - BloodHound-related exports/logs
  - secretsdump output
  - linpeas/winpeas logs
  - feroxbuster/gobuster output
  - smbclient listings
  - generic text/log files

### Output Structure

By default, writes artifacts into `parsed/`:

- `creds.txt`
- `hashes.txt`
- `users.txt`
- `urls.txt`
- `shares.txt`
- `domains.txt`
- `interesting.txt`
- `ips.txt`
- `ports.txt`
- `tokens.txt`
- `privesc.txt`
- `findings.md`

Optional JSON export:

- `findings.json` (with `--json`)

### HTB `.env` Integration

If `.env` exists, `loot-parse` loads:

- `target`
- `box`
- `tun0_ip`

These values are included in generated summaries.

### Useful Options

- `--summary-only`: Print only counts by category
- `--type <category>`: Show one category (for example `creds`, `hashes`, `urls`)
- `--filter <text>`: Only parse files whose path includes text
- `--quiet`: Scriptable output mode
- `--outdir <dir>`: Custom output directory
- `--json`: Export JSON findings
- `--copy <category>`: Copy category output to clipboard (if clipboard tool exists)
- `--no-color`: Disable ANSI formatting

### Examples

```bash
# Parse current workspace recursively
loot-parse

# Parse only scans tree and print summary counts
loot-parse scans --summary-only

# Extract only URLs in quiet mode
loot-parse . --type urls --quiet

# Parse single file and export JSON
loot-parse ./scans/enum.nmap --json

# Parse with path filter
loot-parse . --filter nmap
```

## `creds`

Local credential database and workflow helper for HTB/CPTS/OSCP operations.

### Syntax

```bash
creds [global-options] <subcommand> [options]
```

### Core Features

- Centralized credential storage using SQLite (offline, portable)
- Supports credential types:
  - `password`
  - `ntlm`
  - `kerberos`
  - `ssh_key`
  - `api_token`
  - `jwt`
  - `cookie`
  - `service_account`
  - `username`
- Tracks metadata:
  - source machine
  - domain
  - host
  - protocol
  - privilege
  - discovery source
  - notes
  - tags
  - date added
  - success/failure flag
- Deduplicates records automatically via stable fingerprinting
- Hides sensitive values by default (show only when explicitly requested)

### Optional Encryption at Rest

- Per-entry encryption of secret values is available with `--encrypt`
- Use `--master-pass` or `CREDS_MASTER_PASS` for decryption
- Safe default: secrets remain masked in output unless `--show-secret` is used

### Subcommands

- `add`: Add credential manually
- `search`: Search by username/domain/host/protocol/type/tag/success
- `list`: List all credentials
- `update`: Update metadata or secret for an existing ID
- `remove`: Delete an entry by ID
- `import-loot`: Import from `loot-parse` output directory (`creds.txt`, `hashes.txt`, `tokens.txt`)
- `export`: Export to `txt`, `csv`, `json`, or `md`
- `cmd`: Generate ready-to-use command templates for a credential
- `stats`: Summary counts and type distribution

### Command Generation Helpers

For a selected credential ID, `creds cmd` generates templates for:

- netexec/crackmapexec
- evil-winrm
- smbclient
- impacket psexec/wmiexec style usage
- ssh
- mysql/postgres
- ldapsearch

### HTB `.env` Integration

If `.env` exists, defaults are pulled where useful:

- `target` (host default)
- `box` (source machine default)
- `tun0_ip` (context for related tooling/workflow)

### Safe Usage Tips

- Prefer `--secret-stdin` to avoid exposing secrets in shell history
- Keep `--show-secret` usage intentional
- Use tags like `local-admin`, `domain-admin`, `sql-admin`, `service-account` for high-value tracking

### Examples

```bash
# Add a password credential (secret prompt if --secret omitted)
creds add --type password --username administrator --host 10.10.10.10 --protocol smb --tags local-admin --success

# Add secret safely from stdin
printf '%s' 'P@ssw0rd!' | creds add --type password --username administrator --host 10.10.10.10 --secret-stdin

# Search and list
creds search --host 10.10.10.10
creds list

# Import from loot-parse output directory
creds import-loot parsed --tags imported

# Generate command templates for ID 5
creds cmd 5

# Export masked results to JSON
creds export --format json --out creds_export.json
```

## `deploy-privesc`

Prepare and host common privilege escalation enumeration tools, then generate copy-ready transfer commands.

### Syntax

```bash
deploy-privesc [options]
```

### Core Features

- Stages Linux and Windows privesc tooling from a local cache
- Hosts selected tools over HTTP (binds to `0.0.0.0` by default)
- Generates Linux and Windows download + execution command examples
- Keeps deployment/staging separate from exploit execution
- Supports GTFOBins and LOLBAS reference links

### Supported Tools

- Linux:
  - `linpeas`
  - `pspy`
  - `linux-exploit-suggester`
- Windows:
  - `winpeas`
  - `seatbelt`
  - `powerup`
  - `sharpup`
  - `watson`
  - `wesng` helper

### Bundle Presets

- `minimal`
- `linux-full`
- `windows-full`
- `stealth-lite`

### Networking Behavior

- Auto-detects VPN IP from `tun0` (fallback to another active non-loopback IP)
- Manual override with `--ip`
- Port override with `--port`
- Optional automatic port selection for busy ports with `--auto-port`
- External hosting URL is displayed for target-side downloads

### HTB `.env` Integration

If `.env` exists, uses context values such as:

- `target`
- `box`
- `tun0_ip`

These values are reflected in output context and default hosting URL selection.

### Cache and Refresh Behavior

- Local toolkit cache is used by default (`~/.local/share/htb-toolkit/privesc`)
- Existing cached files are preferred
- No unexpected downloads: remote fetch/update only occurs with explicit `--refresh`

### Useful Options

- `--list`: List available tools
- `--search <keyword>`: Search tools
- `--tool <name>`: Select one or more tools (repeat flag)
- `--bundle <preset>`: Select preset bundle
- `--platform linux|windows|all`: Filter selection
- `--quiet url|command`: Script-friendly output
- `--cmd-platform linux|windows`: Command style for quiet command mode
- `--cmd-tool <name>`: Choose tool for quiet command output
- `--copy`: Copy first generated command to clipboard (if supported)
- `--oneshot`: Exit after first successful download request
- `--log`: Enable request logging with timestamps
- `--show-refs`: Print GTFOBins/LOLBAS links

### Examples

```bash
# List tools
deploy-privesc --list

# Stage and host minimal bundle using local cache
deploy-privesc --bundle minimal

# Linux-focused staging with auto port adjustment
deploy-privesc --bundle linux-full --platform linux --port 8000 --auto-port

# Refresh selected tool from official source
deploy-privesc --tool linpeas --refresh

# Quiet command output for scripting
deploy-privesc --tool linpeas --quiet command --cmd-platform linux --cmd-tool linpeas

# Print reference links only
deploy-privesc --show-refs
```

## `enum-ports`

Turn discovered open ports into organized, service-specific enumeration plans (and optional execution).

### Syntax

```bash
enum-ports [options]
```

### Core Features

- Accepts target + ports directly
- Optionally loads `target` and `ports` from local `.env`
- Optionally parses nmap output (`--nmap`) to improve service inference
- Maps ports/services to targeted enumeration commands
- Safe default: prints planned commands first (no execution unless `--execute`)
- Saves output to structured scan paths under `./scans/` by default

### Supported Service Coverage

- FTP, SSH, Telnet, SMTP, DNS
- HTTP/HTTPS
- SMB, RPC, NFS
- LDAP, Kerberos
- MSSQL, MySQL, PostgreSQL, Redis, MongoDB
- WinRM, RDP, VNC
- SNMP
- Java RMI
- Elasticsearch
- Docker API
- Kubernetes API

### Enumeration Modes

- `--mode quick`: fast baseline checks
- `--mode deep`: includes heavier content/service checks where applicable
- non-destructive by default

### Execution Controls

- `--execute`: actually run planned commands
- `--resume`: skip commands with existing non-empty output files
- `--service <name>`: run only selected service(s)
- `--port <n>`: run only selected port(s)

### Output Structure

Results are organized with clear filenames including service and port, for example:

- `scans/ports/`
- `scans/web/`
- `scans/smb/`
- `scans/ldap/`
- `scans/snmp/`

This keeps raw output suitable for downstream parsing by `loot-parse`.

### CLI Features

- `--list-services`: list supported services
- `--quiet commands|summary`: script-friendly output
- `--copy <n>`: copy Nth planned command if clipboard tool exists
- `--auto-dirs`: pre-create common output directories
- `--md-summary`: generate markdown summary
- `--no-color`: disable ANSI color

### HTB `.env` Integration

When present, `.env` values are used automatically where relevant:

- `target`
- `ports`
- `box`
- `tun0_ip` (context only)

### Examples

```bash
# Plan only (safe default)
enum-ports --target 10.10.10.10 --ports 22,80,445

# Execute web-only deep checks
enum-ports --target 10.10.10.10 --ports 80,443 --service http --service https --mode deep --execute

# Use .env target/ports and print commands only
enum-ports --quiet commands

# Resume execution and skip existing output files
enum-ports --target 10.10.10.10 --ports 21,22,80 --execute --resume
```

## Related Shell Function

See [`bashrc_changes.md`](./bashrc_changes.md) for the `box` bash function and tab-completion setup that pairs with `.env` generated by `htb-init`.
