#!/usr/bin/env bash

set -u

section() {
  printf '\n[+] %s\n' "$1"
}

have() {
  command -v "$1" >/dev/null 2>&1
}

run_to_file() {
  local outfile="$1"
  shift
  {
    echo "### CMD: $*"
    echo "### TS: $(date -Iseconds)"
    echo
    "$@"
  } >"$outfile" 2>&1 || true
}

append_line() {
  echo "$1" >> "$SUMMARY"
}

HOST="$(hostname 2>/dev/null || echo unknown-host)"
TS="$(date +%Y%m%d-%H%M%S)"
ROOT="${PWD}/${HOST}-${TS}-loot"

SYSTEM_DIR="$ROOT/system"
NETWORK_DIR="$ROOT/network"
USERS_DIR="$ROOT/users"
PROCESSES_DIR="$ROOT/processes"
SERVICES_DIR="$ROOT/services"
SCHEDULED_DIR="$ROOT/scheduled"
FILES_DIR="$ROOT/files"
PERMS_DIR="$ROOT/permissions"
SUMMARY_DIR="$ROOT/summary"

mkdir -p "$SYSTEM_DIR" "$NETWORK_DIR" "$USERS_DIR" "$PROCESSES_DIR" "$SERVICES_DIR" "$SCHEDULED_DIR" "$FILES_DIR" "$PERMS_DIR" "$SUMMARY_DIR"

SUMMARY="$SUMMARY_DIR/summary.txt"
: > "$SUMMARY"

append_line "loot-linux summary"
append_line "timestamp: $(date -Iseconds)"
append_line "host: $HOST"
append_line "user: $(whoami 2>/dev/null || echo unknown)"
append_line "root_dir: $ROOT"

section "System"
run_to_file "$SYSTEM_DIR/id.txt" id
run_to_file "$SYSTEM_DIR/uname.txt" uname -a
run_to_file "$SYSTEM_DIR/os-release.txt" cat /etc/os-release
run_to_file "$SYSTEM_DIR/hostnamectl.txt" hostnamectl
run_to_file "$SYSTEM_DIR/env.txt" env
run_to_file "$SYSTEM_DIR/df.txt" df -h
run_to_file "$SYSTEM_DIR/mount.txt" mount

section "Users and sudo"
run_to_file "$USERS_DIR/whoami.txt" whoami
run_to_file "$USERS_DIR/groups.txt" groups
run_to_file "$USERS_DIR/passwd.txt" cat /etc/passwd
run_to_file "$USERS_DIR/group.txt" cat /etc/group
run_to_file "$USERS_DIR/who.txt" who
run_to_file "$USERS_DIR/w.txt" w
if have sudo; then
  run_to_file "$USERS_DIR/sudo-nopasswd-check.txt" sudo -n -l
else
  echo "sudo not found" > "$USERS_DIR/sudo-nopasswd-check.txt"
fi

section "Network"
if have ip; then
  run_to_file "$NETWORK_DIR/ip-addr.txt" ip addr
  run_to_file "$NETWORK_DIR/ip-route.txt" ip route
else
  run_to_file "$NETWORK_DIR/ifconfig.txt" ifconfig
  run_to_file "$NETWORK_DIR/route.txt" route -n
fi
if have ss; then
  run_to_file "$NETWORK_DIR/listeners.txt" ss -tulpen
else
  run_to_file "$NETWORK_DIR/listeners-netstat.txt" netstat -tulpen
fi

section "Processes and services"
run_to_file "$PROCESSES_DIR/ps-aux.txt" ps aux
if have systemctl; then
  run_to_file "$SERVICES_DIR/systemctl-running.txt" systemctl list-units --type=service --state=running
  run_to_file "$SCHEDULED_DIR/systemd-timers.txt" systemctl list-timers --all
fi
run_to_file "$SERVICES_DIR/service-status-all.txt" service --status-all

section "Scheduled tasks"
run_to_file "$SCHEDULED_DIR/crontab-current-user.txt" crontab -l
run_to_file "$SCHEDULED_DIR/etc-crontab.txt" cat /etc/crontab
run_to_file "$SCHEDULED_DIR/cron-dirs.txt" ls -la /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.monthly /etc/cron.weekly

section "Permissions and writable locations"
run_to_file "$PERMS_DIR/find-writable-world.txt" find / -xdev -type d -perm -0002
run_to_file "$PERMS_DIR/find-writable-user.txt" find / -xdev -type d -writable
run_to_file "$PERMS_DIR/suid-binaries.txt" find / -xdev -type f -perm -4000
run_to_file "$PERMS_DIR/sgid-binaries.txt" find / -xdev -type f -perm -2000

section "Interesting files"
run_to_file "$FILES_DIR/web-roots.txt" ls -la /var/www /srv/www /usr/share/nginx/html /var/www/html
run_to_file "$FILES_DIR/interesting-by-name.txt" find / -xdev -type f \( -iname "*.env" -o -iname "*.conf" -o -iname "*.ini" -o -iname "*.yaml" -o -iname "*.yml" -o -iname "*.json" -o -iname "*backup*" -o -iname "*.bak" -o -iname "id_rsa" -o -iname "id_ed25519" -o -iname "*.kdbx" \)
run_to_file "$FILES_DIR/interesting-grep-secrets.txt" grep -RInE "password|passwd|secret|token|api[_-]?key|PRIVATE KEY" /home /opt /var/www /etc

section "SSH and shell history inventory (metadata only)"
run_to_file "$FILES_DIR/ssh-inventory.txt" find /home /root -maxdepth 4 -type f \( -name "id_rsa" -o -name "id_ed25519" -o -name "authorized_keys" -o -name "known_hosts" \) -exec ls -la {} \;
run_to_file "$FILES_DIR/history-inventory.txt" find /home /root -maxdepth 4 -type f \( -name ".bash_history" -o -name ".zsh_history" -o -name "*history" \) -exec ls -la {} \;

section "Summary"
FILE_COUNT="$(find "$ROOT" -type f | wc -l 2>/dev/null || echo 0)"
append_line "files_collected: $FILE_COUNT"
append_line "important_paths:"
append_line "- $USERS_DIR/sudo-nopasswd-check.txt"
append_line "- $PERMS_DIR/suid-binaries.txt"
append_line "- $FILES_DIR/interesting-grep-secrets.txt"
append_line "- $NETWORK_DIR/listeners.txt"
append_line "- $PROCESSES_DIR/ps-aux.txt"
append_line ""
append_line "generated_files:"
find "$ROOT" -type f | sed "s|$ROOT/|- |" >> "$SUMMARY"

ARCHIVE=""
if have tar; then
  section "Archiving"
  ARCHIVE="${ROOT}.tar.gz"
  tar -czf "$ARCHIVE" -C "$(dirname "$ROOT")" "$(basename "$ROOT")" 2>/dev/null || true
fi

section "Complete"
echo "Loot directory: $ROOT"
if [[ -n "$ARCHIVE" && -f "$ARCHIVE" ]]; then
  echo "Archive: $ARCHIVE"
fi
echo "Summary: $SUMMARY"
