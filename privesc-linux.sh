#!/usr/bin/env bash

set -u

MODE="${MODE:-normal}"          # stealth|normal|aggressive
VERBOSITY="${VERBOSITY:-normal}" # quiet|normal|verbose
INTEGRATE_TOOLS=0
VALIDATE_SAFE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --verbosity) VERBOSITY="$2"; shift 2 ;;
    --integrate-tools) INTEGRATE_TOOLS=1; shift ;;
    --validate-safe) VALIDATE_SAFE=1; shift ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

noise_level() {
  case "$1" in
    stealth) echo 0 ;;
    normal) echo 1 ;;
    aggressive) echo 2 ;;
    *) echo 1 ;;
  esac
}

should_run_noise() {
  local check_noise="$1"
  [[ "$(noise_level "$check_noise")" -le "$(noise_level "$MODE")" ]]
}

log() {
  [[ "$VERBOSITY" == "quiet" ]] && return
  echo "$@"
}

vlog() {
  [[ "$VERBOSITY" == "verbose" ]] && echo "$@"
}

run_cmd() {
  local cmd="$1"
  local out="$2"
  {
    echo "### CMD: $cmd"
    echo "### TS: $(date -Iseconds)"
    echo
    bash -lc "$cmd"
  } >"$out" 2>&1 || true
}

add_finding() {
  # score|severity|confidence|title|check|detail|ref
  echo "$1|$2|$3|$4|$5|$6|$7" >> "$FINDINGS_FILE"
}

GTFOBIN_URL() {
  local b="$1"
  echo "https://gtfobins.github.io/gtfobins/${b}/"
}

HOST="$(hostname 2>/dev/null || echo unknown-host)"
TS="$(date +%Y%m%d-%H%M%S)"
ROOT="${PWD}/privesc/${HOST}-${TS}"
RAW="$ROOT/raw"
SUMMARY_DIR="$ROOT/summary"
mkdir -p "$RAW" "$SUMMARY_DIR"

FINDINGS_FILE="$ROOT/findings.tsv"
: > "$FINDINGS_FILE"

BOX="-"
TARGET="-"
if [[ -f .env ]]; then
  # shellcheck disable=SC1091
  source .env >/dev/null 2>&1 || true
  BOX="${box:-$BOX}"
  TARGET="${target:-$TARGET}"
fi

log "[+] privesc-linux starting"
log "[+] mode=$MODE verbosity=$VERBOSITY integrate_tools=$INTEGRATE_TOOLS validate_safe=$VALIDATE_SAFE"
log "[+] output=$ROOT"

# id|noise|category|cmd
CHECKS=(
  "identity|stealth|users|id && whoami && groups"
  "kernel|stealth|system|uname -a && cat /etc/os-release"
  "sudo|stealth|permissions|sudo -n -l"
  "network|stealth|network|ip addr && ip route && ss -tulpen"
  "processes|stealth|processes|ps aux"
  "services|normal|services|systemctl list-units --type=service --state=running || service --status-all"
  "scheduled|normal|scheduled|crontab -l 2>/dev/null; cat /etc/crontab 2>/dev/null; ls -la /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly 2>/dev/null"
  "mounts|stealth|filesystem|mount && df -h"
  "writable|normal|permissions|find / -xdev -type d -writable 2>/dev/null"
  "suid_sgid|normal|permissions|find / -xdev -type f \( -perm -4000 -o -perm -2000 \) 2>/dev/null"
  "capabilities|normal|permissions|getcap -r / 2>/dev/null"
  "creds_scan|aggressive|credentials|grep -RInE 'password|passwd|secret|token|api[_-]?key|PRIVATE KEY' /home /opt /var/www /etc 2>/dev/null"
  "webroots|normal|filesystem|ls -la /var/www /srv/www /usr/share/nginx/html /var/www/html 2>/dev/null"
)

if [[ "$VALIDATE_SAFE" -eq 1 ]]; then
  CHECKS=(
    "identity|stealth|users|id && whoami && groups"
    "kernel|stealth|system|uname -a && cat /etc/os-release"
    "sudo|stealth|permissions|sudo -n -l"
  )
fi

for entry in "${CHECKS[@]}"; do
  IFS='|' read -r cid noise cat cmd <<< "$entry"
  if ! should_run_noise "$noise"; then
    continue
  fi
  out="$RAW/${cid}.txt"
  vlog "[.] running $cid"
  run_cmd "$cmd" "$out"

done

# Parsing + correlation
if [[ -f "$RAW/identity.txt" ]]; then
  if grep -Eiq '\bdocker\b' "$RAW/identity.txt"; then
    add_finding 18 high high "User in docker group" "identity" "docker group membership observed" ""
  fi
  if grep -Eiq '\blxd\b' "$RAW/identity.txt"; then
    add_finding 18 high high "User in lxd group" "identity" "lxd group membership observed" ""
  fi
fi

if [[ -f "$RAW/sudo.txt" ]]; then
  if grep -Eiq 'NOPASSWD|may run the following commands' "$RAW/sudo.txt"; then
    add_finding 20 high high "Sudo rights discovered" "sudo" "sudo -n -l returned actionable permissions" ""
    for b in vim less awk find nmap tar perl python python3 bash; do
      if grep -Eiq "\b${b}\b" "$RAW/sudo.txt"; then
        add_finding 22 high medium "Potential GTFOBins sudo path: ${b}" "sudo" "sudo-allowed binary appears in output" "$(GTFOBIN_URL "$b")"
      fi
    done
  fi
fi

if [[ -f "$RAW/suid_sgid.txt" ]]; then
  while IFS= read -r line; do
    bn="$(basename "$line")"
    case "$bn" in
      vim|less|awk|find|nmap|tar|perl|python|python3|bash)
        add_finding 13 medium medium "Interesting SUID/SGID binary: $bn" "suid_sgid" "$line" "$(GTFOBIN_URL "$bn")"
        ;;
    esac
  done < "$RAW/suid_sgid.txt"
fi

if [[ -f "$RAW/capabilities.txt" ]]; then
  grep -E 'cap_setuid|cap_setgid|cap_sys_admin' "$RAW/capabilities.txt" | head -n 20 | while IFS= read -r line; do
    add_finding 19 high high "Dangerous file capability" "capabilities" "$line" ""
  done
fi

if [[ -f "$RAW/writable.txt" ]]; then
  grep -E '^/(etc|usr/local|opt)/' "$RAW/writable.txt" | head -n 20 | while IFS= read -r line; do
    add_finding 14 high medium "Sensitive writable directory" "writable" "$line" ""
  done
fi

if [[ -f "$RAW/network.txt" ]] && grep -q 'LISTEN' "$RAW/network.txt"; then
  add_finding 8 medium high "Listening services detected" "network" "local listening ports/services found" ""
fi

if [[ -f "$RAW/scheduled.txt" ]] && grep -Eiq 'root|systemd' "$RAW/scheduled.txt"; then
  add_finding 9 medium medium "Root scheduled context detected" "scheduled" "cron/timer output includes root/system context" ""
fi

if [[ -f "$RAW/creds_scan.txt" ]] && [[ "$(wc -l < "$RAW/creds_scan.txt" 2>/dev/null || echo 0)" -gt 0 ]]; then
  add_finding 16 high low "Credential-like strings found" "creds_scan" "potential secrets matched by pattern search" ""
fi

# Integration points (optional)
if [[ "$INTEGRATE_TOOLS" -eq 1 ]]; then
  TOOL_DIR="$ROOT/tools"
  mkdir -p "$TOOL_DIR"
  for t in ./linpeas.sh ./LinEnum.sh ./linux-exploit-suggester.sh; do
    if [[ -x "$t" || -f "$t" ]]; then
      out="$TOOL_DIR/$(basename "$t").txt"
      bash -lc "$t" > "$out" 2>&1 || true
      add_finding 7 low medium "Tool integration output captured" "tool-integration" "ran $t and captured output" ""
    fi
  done
fi

SUMMARY_TXT="$SUMMARY_DIR/summary.txt"
SUMMARY_MD="$SUMMARY_DIR/summary.md"

{
  echo "privesc-linux summary"
  echo "timestamp: $(date -Iseconds)"
  echo "host: $HOST"
  echo "box: $BOX"
  echo "target: $TARGET"
  echo "mode: $MODE"
  echo "verbosity: $VERBOSITY"
  echo "integrate_tools: $INTEGRATE_TOOLS"
  echo "validate_safe: $VALIDATE_SAFE"
  echo ""
  echo "top findings (score desc):"
  if [[ -s "$FINDINGS_FILE" ]]; then
    sort -t'|' -k1,1nr "$FINDINGS_FILE" | head -n 25 | while IFS='|' read -r score sev conf title check detail ref; do
      echo "- [$score] $sev/$conf $title ($check)"
      echo "  detail: $detail"
      [[ -n "$ref" ]] && echo "  ref: $ref"
    done
  else
    echo "- no prioritized findings"
  fi
  echo ""
  echo "generated files:"
  find "$ROOT" -type f | sed "s|$ROOT/|- |"
} > "$SUMMARY_TXT"

{
  echo "# Linux PrivEsc Triage Summary"
  echo
  echo "- **timestamp**: \`$(date -Iseconds)\`"
  echo "- **host**: \`$HOST\`"
  echo "- **box**: \`$BOX\`"
  echo "- **target**: \`$TARGET\`"
  echo "- **mode**: \`$MODE\`"
  echo "- **integrate_tools**: \`$INTEGRATE_TOOLS\`"
  echo "- **validate_safe**: \`$VALIDATE_SAFE\`"
  echo
  echo "## Top Findings"
  echo
  if [[ -s "$FINDINGS_FILE" ]]; then
    sort -t'|' -k1,1nr "$FINDINGS_FILE" | head -n 40 | while IFS='|' read -r score sev conf title check detail ref; do
      echo "### [$score] $title"
      echo "- Severity: \`$sev\`"
      echo "- Confidence: \`$conf\`"
      echo "- Check: \`$check\`"
      echo "- Detail: \`$detail\`"
      [[ -n "$ref" ]] && echo "- Ref: $ref"
      echo
    done
  else
    echo "No prioritized findings."
  fi
} > "$SUMMARY_MD"

if command -v tar >/dev/null 2>&1; then
  tar -czf "${ROOT}.tar.gz" -C "$(dirname "$ROOT")" "$(basename "$ROOT")" 2>/dev/null || true
fi

log "[+] complete"
log "[+] output dir: $ROOT"
[[ -f "${ROOT}.tar.gz" ]] && log "[+] archive: ${ROOT}.tar.gz"
log "[+] summary: $SUMMARY_TXT"
