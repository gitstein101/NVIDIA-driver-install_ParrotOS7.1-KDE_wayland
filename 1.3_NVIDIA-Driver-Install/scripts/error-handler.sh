#!/bin/bash

# error-handler.sh — Shared failure logging library for NVIDIA toolkit v1.3
# Source this file from nvidia-install.sh and nvidia-remove.sh
# Provides: step tracking, ERR/EXIT trap handlers, change recording, failure log generation
#
# NOTE: The calling script should use `set -euo pipefail`. This handler does NOT
# set -E (errtrace) because it would cause ERR traps to fire inside `|| true`
# guards. Instead, we capture what we can from the ERR trap and fall back to
# step-level context when line-level context is unavailable.

# Guard against double-sourcing
if [ "${_ERROR_HANDLER_LOADED:-}" = "true" ]; then
    return 0
fi
_ERROR_HANDLER_LOADED=true

# --- State variables ---
_FAILURE_LOG_DIR=""
_FAILURE_LOG_PREFIX=""
_TOTAL_STEPS=0
_CURRENT_STEP_NUM=0
_CURRENT_STEP_DESC=""
_STEPS_COMPLETED=()    # "N: description" entries
_STEPS_STATUS=()       # parallel array: "OK" or "FAILED"
_CHANGES_MADE=()       # human-readable change descriptions
_CALLING_SCRIPT=""
_TRAPS_ACTIVE=false

# --- Initialization ---

# init_failure_logging "install" 13
#   Sets up the log directory, prefix, and total step count.
#   Must be called before any other error-handler function.
init_failure_logging() {
    local script_type="$1"
    local total_steps="$2"

    _FAILURE_LOG_PREFIX="nvidia-failure-${script_type}"
    _TOTAL_STEPS="$total_steps"
    _CALLING_SCRIPT="nvidia-${script_type}.sh"

    # Determine writable log directory (same dir as script, fallback to /tmp)
    local script_dir
    script_dir="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)}"

    if [ -w "$script_dir" ]; then
        _FAILURE_LOG_DIR="$script_dir"
    else
        _FAILURE_LOG_DIR="/tmp"
    fi
}

# activate_traps
#   Installs the ERR, EXIT, and INT trap handlers.
#   Call after init_failure_logging.
activate_traps() {
    trap '_on_error ${LINENO} "${FUNCNAME[0]:-main}" "$BASH_COMMAND" $?' ERR
    trap '_on_exit $?' EXIT
    trap 'exit 130' INT
    _TRAPS_ACTIVE=true
}

# --- Step tracking ---

# set_step N "description"
#   Announces and tracks the current step.
set_step() {
    local step_num="$1"
    local step_desc="$2"

    _CURRENT_STEP_NUM="$step_num"
    _CURRENT_STEP_DESC="$step_desc"

    echo -e "\033[0;34m[Step ${step_num}/${_TOTAL_STEPS}]\033[0m ${step_desc}"
}

# step_done
#   Records the current step as completed.
step_done() {
    _STEPS_COMPLETED+=("${_CURRENT_STEP_NUM}: ${_CURRENT_STEP_DESC}")
    _STEPS_STATUS+=("OK")
}

# record_change "description of system modification"
#   Tracks a change made to the system for rollback awareness.
record_change() {
    _CHANGES_MADE+=("$1")
}

# --- Internal trap handlers ---

# _on_error LINENO FUNCNAME COMMAND EXIT_CODE
#   ERR trap handler — captures failure context but does NOT write the log.
#   The EXIT trap (_on_exit) handles log writing, since ERR fires before EXIT.
_on_error() {
    # Save error context for the EXIT handler
    _ERR_LINE="$1"
    _ERR_FUNC="$2"
    _ERR_CMD="$3"
    _ERR_CODE="$4"
    _ERR_SOURCE="${BASH_SOURCE[1]:-unknown}"
}

# _on_exit EXIT_CODE
#   EXIT trap handler — writes failure log if exit was abnormal.
_on_exit() {
    local exit_code="$1"

    # Disable traps to prevent recursion
    trap - ERR EXIT INT

    # Clean exit (0) or user cancellation (130) — no failure log
    if [ "$exit_code" -eq 0 ] || [ "$exit_code" -eq 130 ]; then
        return 0
    fi

    # Pre-condition exit (before any step started) — not an installation failure
    if [ "$_CURRENT_STEP_NUM" -eq 0 ]; then
        return 0
    fi

    # Use ERR-captured context if available, otherwise derive from step context
    local failed_line="${_ERR_LINE:-unknown}"
    local failed_func="${_ERR_FUNC:-unknown}"
    local failed_cmd="${_ERR_CMD:-unknown}"
    local failed_source="${_ERR_SOURCE:-unknown}"

    # If ERR trap didn't fire (e.g., || true suppressed it), enrich with step info
    if [ "$failed_cmd" = "unknown" ] && [ -n "$_CURRENT_STEP_DESC" ]; then
        failed_cmd="(ERR trap suppressed — failed during step ${_CURRENT_STEP_NUM}: ${_CURRENT_STEP_DESC})"
        failed_func="${_CALLING_SCRIPT}:step${_CURRENT_STEP_NUM}"
    fi

    _write_failure_log "$exit_code" "$failed_line" "$failed_func" "$failed_cmd" "$failed_source"
    _print_terminal_summary "$exit_code"
}

# --- Failure log generation ---

_write_failure_log() {
    local exit_code="$1"
    local failed_line="$2"
    local failed_func="$3"
    local failed_cmd="$4"
    local failed_source="${5:-unknown}"

    local timestamp
    timestamp=$(date -Iseconds)
    local file_timestamp
    file_timestamp=$(date +%Y%m%d-%H%M%S)
    local log_file="${_FAILURE_LOG_DIR}/${_FAILURE_LOG_PREFIX}-${file_timestamp}.log"

    local distro_val="${DISTRO:-unknown}"
    local kernel_val
    kernel_val=$(uname -r 2>/dev/null || echo "unknown")
    local hostname_val
    hostname_val=$(hostname 2>/dev/null || echo "unknown")

    # --- Machine-parseable header ---
    {
        echo "NVIDIA_FAILURE_LOG_VERSION=2"
        echo "TIMESTAMP=${timestamp}"
        echo "SCRIPT=${_CALLING_SCRIPT}"
        echo "EXIT_CODE=${exit_code}"
        echo "FAILED_LINE=${failed_line}"
        echo "FAILED_FUNCTION=${failed_func}"
        echo "FAILED_COMMAND=${failed_cmd}"
        echo "FAILED_SOURCE=${failed_source}"
        echo "FAILED_STEP_NUM=${_CURRENT_STEP_NUM}"
        echo "FAILED_STEP=${_CURRENT_STEP_DESC}"
        echo "TOTAL_STEPS=${_TOTAL_STEPS}"
        echo "DISTRO=${distro_val}"
        echo "KERNEL=${kernel_val}"
        echo "HOSTNAME=${hostname_val}"
        echo "---"
        echo ""

        # --- Steps completed ---
        echo "=== STEPS COMPLETED ==="
        local i
        for i in "${!_STEPS_COMPLETED[@]}"; do
            echo "  [${_STEPS_STATUS[$i]}] ${_STEPS_COMPLETED[$i]}"
        done
        # Mark current step as failed if it wasn't completed
        if [ -n "$_CURRENT_STEP_DESC" ]; then
            local already_done=false
            for entry in "${_STEPS_COMPLETED[@]}"; do
                if [[ "$entry" == "${_CURRENT_STEP_NUM}:"* ]]; then
                    already_done=true
                    break
                fi
            done
            if [ "$already_done" = false ]; then
                echo "  [FAILED] ${_CURRENT_STEP_NUM}: ${_CURRENT_STEP_DESC}"
            fi
        fi
        echo ""

        # --- Changes made ---
        echo "=== CHANGES MADE (may need rollback) ==="
        if [ ${#_CHANGES_MADE[@]} -eq 0 ]; then
            echo "  (none)"
        else
            for change in "${_CHANGES_MADE[@]}"; do
                echo "  - ${change}"
            done
        fi
        echo ""

        # --- System state snapshot ---
        echo "=== SYSTEM STATE AT FAILURE ==="
        echo ""

        echo "--- Loaded NVIDIA/nouveau modules ---"
        lsmod 2>/dev/null | grep -E "nvidia|nouveau" || echo "  (none)"
        echo ""

        echo "--- Installed NVIDIA packages ---"
        if command -v dpkg &> /dev/null; then
            dpkg -l 2>/dev/null | grep -i nvidia | grep ^ii || echo "  (none)"
        elif command -v pacman &> /dev/null; then
            pacman -Q 2>/dev/null | grep -i nvidia || echo "  (none)"
        fi
        echo ""

        echo "--- Broken/half-installed packages ---"
        if command -v dpkg &> /dev/null; then
            dpkg -l 2>/dev/null | awk '/^.[HUFWt]/' || echo "  (none)"
        fi
        echo ""

        echo "--- Display manager status ---"
        systemctl is-active display-manager 2>/dev/null || echo "  not running"
        echo ""

        echo "--- Key config files ---"
        for f in /etc/modprobe.d/blacklist-nouveau.conf /etc/modprobe.d/blacklist-intel.conf \
                 /etc/X11/xorg.conf /etc/sddm.conf.d/10-wayland.conf \
                 /etc/lightdm/lightdm.conf.d/50-nvidia.conf /etc/environment; do
            if [ -f "$f" ]; then
                echo "  [EXISTS] $f"
            else
                echo "  [ABSENT] $f"
            fi
        done
        echo ""

        echo "--- Boot parameters ---"
        cat /proc/cmdline 2>/dev/null || echo "  (unavailable)"
        echo ""

        echo "--- Recent dmesg (NVIDIA/nouveau, last 20 lines) ---"
        dmesg 2>/dev/null | grep -i "nvidia\|nouveau" | tail -20 || echo "  (unavailable)"

    } > "$log_file" 2>/dev/null

    echo ""
    echo -e "\033[0;31m=== FAILURE LOG WRITTEN ===\033[0m"
    echo "  ${log_file}"
}

_print_terminal_summary() {
    local exit_code="$1"

    echo ""
    echo -e "\033[0;31m========================================\033[0m"
    echo -e "\033[0;31m  ${_CALLING_SCRIPT} FAILED\033[0m"
    echo -e "\033[0;31m========================================\033[0m"
    echo ""
    echo "  Failed at step ${_CURRENT_STEP_NUM}/${_TOTAL_STEPS}: ${_CURRENT_STEP_DESC}"
    echo "  Exit code: ${exit_code}"
    echo ""

    if [ ${#_CHANGES_MADE[@]} -gt 0 ]; then
        echo -e "\033[1;33mChanges already applied to your system:\033[0m"
        for change in "${_CHANGES_MADE[@]}"; do
            echo "  - ${change}"
        done
        echo ""
        echo "To undo these changes, run: sudo ./nvidia-remove.sh"
    else
        echo "No system changes were made before the failure."
    fi

    echo ""
    echo "For diagnostics, run: sudo ./nvidia-diagnose.sh"
    echo ""
}
