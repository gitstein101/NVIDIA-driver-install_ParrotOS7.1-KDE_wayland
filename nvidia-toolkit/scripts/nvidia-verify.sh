#!/bin/bash

# NVIDIA Post-Reboot Verification Script v1.3
# Run after install + reboot to confirm everything is working
# Does NOT require root — all checks are read-only

set -uo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0
WARN=0
FAIL=0

check_pass() {
    echo -e "  ${GREEN}[PASS]${NC} $1"
    PASS=$((PASS + 1))
}

check_warn() {
    echo -e "  ${YELLOW}[WARN]${NC} $1"
    WARN=$((WARN + 1))
}

check_fail() {
    echo -e "  ${RED}[FAIL]${NC} $1"
    FAIL=$((FAIL + 1))
}

check_fix() {
    echo -e "         ${BLUE}Fix:${NC} $1"
}

echo -e "${BLUE}==================================${NC}"
echo -e "${BLUE}  NVIDIA Post-Reboot Verify v1.3${NC}"
echo -e "${BLUE}==================================${NC}"
echo ""

# --- 1. Kernel modules ---
echo -e "${BOLD}1. Kernel Modules${NC}"

for mod in nvidia nvidia_drm nvidia_modeset; do
    if lsmod | grep -q "^${mod} "; then
        check_pass "$mod loaded"
    else
        check_fail "$mod NOT loaded"
        check_fix "modprobe $mod  (or check dmesg for load errors)"
    fi
done

if lsmod | grep -q "^nouveau "; then
    check_fail "nouveau is loaded (conflicts with NVIDIA)"
    check_fix "Blacklist nouveau: echo 'blacklist nouveau' > /etc/modprobe.d/blacklist-nouveau.conf && update-initramfs -u && reboot"
else
    check_pass "nouveau not loaded"
fi

# --- 2. nvidia-smi ---
echo ""
echo -e "${BOLD}2. nvidia-smi${NC}"

if command -v nvidia-smi &>/dev/null; then
    if nvidia-smi &>/dev/null; then
        DRIVER_VER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null || echo "unknown")
        GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || echo "unknown")
        check_pass "nvidia-smi works — driver $DRIVER_VER, GPU: $GPU_NAME"
    else
        check_fail "nvidia-smi found but failed to run"
        check_fix "Check dmesg | grep -i nvidia for kernel errors"
    fi
else
    check_fail "nvidia-smi not found"
    check_fix "Install nvidia-utils or nvidia-driver package"
fi

# --- 3. Boot parameters ---
echo ""
echo -e "${BOLD}3. Boot Parameters${NC}"

if grep -q "nvidia-drm.modeset=1" /proc/cmdline; then
    check_pass "nvidia-drm.modeset=1 active"
else
    check_fail "nvidia-drm.modeset=1 NOT in boot params"
    check_fix "Add nvidia-drm.modeset=1 to GRUB_CMDLINE_LINUX_DEFAULT in /etc/default/grub, then update-grub && reboot"
fi

# Check fbdev on kernel 6.x+
KERN_MAJOR=$(uname -r | cut -d. -f1)
if [ "${KERN_MAJOR:-0}" -ge 6 ]; then
    if grep -q "nvidia-drm.fbdev=1" /proc/cmdline; then
        check_pass "nvidia-drm.fbdev=1 active (kernel 6.x+)"
    elif [ -f /sys/module/nvidia_drm/parameters/fbdev ] && [ "$(cat /sys/module/nvidia_drm/parameters/fbdev 2>/dev/null)" = "Y" ]; then
        check_pass "nvidia-drm.fbdev=1 active via module param"
    else
        check_warn "nvidia-drm.fbdev=1 not set (recommended on kernel 6.x+ for framebuffer console)"
        check_fix "Add nvidia-drm.fbdev=1 to GRUB_CMDLINE_LINUX_DEFAULT"
    fi
fi

# --- 4. Display manager ---
echo ""
echo -e "${BOLD}4. Display Manager${NC}"

if systemctl is-active --quiet display-manager 2>/dev/null; then
    DM_UNIT=$(systemctl show -p Id display-manager.service 2>/dev/null | cut -d= -f2)
    check_pass "Display manager running ($DM_UNIT)"
else
    check_fail "Display manager NOT running"
    check_fix "systemctl start display-manager (check journalctl -u display-manager for errors)"
fi

# --- 5. Session type ---
echo ""
echo -e "${BOLD}5. Display Session${NC}"

SESSION="${XDG_SESSION_TYPE:-unknown}"
if [ "$SESSION" = "wayland" ]; then
    check_pass "Wayland session active"
elif [ "$SESSION" = "x11" ]; then
    check_pass "X11 session active"
elif [ -n "${WAYLAND_DISPLAY:-}" ]; then
    check_pass "Wayland session detected (via WAYLAND_DISPLAY=$WAYLAND_DISPLAY)"
    SESSION="wayland"
elif [ -n "${DISPLAY:-}" ]; then
    check_pass "X11 session detected (via DISPLAY=$DISPLAY)"
    SESSION="x11"
else
    check_warn "No graphical session detected (running from TTY?)"
    check_fix "Log in to a graphical session and re-run this script"
fi

# --- 6. Wayland-specific checks ---
if [ "$SESSION" = "wayland" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
    echo ""
    echo -e "${BOLD}6. Wayland Configuration${NC}"

    # Environment variables
    if [ "${GBM_BACKEND:-}" = "nvidia-drm" ]; then
        check_pass "GBM_BACKEND=nvidia-drm"
    else
        check_fail "GBM_BACKEND not set to nvidia-drm (current: ${GBM_BACKEND:-unset})"
        check_fix "Add GBM_BACKEND=nvidia-drm to /etc/environment and re-login"
    fi

    if [ "${__GLX_VENDOR_LIBRARY_NAME:-}" = "nvidia" ]; then
        check_pass "__GLX_VENDOR_LIBRARY_NAME=nvidia"
    else
        check_warn "__GLX_VENDOR_LIBRARY_NAME not set to nvidia (current: ${__GLX_VENDOR_LIBRARY_NAME:-unset})"
        check_fix "Add __GLX_VENDOR_LIBRARY_NAME=nvidia to /etc/environment and re-login"
    fi

    # EGL-Wayland library
    if dpkg -l 2>/dev/null | grep -q "libnvidia-egl-wayland\|egl-wayland"; then
        check_pass "EGL-Wayland library installed"
    else
        check_fail "EGL-Wayland library NOT installed"
        check_fix "apt install libnvidia-egl-wayland1 egl-wayland"
    fi

    # PreserveVideoMemoryAllocations (for suspend/resume)
    PRESERVE_OK=false
    if [ -f /sys/module/nvidia/parameters/PreserveVideoMemoryAllocations ] && [ "$(cat /sys/module/nvidia/parameters/PreserveVideoMemoryAllocations 2>/dev/null)" = "1" ]; then
        PRESERVE_OK=true
    elif grep -q "NVreg_PreserveVideoMemoryAllocations=1" /proc/cmdline; then
        PRESERVE_OK=true
    fi
    if [ "$PRESERVE_OK" = true ]; then
        check_pass "PreserveVideoMemoryAllocations enabled (suspend/resume)"
    else
        check_warn "PreserveVideoMemoryAllocations not set (suspend/resume may break)"
        check_fix "Add 'options nvidia NVreg_PreserveVideoMemoryAllocations=1' to /etc/modprobe.d/nvidia.conf"
    fi

    # Power management services
    for svc in nvidia-suspend nvidia-resume nvidia-hibernate; do
        if systemctl is-enabled "${svc}.service" 2>/dev/null | grep -q "enabled"; then
            check_pass "${svc}.service enabled"
        else
            check_warn "${svc}.service not enabled"
            check_fix "systemctl enable ${svc}.service"
        fi
    done
fi

# --- 7. X11-specific checks ---
if [ "$SESSION" = "x11" ]; then
    echo ""
    echo -e "${BOLD}6. X11 Configuration${NC}"

    if command -v glxinfo &>/dev/null; then
        GLX_RENDERER=$(glxinfo 2>/dev/null | grep "OpenGL renderer" | head -1 || true)
        if echo "$GLX_RENDERER" | grep -qi "nvidia"; then
            check_pass "OpenGL renderer: NVIDIA"
        elif [ -n "$GLX_RENDERER" ]; then
            check_warn "OpenGL renderer is not NVIDIA: $GLX_RENDERER"
        else
            check_warn "Could not query OpenGL renderer"
        fi
    else
        check_warn "glxinfo not available (install mesa-utils to check OpenGL)"
    fi

    if command -v xrandr &>/dev/null; then
        PROVIDERS=$(xrandr --listproviders 2>/dev/null || true)
        if echo "$PROVIDERS" | grep -qi "nvidia"; then
            check_pass "NVIDIA display provider registered"
        else
            check_warn "NVIDIA not listed in xrandr providers"
        fi
    fi
fi

# --- 8. Dual-GPU checks ---
VGA_COUNT=$(lspci | grep -ci "vga\|3d" 2>/dev/null || echo "0")
if [ "${VGA_COUNT:-0}" -gt 1 ]; then
    echo ""
    echo -e "${BOLD}7. Dual-GPU${NC}"

    echo -e "  Found $VGA_COUNT GPU devices"

    # Check primary DRM device
    if [ -f /sys/class/drm/card0/device/vendor ]; then
        VENDOR=$(cat /sys/class/drm/card0/device/vendor 2>/dev/null)
        case "$VENDOR" in
            0x10de) check_pass "Primary DRM device (card0): NVIDIA" ;;
            0x8086) check_warn "Primary DRM device (card0): Intel (NVIDIA is secondary)"
                    check_fix "For Wayland: nvidia-drm.modeset=1 should handle GPU selection" ;;
            0x1002) check_warn "Primary DRM device (card0): AMD (NVIDIA is secondary)" ;;
            *)      check_warn "Primary DRM device (card0): vendor $VENDOR" ;;
        esac
    fi

    # Check nvidia-primary service (X11 dual-GPU)
    if [ -f /etc/systemd/system/nvidia-primary.service ]; then
        if systemctl is-active --quiet nvidia-primary.service 2>/dev/null; then
            check_pass "nvidia-primary.service active"
        elif systemctl is-enabled --quiet nvidia-primary.service 2>/dev/null; then
            check_warn "nvidia-primary.service enabled but not active"
            check_fix "systemctl status nvidia-primary.service (check for errors)"
        else
            check_warn "nvidia-primary.service not enabled"
            check_fix "systemctl enable nvidia-primary.service"
        fi
    fi
fi

# --- 9. SDDM Health (if SDDM is the display manager) ---
DM_ID=$(systemctl show -p Id display-manager.service 2>/dev/null | cut -d= -f2 || true)
if [ "$DM_ID" = "sddm.service" ] || systemctl is-enabled sddm.service 2>/dev/null | grep -q "enabled"; then
    echo ""
    echo -e "${BOLD}8. SDDM Health${NC}"

    # Check if SDDM config requests Wayland greeter
    SDDM_WAYLAND_GREETER=false
    if grep -qi "^DisplayServer=wayland" /etc/sddm.conf.d/10-wayland.conf 2>/dev/null || \
       grep -qi "^DisplayServer=wayland" /etc/sddm.conf 2>/dev/null; then
        SDDM_WAYLAND_GREETER=true
    fi

    if [ "$SDDM_WAYLAND_GREETER" = true ]; then
        echo -e "  SDDM greeter mode: Wayland"

        # kwin_wayland required as compositor for Wayland greeter
        if command -v kwin_wayland &>/dev/null; then
            check_pass "kwin_wayland binary found"
        else
            check_fail "kwin_wayland NOT found — SDDM Wayland greeter will crash"
            check_fix "apt install kwin-wayland, or set DisplayServer=x11 in /etc/sddm.conf.d/10-wayland.conf"
        fi

        # Qt Wayland plugin required for SDDM greeter
        if dpkg -l 2>/dev/null | grep -q "qtwayland5\|qt6-wayland"; then
            check_pass "Qt Wayland platform plugin installed"
        else
            check_fail "Qt Wayland plugin missing — SDDM greeter will crash"
            check_fix "apt install qtwayland5"
        fi
    else
        echo -e "  SDDM greeter mode: X11"
    fi

    # Check for Wayland session .desktop files
    WAYLAND_SESSIONS=$(ls /usr/share/wayland-sessions/*.desktop 2>/dev/null || true)
    if [ -n "$WAYLAND_SESSIONS" ]; then
        SESSION_COUNT=$(echo "$WAYLAND_SESSIONS" | wc -l)
        check_pass "$SESSION_COUNT Wayland session(s) available in /usr/share/wayland-sessions/"
    else
        if [ "$SESSION" = "wayland" ] || [ "$SDDM_WAYLAND_GREETER" = true ]; then
            check_fail "No Wayland session .desktop files found"
            check_fix "apt install plasma-workspace-wayland (or your preferred Wayland DE)"
        else
            check_warn "No Wayland session .desktop files (OK if using X11 only)"
        fi
    fi

    # Check sddm user group membership
    if id sddm &>/dev/null; then
        for grp in video render; do
            if getent group "$grp" &>/dev/null; then
                if id -nG sddm 2>/dev/null | grep -qw "$grp"; then
                    check_pass "sddm user in $grp group"
                else
                    check_warn "sddm user NOT in $grp group (may prevent GPU access)"
                    check_fix "sudo usermod -aG $grp sddm && sudo systemctl restart sddm"
                fi
            fi
        done
    fi

    # Check NVIDIA modules in initramfs
    INITRAMFS_MODULES="/etc/initramfs-tools/modules"
    if [ -f "$INITRAMFS_MODULES" ]; then
        if grep -q "^nvidia_drm$" "$INITRAMFS_MODULES" 2>/dev/null; then
            check_pass "nvidia_drm in initramfs (early KMS)"
        else
            check_warn "nvidia_drm NOT in initramfs — SDDM may start before GPU is ready"
            check_fix "Add 'nvidia nvidia_modeset nvidia_uvm nvidia_drm' to $INITRAMFS_MODULES && sudo update-initramfs -u"
        fi
    fi

    # Check for conflicting /etc/sddm.conf
    if [ -f /etc/sddm.conf ]; then
        CONFLICT_DS=$(grep -i "^DisplayServer=" /etc/sddm.conf 2>/dev/null || true)
        if [ -n "$CONFLICT_DS" ]; then
            check_warn "/etc/sddm.conf has '$CONFLICT_DS' (may conflict with drop-in config)"
            check_fix "Remove DisplayServer= from /etc/sddm.conf to let /etc/sddm.conf.d/ take effect"
        fi
    fi

    # Check SDDM journal for recent errors
    SDDM_ERRORS=$(journalctl -u sddm -b --no-pager -p err 2>/dev/null | tail -5 || true)
    if [ -n "$SDDM_ERRORS" ]; then
        check_warn "SDDM has recent errors in journal"
        echo -e "         ${BLUE}Run:${NC} journalctl -u sddm -b --no-pager"
    else
        check_pass "No SDDM errors in current boot journal"
    fi
fi

# --- Summary ---
echo ""
echo -e "${BOLD}========================================${NC}"
TOTAL=$((PASS + WARN + FAIL))

if [ "$FAIL" -eq 0 ] && [ "$WARN" -eq 0 ]; then
    echo -e "${GREEN}  ALL CHECKS PASSED ($PASS/$TOTAL)${NC}"
    echo -e "${GREEN}  NVIDIA driver is fully operational${NC}"
elif [ "$FAIL" -eq 0 ]; then
    echo -e "${YELLOW}  PASSED with warnings${NC}"
    echo -e "  ${GREEN}$PASS passed${NC}, ${YELLOW}$WARN warnings${NC}"
    echo -e "  Driver works but some optimizations are missing"
else
    echo -e "${RED}  ISSUES DETECTED${NC}"
    echo -e "  ${GREEN}$PASS passed${NC}, ${YELLOW}$WARN warnings${NC}, ${RED}$FAIL failures${NC}"
    echo -e "  Review the [FAIL] items above and apply the fixes"
fi
echo -e "${BOLD}========================================${NC}"
echo ""

exit "$FAIL"
