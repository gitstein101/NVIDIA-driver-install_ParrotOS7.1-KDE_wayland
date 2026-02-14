#!/bin/bash

# NVIDIA Diagnostic Script v1.2
# Comprehensive system analysis with Wayland and dual-GPU diagnostics

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Output files
DIAG_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
OUTPUT_FILE="nvidia-diagnostic-${DIAG_TIMESTAMP}.log"
JSON_FILE="nvidia-diagnostic-${DIAG_TIMESTAMP}.json"

echo -e "${BLUE}=== NVIDIA Driver Diagnostic Tool v1.2 ===${NC}"
echo "Generating diagnostic report: $OUTPUT_FILE"
echo ""

# Function to print section headers
print_header() {
    echo -e "\n${GREEN}=== $1 ===${NC}" | tee -a "$OUTPUT_FILE"
}

# Function to print warnings
print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$OUTPUT_FILE"
}

# Function to print errors
print_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$OUTPUT_FILE"
}

# Start diagnostic log
{
    echo "NVIDIA Driver Diagnostic Report v1.2"
    echo "Generated: $(date)"
    echo "System: $(hostname)"
    echo "=========================================="
} > "$OUTPUT_FILE"

# 1. System Information
print_header "System Information"
{
    echo "Hostname: $(hostname)"
    echo "Kernel: $(uname -r)"
    echo "Distribution: $(lsb_release -d 2>/dev/null || grep PRETTY_NAME /etc/os-release 2>/dev/null || echo 'Unknown')"
    echo "Architecture: $(uname -m)"
    echo "Boot parameters: $(cat /proc/cmdline)"
} | tee -a "$OUTPUT_FILE"

# 2. Session Type Detection
print_header "Display Session Detection"
{
    echo "=== Session Type ==="
    echo "XDG_SESSION_TYPE: ${XDG_SESSION_TYPE:-not set}"
    echo "WAYLAND_DISPLAY: ${WAYLAND_DISPLAY:-not set}"
    echo "DISPLAY: ${DISPLAY:-not set}"

    if [ "${XDG_SESSION_TYPE:-}" = "wayland" ]; then
        echo "Active session: Wayland"
    elif [ "${XDG_SESSION_TYPE:-}" = "x11" ]; then
        echo "Active session: X11"
    elif [ -n "${WAYLAND_DISPLAY:-}" ]; then
        echo "Active session: Wayland (detected via WAYLAND_DISPLAY)"
    elif [ -n "${DISPLAY:-}" ]; then
        echo "Active session: X11 (detected via DISPLAY)"
    else
        echo "Active session: Unknown (no display session detected — running from TTY?)"
    fi

    echo ""
    echo "=== Compositor Detection ==="
    if pgrep -x "kwin_wayland" > /dev/null 2>&1; then
        echo "Compositor: KWin (Wayland)"
    elif pgrep -x "kwin_x11" > /dev/null 2>&1; then
        echo "Compositor: KWin (X11)"
    elif pgrep -x "mutter" > /dev/null 2>&1; then
        echo "Compositor: Mutter (GNOME)"
    elif pgrep -x "sway" > /dev/null 2>&1; then
        echo "Compositor: Sway"
    else
        echo "Compositor: Unknown or not running"
    fi

    echo ""
    echo "=== Wayland Environment Variables ==="
    echo "GBM_BACKEND: ${GBM_BACKEND:-not set}"
    echo "__GLX_VENDOR_LIBRARY_NAME: ${__GLX_VENDOR_LIBRARY_NAME:-not set}"

    if [ -f /etc/environment ]; then
        echo ""
        echo "=== /etc/environment (NVIDIA-related) ==="
        grep -E "GBM_BACKEND|__GLX_VENDOR_LIBRARY_NAME|WLR_" /etc/environment 2>/dev/null || echo "No NVIDIA Wayland vars in /etc/environment"
    fi
} | tee -a "$OUTPUT_FILE"

# 3. GPU Detection (with dual-GPU awareness)
print_header "GPU Hardware Detection"
{
    echo "=== PCI Graphics Devices ==="
    lspci -k | grep -A 3 -E "(VGA|3D)" || true
    echo ""

    VGA_COUNT=$(lspci | grep -ci "vga\|3d" || true)
    echo "Total GPU devices: $VGA_COUNT"

    if [ "${VGA_COUNT:-0}" -gt 1 ]; then
        echo ""
        echo "=== DUAL-GPU SYSTEM DETECTED ==="
        if lspci | grep -i "vga" | grep -qi "intel"; then
            echo "Configuration: Intel iGPU + NVIDIA dGPU"
        elif lspci | grep -i "vga" | grep -qi "amd"; then
            echo "Configuration: AMD iGPU + NVIDIA dGPU"
        else
            echo "Configuration: Multiple GPUs"
        fi

        # Show which is being used as primary
        echo ""
        echo "=== GPU Primary Status ==="
        if [ -f /sys/class/drm/card0/device/vendor ]; then
            CARD0_VENDOR=$(cat /sys/class/drm/card0/device/vendor 2>/dev/null)
            case "$CARD0_VENDOR" in
                0x10de) echo "card0 (primary DRM device): NVIDIA" ;;
                0x8086) echo "card0 (primary DRM device): Intel" ;;
                0x1002) echo "card0 (primary DRM device): AMD" ;;
                *) echo "card0 vendor: $CARD0_VENDOR" ;;
            esac
        fi
        if [ -f /sys/class/drm/card1/device/vendor ]; then
            CARD1_VENDOR=$(cat /sys/class/drm/card1/device/vendor 2>/dev/null)
            case "$CARD1_VENDOR" in
                0x10de) echo "card1 (secondary DRM device): NVIDIA" ;;
                0x8086) echo "card1 (secondary DRM device): Intel" ;;
                0x1002) echo "card1 (secondary DRM device): AMD" ;;
                *) echo "card1 vendor: $CARD1_VENDOR" ;;
            esac
        fi
    fi

    echo ""
    echo "=== GPU Details ==="
    lspci -v | grep -A 15 "VGA"
} | tee -a "$OUTPUT_FILE"

# 4. Current Driver Status
print_header "Current Driver Status"
{
    echo "=== Loaded Modules ==="
    if lsmod | grep -q nvidia; then
        echo -e "${GREEN}NVIDIA modules loaded:${NC}"
        lsmod | grep nvidia
    else
        print_warning "No NVIDIA modules loaded"
    fi

    if lsmod | grep -q nouveau; then
        print_warning "Nouveau driver is loaded (conflicts with NVIDIA)"
        lsmod | grep nouveau
    else
        echo "Nouveau: Not loaded (good)"
    fi

    echo ""
    echo "=== NVIDIA Driver Version ==="
    if command -v nvidia-smi &> /dev/null; then
        nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>&1
    else
        print_warning "nvidia-smi not available"
    fi

    echo ""
    echo "=== nvidia-drm.modeset Status ==="
    if grep -q "nvidia-drm.modeset=1" /proc/cmdline; then
        echo "nvidia-drm.modeset=1: Enabled (via boot parameters)"
    elif [ -f /sys/module/nvidia_drm/parameters/modeset ]; then
        MODESET_VAL=$(cat /sys/module/nvidia_drm/parameters/modeset)
        echo "nvidia-drm.modeset: $MODESET_VAL (via module parameter)"
    else
        print_warning "nvidia-drm.modeset not detected"
    fi
} | tee -a "$OUTPUT_FILE"

# 5. Installed Packages
print_header "Installed NVIDIA Packages"
{
    if command -v dpkg &> /dev/null; then
        echo "=== Debian/Ubuntu packages ==="
        dpkg -l 2>/dev/null | grep -i nvidia || echo "No NVIDIA packages found"
        echo ""
        echo "=== EGL/Wayland packages ==="
        dpkg -l 2>/dev/null | grep -i "egl-wayland\|libnvidia-egl" || echo "No EGL-Wayland packages found"
    elif command -v pacman &> /dev/null; then
        echo "=== Arch packages ==="
        pacman -Q 2>/dev/null | grep -i nvidia || echo "No NVIDIA packages found"
        echo ""
        echo "=== EGL/Wayland packages ==="
        pacman -Q 2>/dev/null | grep -i "egl-wayland" || echo "No EGL-Wayland packages found"
    fi
} | tee -a "$OUTPUT_FILE"

# 6. Blacklist Configuration
print_header "Driver Blacklist Configuration"
{
    if [ -f /etc/modprobe.d/blacklist-nouveau.conf ]; then
        echo "=== /etc/modprobe.d/blacklist-nouveau.conf ==="
        cat /etc/modprobe.d/blacklist-nouveau.conf
    else
        print_warning "Nouveau not blacklisted"
    fi

    echo ""
    if [ -f /etc/modprobe.d/blacklist-intel.conf ]; then
        echo "=== /etc/modprobe.d/blacklist-intel.conf ==="
        cat /etc/modprobe.d/blacklist-intel.conf
    fi

    echo ""
    echo "=== All blacklist files ==="
    grep -r "blacklist" /etc/modprobe.d/ 2>/dev/null | grep -i "nouveau\|nvidia\|i915\|intel" || echo "None found"
} | tee -a "$OUTPUT_FILE"

# 7. X Server Configuration
print_header "X Server Configuration"
{
    echo "=== X Display ==="
    echo "DISPLAY: ${DISPLAY:-not set}"

    if [ -f /etc/X11/xorg.conf ]; then
        echo "=== /etc/X11/xorg.conf exists ==="
        cat /etc/X11/xorg.conf
    else
        echo "No /etc/X11/xorg.conf found"
    fi

    if [ -d /etc/X11/xorg.conf.d ]; then
        echo ""
        echo "=== /etc/X11/xorg.conf.d/ contents ==="
        ls -la /etc/X11/xorg.conf.d/
        for conf in /etc/X11/xorg.conf.d/*; do
            if [ -f "$conf" ]; then
                echo "--- $conf ---"
                cat "$conf"
            fi
        done
    fi
} | tee -a "$OUTPUT_FILE"

# 8. Wayland Configuration
print_header "Wayland Configuration"
{
    echo "=== SDDM Configuration ==="
    if [ -f /etc/sddm.conf ]; then
        echo "--- /etc/sddm.conf ---"
        cat /etc/sddm.conf
    else
        echo "No /etc/sddm.conf"
    fi

    if [ -d /etc/sddm.conf.d ]; then
        echo ""
        echo "--- /etc/sddm.conf.d/ ---"
        for conf in /etc/sddm.conf.d/*; do
            if [ -f "$conf" ]; then
                echo "--- $conf ---"
                cat "$conf"
            fi
        done
    fi

    echo ""
    echo "=== GDM Configuration ==="
    if [ -f /etc/gdm3/daemon.conf ]; then
        echo "--- /etc/gdm3/daemon.conf ---"
        grep -E "Wayland|wayland" /etc/gdm3/daemon.conf || echo "No Wayland settings found"
    else
        echo "No GDM configuration found"
    fi

    echo ""
    echo "=== Wayland Session Files ==="
    ls /usr/share/wayland-sessions/ 2>/dev/null || echo "No Wayland session files found"

    echo ""
    echo "=== X11 Session Files ==="
    ls /usr/share/xsessions/ 2>/dev/null || echo "No X11 session files found"
} | tee -a "$OUTPUT_FILE"

# 9. Display Manager Status
print_header "Display Manager Status"
{
    echo "=== Active Display Manager ==="
    systemctl status display-manager --no-pager 2>&1 | head -20

    echo ""
    echo "=== Enabled Display Managers ==="
    systemctl list-unit-files | grep -E "lightdm|gdm|sddm|xdm|kdm" || echo "None found"
} | tee -a "$OUTPUT_FILE"

# 10. Dual-GPU Service Status
print_header "Dual-GPU Service Status"
{
    if [ -f /etc/systemd/system/nvidia-primary.service ]; then
        echo "=== nvidia-primary.service ==="
        systemctl status nvidia-primary.service --no-pager 2>&1 || true
    else
        echo "nvidia-primary.service: Not installed"
    fi

    if [ -f /usr/local/bin/nvidia-primary.sh ]; then
        echo ""
        echo "=== /usr/local/bin/nvidia-primary.sh ==="
        cat /usr/local/bin/nvidia-primary.sh
    fi
} | tee -a "$OUTPUT_FILE"

# 11. Recent Logs
print_header "Recent Relevant Logs"
{
    echo "=== Kernel Messages (NVIDIA/Nouveau) ==="
    dmesg 2>/dev/null | grep -i "nvidia\|nouveau" | tail -50 || echo "No kernel messages found"

    echo ""
    echo "=== System Journal (last boot) ==="
    journalctl -b 2>/dev/null | grep -i "nvidia\|nouveau" | tail -30 || echo "No journal entries found"

    if [ -f /var/log/Xorg.0.log ]; then
        echo ""
        echo "=== X Server Log (errors/warnings) ==="
        grep -E "(EE)|(WW)" /var/log/Xorg.0.log | tail -30
    fi

    echo ""
    echo "=== Wayland/KWin Logs ==="
    journalctl -b 2>/dev/null | grep -i "kwin\|wayland\|gbm\|drm" | grep -iv "bluetooth" | tail -30 || echo "No Wayland/KWin log entries found"
} | tee -a "$OUTPUT_FILE"

# 12. OpenGL / EGL Information
print_header "Graphics API Information"
{
    echo "=== OpenGL (GLX) Info ==="
    if command -v glxinfo &> /dev/null; then
        glxinfo | grep -E "OpenGL version|OpenGL renderer|OpenGL vendor" 2>/dev/null || echo "glxinfo failed (no X11 display?)"
    else
        print_warning "glxinfo not installed (install mesa-utils)"
    fi

    echo ""
    echo "=== EGL Info ==="
    if command -v eglinfo &> /dev/null; then
        eglinfo 2>/dev/null | head -30 || echo "eglinfo failed"
    else
        echo "eglinfo not installed (install mesa-utils-extra)"
    fi

    echo ""
    echo "=== Wayland Info ==="
    if command -v wayland-info &> /dev/null; then
        wayland-info 2>/dev/null | head -20 || echo "wayland-info failed (no Wayland session?)"
    else
        echo "wayland-info not installed (install wayland-utils)"
    fi

    echo ""
    echo "=== Vulkan Info ==="
    if command -v vulkaninfo &> /dev/null; then
        vulkaninfo --summary 2>/dev/null || echo "vulkaninfo failed"
    else
        echo "vulkaninfo not installed (install vulkan-tools)"
    fi
} | tee -a "$OUTPUT_FILE"

# 13. GRUB Configuration
print_header "GRUB Configuration"
{
    if [ -f /etc/default/grub ]; then
        echo "=== /etc/default/grub ==="
        grep -E "GRUB_CMDLINE_LINUX" /etc/default/grub
    fi
} | tee -a "$OUTPUT_FILE"

# 14. Kernel Headers
print_header "Kernel Headers"
{
    if command -v dpkg &> /dev/null; then
        dpkg -l 2>/dev/null | grep linux-headers | grep "$(uname -r | cut -d'-' -f1)" || echo "No matching headers found"
    elif command -v pacman &> /dev/null; then
        pacman -Q 2>/dev/null | grep linux-headers || echo "No matching headers found"
    fi
} | tee -a "$OUTPUT_FILE"

# 15. NVIDIA Wayland Deep Checks
print_header "NVIDIA Wayland Deep Checks"
{
    echo "=== nvidia-drm.fbdev Status ==="
    if [ -f /sys/module/nvidia_drm/parameters/fbdev ]; then
        FBDEV_VAL=$(cat /sys/module/nvidia_drm/parameters/fbdev)
        echo "nvidia-drm.fbdev: $FBDEV_VAL (via module parameter)"
    elif grep -q "nvidia-drm.fbdev=1" /proc/cmdline; then
        echo "nvidia-drm.fbdev=1: Enabled (via boot parameters)"
    else
        echo "nvidia-drm.fbdev: Not detected"
        KERNEL_MAJOR=$(uname -r | cut -d. -f1)
        if [ "${KERNEL_MAJOR:-0}" -ge 6 ]; then
            print_warning "Kernel 6.x+ detected — nvidia-drm.fbdev=1 is recommended for framebuffer console on Wayland"
        fi
    fi

    echo ""
    echo "=== NVreg_PreserveVideoMemoryAllocations Status ==="
    if [ -f /sys/module/nvidia/parameters/PreserveVideoMemoryAllocations ]; then
        PRESERVE_VAL=$(cat /sys/module/nvidia/parameters/PreserveVideoMemoryAllocations)
        echo "PreserveVideoMemoryAllocations: $PRESERVE_VAL"
    elif grep -q "NVreg_PreserveVideoMemoryAllocations=1" /proc/cmdline; then
        echo "PreserveVideoMemoryAllocations: Enabled (via boot parameters)"
    else
        echo "PreserveVideoMemoryAllocations: Not detected"
        print_warning "Required for suspend/resume on Wayland — add NVreg_PreserveVideoMemoryAllocations=1 to kernel params or /etc/modprobe.d/nvidia.conf"
    fi

    echo ""
    echo "=== NVIDIA Power Management Services ==="
    for SVC in nvidia-suspend nvidia-resume nvidia-hibernate; do
        if systemctl is-enabled "${SVC}.service" 2>/dev/null | grep -q "enabled"; then
            echo "  ${SVC}.service: enabled"
        else
            print_warning "${SVC}.service: not enabled (required for suspend/resume with PreserveVideoMemoryAllocations)"
        fi
    done

    echo ""
    echo "=== GBM vs EGL Stream Backend Detection ==="
    if [ "${GBM_BACKEND:-}" = "nvidia-drm" ]; then
        echo "Backend: GBM (nvidia-drm) — modern path"
    elif [ -n "${__NV_PRIME_RENDER_OFFLOAD:-}" ]; then
        echo "Backend: EGL Streams (legacy) — __NV_PRIME_RENDER_OFFLOAD is set"
        print_warning "EGL Streams is deprecated — switch to GBM by setting GBM_BACKEND=nvidia-drm"
    else
        echo "Backend: Not explicitly configured"
        echo "  GBM_BACKEND: ${GBM_BACKEND:-not set}"
        echo "  __NV_PRIME_RENDER_OFFLOAD: ${__NV_PRIME_RENDER_OFFLOAD:-not set}"
    fi

    echo ""
    echo "=== Explicit Sync Support ==="
    KERNEL_VER=$(uname -r)
    KERNEL_MAJOR=$(echo "$KERNEL_VER" | cut -d. -f1)
    KERNEL_MINOR=$(echo "$KERNEL_VER" | cut -d. -f2)
    DRIVER_VER=""
    if command -v nvidia-smi &> /dev/null; then
        DRIVER_VER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null || true)
    fi
    DRIVER_MAJOR=$(echo "${DRIVER_VER:-0}" | cut -d. -f1)

    SYNC_KERNEL=false
    SYNC_DRIVER=false
    if [ "${KERNEL_MAJOR:-0}" -gt 6 ] || { [ "${KERNEL_MAJOR:-0}" -eq 6 ] && [ "${KERNEL_MINOR:-0}" -ge 8 ]; }; then
        SYNC_KERNEL=true
    fi
    if [ "${DRIVER_MAJOR:-0}" -ge 555 ]; then
        SYNC_DRIVER=true
    fi

    echo "  Kernel: $KERNEL_VER (needs >= 6.8 for explicit sync: $SYNC_KERNEL)"
    echo "  Driver: ${DRIVER_VER:-unknown} (needs >= 555 for explicit sync: $SYNC_DRIVER)"
    if [ "$SYNC_KERNEL" = true ] && [ "$SYNC_DRIVER" = true ]; then
        echo -e "  ${GREEN}Explicit sync supported — eliminates Wayland flickering${NC}"
    elif [ "$SYNC_KERNEL" = false ] && [ "$SYNC_DRIVER" = false ]; then
        print_warning "Neither kernel nor driver supports explicit sync — Wayland may have flickering"
    elif [ "$SYNC_KERNEL" = false ]; then
        print_warning "Kernel < 6.8 — upgrade kernel for explicit sync support"
    else
        print_warning "Driver < 555 — upgrade NVIDIA driver for explicit sync support"
    fi
} | tee -a "$OUTPUT_FILE"

# 16. Common Issues Check
print_header "Common Issues Analysis"
{
    ISSUES_FOUND=0

    # Check if nouveau is loaded
    if lsmod | grep -q nouveau; then
        print_error "Nouveau driver is loaded — this conflicts with NVIDIA"
        echo "  Fix: Blacklist nouveau in /etc/modprobe.d/blacklist-nouveau.conf"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi

    # Check if nvidia module is loaded but nvidia-smi fails
    if lsmod | grep -q nvidia && ! command -v nvidia-smi &> /dev/null; then
        print_warning "NVIDIA kernel module loaded but nvidia-smi not available"
        echo "  Fix: Install nvidia-utils package"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi

    # Check for missing kernel headers
    if ! command -v dpkg &> /dev/null || ! dpkg -l 2>/dev/null | grep -q "linux-headers-$(uname -r)"; then
        if ! command -v pacman &> /dev/null || ! pacman -Q 2>/dev/null | grep -q "linux-headers"; then
            print_warning "Kernel headers may not be installed"
            echo "  Fix: Install linux-headers for your kernel version"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        fi
    fi

    # Check X server logs for errors
    if [ -f /var/log/Xorg.0.log ] && grep -q "(EE)" /var/log/Xorg.0.log; then
        print_warning "X server errors detected in log"
        echo "  Check: /var/log/Xorg.0.log for details"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi

    # Check display manager status
    if ! systemctl is-active --quiet display-manager; then
        print_error "Display manager is not running"
        echo "  Fix: Check display manager configuration and logs"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi

    # Wayland-specific checks
    if [ "${XDG_SESSION_TYPE:-}" = "wayland" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
        # Check nvidia-drm.modeset
        if ! grep -q "nvidia-drm.modeset=1" /proc/cmdline; then
            print_error "Wayland session but nvidia-drm.modeset=1 not in boot parameters"
            echo "  Fix: Add nvidia-drm.modeset=1 to GRUB_CMDLINE_LINUX_DEFAULT"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        fi

        # Check GBM_BACKEND
        if [ "${GBM_BACKEND:-}" != "nvidia-drm" ]; then
            print_warning "GBM_BACKEND not set to nvidia-drm"
            echo "  Fix: Add GBM_BACKEND=nvidia-drm to /etc/environment"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        fi

        # Check EGL wayland library
        if command -v dpkg &> /dev/null; then
            if ! dpkg -l 2>/dev/null | grep -q "libnvidia-egl-wayland\|egl-wayland"; then
                print_warning "EGL-Wayland library not installed"
                echo "  Fix: apt install libnvidia-egl-wayland1"
                ISSUES_FOUND=$((ISSUES_FOUND + 1))
            fi
        fi

        # Check nvidia-drm.fbdev on kernel 6.x+
        KERN_MAJOR=$(uname -r | cut -d. -f1)
        if [ "${KERN_MAJOR:-0}" -ge 6 ]; then
            FBDEV_OK=false
            if [ -f /sys/module/nvidia_drm/parameters/fbdev ] && [ "$(cat /sys/module/nvidia_drm/parameters/fbdev)" = "Y" ]; then
                FBDEV_OK=true
            elif grep -q "nvidia-drm.fbdev=1" /proc/cmdline; then
                FBDEV_OK=true
            fi
            if [ "$FBDEV_OK" = false ]; then
                print_warning "nvidia-drm.fbdev=1 not set (recommended on kernel 6.x+ for Wayland framebuffer console)"
                echo "  Fix: Add nvidia-drm.fbdev=1 to GRUB_CMDLINE_LINUX_DEFAULT"
                ISSUES_FOUND=$((ISSUES_FOUND + 1))
            fi
        fi

        # Check PreserveVideoMemoryAllocations
        PRESERVE_OK=false
        if [ -f /sys/module/nvidia/parameters/PreserveVideoMemoryAllocations ] && [ "$(cat /sys/module/nvidia/parameters/PreserveVideoMemoryAllocations)" = "1" ]; then
            PRESERVE_OK=true
        elif grep -q "NVreg_PreserveVideoMemoryAllocations=1" /proc/cmdline; then
            PRESERVE_OK=true
        fi
        if [ "$PRESERVE_OK" = false ]; then
            print_warning "NVreg_PreserveVideoMemoryAllocations=1 not set (required for suspend/resume on Wayland)"
            echo "  Fix: Add 'options nvidia NVreg_PreserveVideoMemoryAllocations=1' to /etc/modprobe.d/nvidia.conf"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        fi

        # Check nvidia suspend/resume services
        for SVC in nvidia-suspend nvidia-resume nvidia-hibernate; do
            if ! systemctl is-enabled "${SVC}.service" 2>/dev/null | grep -q "enabled"; then
                print_warning "${SVC}.service not enabled (required for Wayland suspend/resume)"
                echo "  Fix: systemctl enable ${SVC}.service"
                ISSUES_FOUND=$((ISSUES_FOUND + 1))
            fi
        done
    fi

    # Dual-GPU checks
    VGA_COUNT=$(lspci | grep -ci "vga\|3d" || true)
    if [ "${VGA_COUNT:-0}" -gt 1 ]; then
        if [ "${XDG_SESSION_TYPE:-}" = "x11" ] && [ ! -f /etc/X11/xorg.conf ]; then
            print_warning "Dual-GPU system on X11 without xorg.conf — display may route to wrong GPU"
            echo "  Fix: Run nvidia-install.sh to configure dual-GPU"
            ISSUES_FOUND=$((ISSUES_FOUND + 1))
        fi
    fi

    if [ $ISSUES_FOUND -eq 0 ]; then
        echo -e "${GREEN}No obvious issues detected${NC}"
    else
        echo ""
        echo -e "${YELLOW}Found $ISSUES_FOUND potential issue(s)${NC}"
    fi
} | tee -a "$OUTPUT_FILE"

# Summary
print_header "Diagnostic Summary"
{
    echo "Full diagnostic log saved to: $OUTPUT_FILE"
    echo ""
    echo "Quick checks:"
    echo "  - GPU detected: $(lspci | grep -q VGA && echo 'Yes' || echo 'No')"
    echo "  - GPU count: $(lspci | grep -ci 'vga\|3d' || echo '0')"
    echo "  - NVIDIA loaded: $(lsmod | grep -q nvidia && echo 'Yes' || echo 'No')"
    echo "  - Nouveau loaded: $(lsmod | grep -q nouveau && echo 'Yes (CONFLICT!)' || echo 'No (good)')"
    echo "  - Display manager: $(systemctl is-active display-manager 2>/dev/null || echo 'not running')"
    echo "  - Session type: ${XDG_SESSION_TYPE:-unknown}"
    echo "  - nvidia-drm.modeset=1: $(grep -q 'nvidia-drm.modeset=1' /proc/cmdline && echo 'Yes' || echo 'No')"
    echo ""
    echo "Next steps:"
    echo "1. Review the issues found above"
    echo "2. Check the full log file for detailed information"
    echo "3. Refer to docs/QUICK-TROUBLESHOOTING.md for solutions"
    echo "4. Refer to docs/WAYLAND-SUPPORT.md for Wayland-specific help"
} | tee -a "$OUTPUT_FILE"

# Generate JSON report
echo -e "\n${BLUE}Generating JSON report: $JSON_FILE${NC}"
{
    # Collect values for JSON
    _hostname=$(hostname)
    _kernel=$(uname -r)
    _distro=$(lsb_release -d -s 2>/dev/null || grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "Unknown")
    _arch=$(uname -m)
    _boot_params=$(cat /proc/cmdline)
    _session_type="${XDG_SESSION_TYPE:-unknown}"
    _wayland_display="${WAYLAND_DISPLAY:-}"
    _display="${DISPLAY:-}"

    # Compositor
    _compositor="unknown"
    if pgrep -x "kwin_wayland" > /dev/null 2>&1; then _compositor="kwin_wayland"
    elif pgrep -x "kwin_x11" > /dev/null 2>&1; then _compositor="kwin_x11"
    elif pgrep -x "mutter" > /dev/null 2>&1; then _compositor="mutter"
    elif pgrep -x "sway" > /dev/null 2>&1; then _compositor="sway"
    fi

    # GPU info
    _gpu_count=$(lspci | grep -ci "vga\|3d" || echo "0")
    _gpu_devices_json=""
    while IFS= read -r line; do
        # Escape quotes and backslashes for JSON
        line_escaped=$(printf '%s' "$line" | sed 's/\\/\\\\/g; s/"/\\"/g')
        if [ -n "$_gpu_devices_json" ]; then
            _gpu_devices_json="${_gpu_devices_json}, \"${line_escaped}\""
        else
            _gpu_devices_json="\"${line_escaped}\""
        fi
    done < <(lspci | grep -i "vga\|3d" || true)

    _dual_gpu=false
    [ "${_gpu_count:-0}" -gt 1 ] && _dual_gpu=true

    _primary_drm="unknown"
    if [ -f /sys/class/drm/card0/device/vendor ]; then
        case "$(cat /sys/class/drm/card0/device/vendor 2>/dev/null)" in
            0x10de) _primary_drm="nvidia" ;;
            0x8086) _primary_drm="intel" ;;
            0x1002) _primary_drm="amd" ;;
            *) _primary_drm="$(cat /sys/class/drm/card0/device/vendor 2>/dev/null)" ;;
        esac
    fi

    # Driver info
    _nvidia_loaded=false
    lsmod | grep -q nvidia && _nvidia_loaded=true
    _nouveau_loaded=false
    lsmod | grep -q nouveau && _nouveau_loaded=true

    _driver_version=""
    if command -v nvidia-smi &> /dev/null; then
        _driver_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null || true)
    fi

    _drm_modeset="false"
    if grep -q "nvidia-drm.modeset=1" /proc/cmdline; then
        _drm_modeset="true"
    elif [ -f /sys/module/nvidia_drm/parameters/modeset ] && [ "$(cat /sys/module/nvidia_drm/parameters/modeset)" = "Y" ]; then
        _drm_modeset="true"
    fi

    # Wayland info
    _gbm_backend="${GBM_BACKEND:-}"
    _glx_vendor="${__GLX_VENDOR_LIBRARY_NAME:-}"

    _egl_wayland_installed=false
    if command -v dpkg &> /dev/null; then
        dpkg -l 2>/dev/null | grep -q "egl-wayland\|libnvidia-egl" && _egl_wayland_installed=true
    elif command -v pacman &> /dev/null; then
        pacman -Q 2>/dev/null | grep -q "egl-wayland" && _egl_wayland_installed=true
    fi

    _explicit_sync=false
    _k_major=$(echo "$_kernel" | cut -d. -f1)
    _k_minor=$(echo "$_kernel" | cut -d. -f2)
    _d_major=$(echo "${_driver_version:-0}" | cut -d. -f1)
    if { [ "${_k_major:-0}" -gt 6 ] || { [ "${_k_major:-0}" -eq 6 ] && [ "${_k_minor:-0}" -ge 8 ]; }; } && [ "${_d_major:-0}" -ge 555 ]; then
        _explicit_sync=true
    fi

    _preserve_mem="false"
    if [ -f /sys/module/nvidia/parameters/PreserveVideoMemoryAllocations ] && [ "$(cat /sys/module/nvidia/parameters/PreserveVideoMemoryAllocations)" = "1" ]; then
        _preserve_mem="true"
    elif grep -q "NVreg_PreserveVideoMemoryAllocations=1" /proc/cmdline; then
        _preserve_mem="true"
    fi

    # Count issues (re-derive from quick checks)
    _issues=0
    _issues_json=""
    add_issue() {
        _issues=$((_issues + 1))
        local escaped
        escaped=$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')
        if [ -n "$_issues_json" ]; then
            _issues_json="${_issues_json}, \"${escaped}\""
        else
            _issues_json="\"${escaped}\""
        fi
    }

    if lsmod | grep -q nouveau; then add_issue "Nouveau driver loaded (conflicts with NVIDIA)"; fi
    if [ "$_nvidia_loaded" = true ] && ! command -v nvidia-smi &> /dev/null; then
        add_issue "NVIDIA module loaded but nvidia-smi not available"
    fi
    if [ "$_drm_modeset" = "false" ]; then
        add_issue "nvidia-drm.modeset=1 not enabled"
    fi
    if { [ "$_session_type" = "wayland" ] || [ -n "$_wayland_display" ]; } && [ "${_gbm_backend}" != "nvidia-drm" ]; then
        add_issue "GBM_BACKEND not set to nvidia-drm for Wayland session"
    fi
    if { [ "$_session_type" = "wayland" ] || [ -n "$_wayland_display" ]; } && [ "$_preserve_mem" = "false" ]; then
        add_issue "NVreg_PreserveVideoMemoryAllocations not set (suspend/resume will fail)"
    fi

    # Write JSON
    cat << ENDJSON
{
  "version": "1.2",
  "timestamp": "$(date -Iseconds)",
  "system": {
    "hostname": "${_hostname}",
    "kernel": "${_kernel}",
    "distro": $(printf '%s' "$_distro" | sed 's/\\/\\\\/g; s/"/\\"/g' | sed 's/.*/"&"/'),
    "arch": "${_arch}",
    "boot_params": $(printf '%s' "$_boot_params" | sed 's/\\/\\\\/g; s/"/\\"/g' | sed 's/.*/"&"/')
  },
  "session": {
    "type": "${_session_type}",
    "compositor": "${_compositor}",
    "wayland_display": "${_wayland_display}",
    "display": "${_display}"
  },
  "gpu": {
    "count": ${_gpu_count:-0},
    "devices": [${_gpu_devices_json}],
    "dual_gpu": ${_dual_gpu},
    "primary_drm": "${_primary_drm}"
  },
  "driver": {
    "nvidia_loaded": ${_nvidia_loaded},
    "nouveau_loaded": ${_nouveau_loaded},
    "version": "${_driver_version}",
    "drm_modeset": ${_drm_modeset}
  },
  "wayland": {
    "gbm_backend": "${_gbm_backend}",
    "glx_vendor": "${_glx_vendor}",
    "egl_wayland_installed": ${_egl_wayland_installed},
    "explicit_sync": ${_explicit_sync},
    "preserve_video_memory": ${_preserve_mem}
  },
  "issues_found": ${_issues},
  "issues": [${_issues_json}]
}
ENDJSON
} > "$JSON_FILE"

echo ""
echo -e "${GREEN}Diagnostic complete!${NC}"
echo "Report saved to: $OUTPUT_FILE"
echo "JSON report saved to: $JSON_FILE"
