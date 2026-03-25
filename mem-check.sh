#!/bin/bash
# mem-check.sh — macOS Memory Health Check & Auto-Cleanup
# Usage: ./mem-check.sh [--fix] [--quiet]
#
# --fix    Automatically kill/restart bloated apps
# --quiet  Only output warnings (for cron/launchd use)

set -uo pipefail

# ── Config ────────────────────────────────────────────────────────────
SWAP_WARN_GB=10                # Warn when swap exceeds this
SWAP_CRIT_GB=30                # Critical when swap exceeds this
APP_WARN_MB=1500               # Flag apps using more than this
PRESSURE_WARN_PCT=80           # Warn when memory used % exceeds this
LOG_DIR="$HOME/.local/logs/mem-check"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).log"

# Apps safe to auto-restart (only used with --fix)
RESTARTABLE_APPS=("Finder" "Ghostty" "Terminal" "iTerm2")

# Apps safe to notify about but not kill
NOTIFY_ONLY_APPS=("Google Chrome" "Slack" "Spotify" "Notion" "Discord")

# ── Parse args ────────────────────────────────────────────────────────
AUTO_FIX=false
QUIET=false
for arg in "$@"; do
    case "$arg" in
        --fix)   AUTO_FIX=true ;;
        --quiet) QUIET=true ;;
    esac
done

# ── Helpers ───────────────────────────────────────────────────────────
mkdir -p "$LOG_DIR"

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log() {
    local msg="[$(date '+%H:%M:%S')] $1"
    echo "$msg" >> "$LOG_FILE"
    if [[ "$QUIET" == false ]]; then
        echo -e "$1"
    fi
}

notify() {
    local title="$1"
    local message="$2"
    osascript -e "display notification \"$message\" with title \"$title\"" 2>/dev/null || true
}

divider() {
    log "${CYAN}──────────────────────────────────────────────${NC}"
}

# ── System info ───────────────────────────────────────────────────────
TOTAL_RAM_BYTES=$(sysctl -n hw.memsize)
TOTAL_RAM_GB=$(echo "$TOTAL_RAM_BYTES" | awk '{printf "%.0f", $1/1024/1024/1024}')
PAGE_SIZE=$(vm_stat | head -1 | grep -oE '[0-9]+')

log ""
log "${BOLD}Memory Health Check — $(date '+%Y-%m-%d %H:%M')${NC}"
log "${BOLD}System: ${TOTAL_RAM_GB} GB RAM${NC}"
divider

# ── 1. Memory pressure ───────────────────────────────────────────────
PRESSURE_OUTPUT=$(memory_pressure 2>/dev/null)
FREE_PCT=$(echo "$PRESSURE_OUTPUT" | grep "free percentage" | grep -oE '[0-9]+')
USED_PCT=$((100 - FREE_PCT))

if [[ $USED_PCT -ge $PRESSURE_WARN_PCT ]]; then
    log "${RED}MEMORY PRESSURE: ${USED_PCT}% used (${FREE_PCT}% free)${NC}"
    PRESSURE_STATUS="warning"
else
    log "${GREEN}MEMORY PRESSURE: ${USED_PCT}% used (${FREE_PCT}% free)${NC}"
    PRESSURE_STATUS="ok"
fi

# ── 2. Swap usage ─────────────────────────────────────────────────────
SWAP_LINE=$(sysctl vm.swapusage)
SWAP_USED_MB=$(echo "$SWAP_LINE" | grep -oE 'used = [0-9.]+' | grep -oE '[0-9.]+')
SWAP_USED_GB=$(echo "$SWAP_USED_MB" | awk '{printf "%.1f", $1/1024}')
SWAP_TOTAL_MB=$(echo "$SWAP_LINE" | grep -oE 'total = [0-9.]+' | grep -oE '[0-9.]+')

SWAP_USED_GB_INT=$(echo "$SWAP_USED_GB" | awk '{printf "%.0f", $1}')

if [[ $SWAP_USED_GB_INT -ge $SWAP_CRIT_GB ]]; then
    log "${RED}SWAP: ${SWAP_USED_GB} GB used — CRITICAL (thrashing likely)${NC}"
    SWAP_STATUS="critical"
elif [[ $SWAP_USED_GB_INT -ge $SWAP_WARN_GB ]]; then
    log "${YELLOW}SWAP: ${SWAP_USED_GB} GB used — elevated${NC}"
    SWAP_STATUS="warning"
else
    log "${GREEN}SWAP: ${SWAP_USED_GB} GB used${NC}"
    SWAP_STATUS="ok"
fi

# ── 3. Compressed memory ─────────────────────────────────────────────
COMPRESSOR_PAGES=$(echo "$PRESSURE_OUTPUT" | grep "Pages used by compressor" | grep -oE '[0-9]+')
COMPRESSED_GB=$(echo "$COMPRESSOR_PAGES $PAGE_SIZE" | awk '{printf "%.1f", $1*$2/1024/1024/1024}')
log "COMPRESSED MEMORY: ${COMPRESSED_GB} GB"

# ── 4. Top memory consumers (aggregated by app family) ─────────────────
divider
log "${BOLD}Top apps by total memory:${NC}"
log ""

# Aggregate processes by app family using name and args (for project attribution).
# Uses args= to identify which project spawned node/runtime processes.
ps -Ao rss=,pid=,ppid=,args= | awk '
BEGIN {
    fam["Cursor"]="Cursor"; fam["Google Chrome"]="Chrome"; fam["Chrome"]="Chrome"
    fam["Notion"]="Notion"; fam["Slack"]="Slack"; fam["Spotify"]="Spotify"
    fam["Claude Helper"]="Claude App"; fam["Claude"]="Claude App"
    fam["Discord"]="Discord"; fam["Postman"]="Postman"
    fam["1Password"]="1Password"; fam["Figma"]="Figma"; fam["Tower"]="Tower"

    split("node,tsserver,SourceKitService,sourcekit-lsp,gopls,rust-analyzer,clangd,pylsp,next-router-worker,doppler", _rt, ",")
    for (_i in _rt) is_rt[_rt[_i]] = 1
}
{
    _rss = $1; _pid = $2; _ppid = $3
    # Everything after rss,pid,ppid is the full args string
    _args = ""
    for (_j = 4; _j <= NF; _j++) _args = (_args == "" ? $_j : _args " " $_j)

    # Extract app name — look for /Applications/*.app or ~/Apps/*.app bundle, else basename
    _name = ""
    if (match(_args, /\/Applications\/[^\/]+\.app/) || match(_args, /\/Apps\/[^\/]+\.app/)) {
        _tmp_app = substr(_args, RSTART + 1, RLENGTH - 1)
        # Get just the app name (last component, minus .app)
        _na = split(_tmp_app, _ap, "/")
        _name = _ap[_na]
        sub(/\.app$/, "", _name)
    } else {
        _nparts = split($4, _pathparts, "/")
        _name = _pathparts[_nparts]
    }

    # Skip ps itself (our own monitoring command)
    if (_name == "ps") next

    rss_of[_pid] = _rss
    name_of[_pid] = _name
    ppid_of[_pid] = _ppid
    args_of[_pid] = _args
    pid_list[++_npids] = _pid
}
END {
    for (_i = 1; _i <= _npids; _i++) {
        _pid = pid_list[_i]; _name = name_of[_pid]; _ppid = ppid_of[_pid]
        _mb = rss_of[_pid] / 1024
        if (_mb < 5) continue

        _family = ""

        # Match against known GUI app families
        for (_app in fam) {
            if (index(_name, _app) == 1) { _family = fam[_app]; break }
        }

        # Runtime processes: attribute by project dir in args
        if (_family == "") {
            _base = _name; sub(/\[.*/, "", _base); gsub(/ +$/, "", _base)
            if (is_rt[_base] || index(_name, "node") == 1) {
                _pa = args_of[_pid]
                if (match(_pa, /\/Users\/[^\/]+\/[Aa]pps\/[^\/]+/)) {
                    _tmp = substr(_pa, RSTART, RLENGTH)
                    _nt = split(_tmp, _tp, "/")
                    _family = _tp[_nt]
                } else {
                    # Walk parent chain — check parent args for project
                    _p = _ppid
                    for (_d = 0; _d < 4 && _p > 1; _d++) {
                        _pn = name_of[_p]
                        for (_app in fam) {
                            if (index(_pn, _app) == 1) { _family = fam[_app]; break }
                        }
                        if (_family != "") break
                        _pargs = args_of[_p]
                        if (match(_pargs, /\/Users\/[^\/]+\/[Aa]pps\/[^\/]+/)) {
                            _tmp2 = substr(_pargs, RSTART, RLENGTH)
                            _nt2 = split(_tmp2, _tp2, "/")
                            _family = _tp2[_nt2]; break
                        }
                        _p = ppid_of[_p]
                    }
                    if (_family == "") _family = "node (other)"
                }
            }
        }

        # CLI claude (lowercase binary, not the .app)
        if (_family == "" && _name == "claude") _family = "Claude CLI"

        # MCP servers
        if (_family == "" && index(_name, "mcp") == 1) _family = "MCP servers"

        if (_family == "") _family = _name

        totmb[_family] += _mb; cnt[_family]++
    }
    for (_fam in totmb) if (totmb[_fam] > 50) printf "%d\t%d\t%s\n", totmb[_fam], cnt[_fam], _fam
}' | sort -rn | head -15 | while IFS=$'\t' read -r mem_mb count app_name; do
    if [[ $count -gt 1 ]]; then
        label="${app_name} (${count} procs)"
    else
        label="${app_name}"
    fi
    if [[ $mem_mb -ge $APP_WARN_MB ]]; then
        log "  ${RED}$(printf '%6d' "$mem_mb") MB${NC}  ${label}"
    elif [[ $mem_mb -ge 500 ]]; then
        log "  ${YELLOW}$(printf '%6d' "$mem_mb") MB${NC}  ${label}"
    else
        log "  $(printf '%6d' "$mem_mb") MB  ${label}"
    fi
done

# ── 5. Bloated GUI apps ──────────────────────────────────────────────
divider
log "${BOLD}GUI apps over ${APP_WARN_MB} MB:${NC}"
log ""

BLOATED_FOUND=false

# Get GUI app memory from ps, match against running apps
# Note: process substitution (< <(...)) avoids subshell so BLOATED_FOUND propagates
while IFS=',' read -ra fields; do
    # Parse paired names and pids
    half=$(( ${#fields[@]} / 2 ))
    for ((i=0; i<half; i++)); do
        app_name=$(echo "${fields[$i]}" | xargs)
        app_pid=$(echo "${fields[$((i + half))]}" | xargs)

        if [[ -n "$app_pid" ]] && [[ "$app_pid" =~ ^[0-9]+$ ]]; then
            rss=$(ps -o rss= -p "$app_pid" 2>/dev/null || echo "0")
            mem_mb=$((rss / 1024))

            if [[ $mem_mb -ge $APP_WARN_MB ]]; then
                BLOATED_FOUND=true
                log "  ${RED}${app_name}: ${mem_mb} MB${NC}"

                if [[ "$AUTO_FIX" == true ]]; then
                    # Check if it's restartable
                    for safe_app in "${RESTARTABLE_APPS[@]}"; do
                        if [[ "$app_name" == "$safe_app" ]]; then
                            log "    → Restarting ${app_name}..."
                            killall "$app_name" 2>/dev/null || true
                            sleep 1
                            open -a "$app_name" 2>/dev/null || true
                            log "    ${GREEN}✓ Restarted${NC}"
                        fi
                    done

                    for warn_app in "${NOTIFY_ONLY_APPS[@]}"; do
                        if [[ "$app_name" == "$warn_app" ]]; then
                            notify "Memory Warning" "${app_name} is using ${mem_mb} MB. Consider closing some tabs/windows."
                            log "    → Sent notification"
                        fi
                    done
                fi
            fi
        fi
    done
done < <(osascript -e 'tell application "System Events" to get {name, unix id} of every process whose background only is false' 2>/dev/null | \
    paste -d',' - - | tr -d '{}')

if [[ "$BLOATED_FOUND" == false ]]; then
    log "  ${GREEN}None — all apps within limits${NC}"
fi

# ── 6. Swap file count & size on disk ─────────────────────────────────
divider
SWAP_FILES=$(ls /private/var/vm/swapfile* 2>/dev/null | wc -l | xargs)
SWAP_DISK=$(du -sh /private/var/vm/ 2>/dev/null | awk '{print $1}')
log "SWAP FILES: ${SWAP_FILES} files using ${SWAP_DISK} on disk"

# ── 7. Recommendations ───────────────────────────────────────────────
divider
log "${BOLD}Recommendations:${NC}"
log ""

ISSUES=0

if [[ "$SWAP_STATUS" == "critical" ]]; then
    log "  ${RED}1. URGENT: Swap is at ${SWAP_USED_GB} GB. Your system is thrashing.${NC}"
    log "     Close heavy apps or restart to reclaim memory."
    ISSUES=$((ISSUES + 1))
elif [[ "$SWAP_STATUS" == "warning" ]]; then
    log "  ${YELLOW}1. Swap is elevated at ${SWAP_USED_GB} GB. Monitor and close unused apps.${NC}"
    ISSUES=$((ISSUES + 1))
fi

if [[ "$PRESSURE_STATUS" == "warning" ]]; then
    log "  ${YELLOW}2. Memory pressure is high (${USED_PCT}%). Free up memory soon.${NC}"
    ISSUES=$((ISSUES + 1))
fi

COMPRESSED_GB_INT=$(echo "$COMPRESSED_GB" | awk '{printf "%.0f", $1}')
if [[ $COMPRESSED_GB_INT -ge 15 ]]; then
    log "  ${YELLOW}3. ${COMPRESSED_GB} GB of compressed memory — system is working hard.${NC}"
    ISSUES=$((ISSUES + 1))
fi

if [[ $ISSUES -eq 0 ]]; then
    log "  ${GREEN}System looks healthy. No action needed.${NC}"
fi

log ""
log "Log saved to: ${LOG_FILE}"

# ── 8. Exit code for automation ───────────────────────────────────────
if [[ "$SWAP_STATUS" == "critical" ]] || [[ "$PRESSURE_STATUS" == "warning" ]]; then
    exit 2  # Critical
elif [[ "$SWAP_STATUS" == "warning" ]]; then
    exit 1  # Warning
else
    exit 0  # Healthy
fi
