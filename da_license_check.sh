#!/usr/bin/env bash
# checks DA license status
# by TechSupp sh.rahimpour
LOG_DIR="/var/log/IO_LOG"
LOG_FILE="${LOG_DIR}/da_license_check.log"
LICENSE_KEY="/usr/local/directadmin/conf/license.key"
DA_LICENSE_HOST="license.ir.cdn.mycache.org"
DA_LOG="/var/log/directadmin/access.log"

LICENSE_MISSING=false
SHOULD_FIX=false

# ─────────────────────────────────────────────
# Logging
# ─────────────────────────────────────────────

setup_log() {
    mkdir -p "$LOG_DIR"
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# ─────────────────────────────────────────────
# Checks
# ─────────────────────────────────────────────

check_license_file() {
    if [[ ! -f "$LICENSE_KEY" ]]; then
        log "ALERT: license.key is MISSING at ${LICENSE_KEY}"
        LICENSE_MISSING=true
    else
        log "OK: license.key exists"
        LICENSE_MISSING=false
    fi
}

check_da_service() {
    DA_STATUS=$(systemctl is-active directadmin 2>/dev/null)
    log "DA service status: ${DA_STATUS}"
}

check_da_error_log() {
    if [[ ! -f "$DA_LOG" ]]; then
        log "WARNING: DA error log not found at ${DA_LOG}"
        return
    fi

    LICENSE_ERRORS=$(grep -i "license" "$DA_LOG" | tail -10)
    if [[ -n "$LICENSE_ERRORS" ]]; then
        log "Recent license-related entries in DA error log:"
        echo "$LICENSE_ERRORS" | while IFS= read -r line; do
            log "  >> $line"
        done
    else
        log "No license-related entries found in DA error log"
    fi
}

check_network_ping() {
    if ping -c 3 -W 3 "$DA_LICENSE_HOST" &>/dev/null; then
        log "NETWORK: ${DA_LICENSE_HOST} is reachable"
    else
        log "NETWORK: ${DA_LICENSE_HOST} is NOT reachable (possible cause of license loss)"
    fi
}

check_dns() {
    DNS_RESULT=$(dig +short "$DA_LICENSE_HOST" 2>/dev/null | paste -sd' ' -)
    if [[ -n "$DNS_RESULT" ]]; then
        log "DNS: ${DA_LICENSE_HOST} resolves to: ${DNS_RESULT}"
    else
        log "DNS: FAILED to resolve ${DA_LICENSE_HOST}"
    fi
}

check_http() {
    HTTP_CODE=$(curl -o /dev/null -s -w "%{http_code}" --max-time 5 "https://${DA_LICENSE_HOST}" 2>/dev/null)
    log "HTTP: License server response code: ${HTTP_CODE}"
}

# ─────────────────────────────────────────────
# Fix
# ─────────────────────────────────────────────

decide_fix() {
    if [[ "$LICENSE_MISSING" == true ]]; then
        log "TRIGGER: license.key missing — will run fix"
        SHOULD_FIX=true
    fi

    if [[ "$DA_STATUS" != "active" ]]; then
        log "TRIGGER: directadmin not active (status: ${DA_STATUS}) — will run fix"
        SHOULD_FIX=true
    fi
}

run_fix() {
    log "ACTION: Running Activation command..."
    UPDATE_OUTPUT=$(update_diradm 2>&1 | tail -n 5)
    UPDATE_EXIT=$?
    log "update_diradm exit code: ${UPDATE_EXIT}"
    echo "$UPDATE_OUTPUT" | while IFS= read -r line; do
        log "  [update] $line"
    done

    log "ACTION: Checking directadmin status after fix..."
    POST_STATUS=$(systemctl status directadmin 2>&1 | head -20)
    echo "$POST_STATUS" | while IFS= read -r line; do
        log "  [post-fix] $line"
    done
}

# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────

main() {
    setup_log
    log "--- DA license check started ---"

    check_license_file
    check_da_service
    check_da_error_log
    check_network_ping
    check_dns
#    check_http

    decide_fix

    if [[ "$SHOULD_FIX" == true ]]; then
        run_fix
    else
        log "INFO: No fix needed. DA is running and license.key exists."
    fi

    log "--- DA license check finished ---"
    echo "" >> "$LOG_FILE"
}

# run main function
main
