# HTB

Hack The Box automation helpers for machine workflow setup, quick serving, and shell quality-of-life improvements.

## Scripts

- `htb-init`: Creates a per-box workspace, updates `/etc/hosts`, generates `.env`, and runs baseline nmap scans.
- `serve`: Starts a simple HTTP file server for payload transfer.
- `auto-recon`: Performs automatic service enumeration using `target`/`ports` from `.env` (or CLI overrides).
- `rshell`: Fast reverse shell helper with payload/listener generation, `.env` defaults, encoding, and clipboard support.
- `upgrade-shell`: Shell stabilization assistant with step-by-step Linux/Windows upgrade flows.
- `host-payload`: Temporary payload HTTP hosting helper with copy-ready Linux/Windows download commands.

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

## Related Shell Function

See [`bashrc_changes.md`](./bashrc_changes.md) for the `box` bash function and tab-completion setup that pairs with `.env` generated by `htb-init`.
