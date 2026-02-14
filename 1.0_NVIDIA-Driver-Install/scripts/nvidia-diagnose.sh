#!/bin/bash

# NVIDIA Diagnostic Script
# Comprehensive system analysis for NVIDIA driver troubleshooting

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Output file
OUTPUT_FILE="nvidia-diagnostic-$(date +%Y%m%d-%H%M%S).log"

echo -e "${BLUE}=== NVIDIA Driver Diagnostic Tool ===${NC}"
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
    echo "NVIDIA Driver Diagnostic Report"
    echo "Generated: $(date)"
    echo "System: $(hostname)"
    echo "=========================================="
} > "$OUTPUT_FILE"

# 1. System Information
print_header "System Information"
{
    echo "Hostname: $(hostname)"
    echo "Kernel: $(uname -r)"
    echo "Distribution: $(lsb_release -d 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME)"
    echo "Architecture: $(uname -m)"
    echo "Boot parameters: $(cat /proc/cmdline)"
} | tee -a "$OUTPUT_FILE"

# 2. GPU Detection
print_header "GPU Hardware Detection"
{
    echo "=== PCI Graphics Devices ==="
    lspci -k | grep -A 3 -E "(VGA|3D)"
    echo ""
    echo "=== GPU Details ==="
    lspci -v | grep -A 15 "VGA"
} | tee -a "$OUTPUT_FILE"

# 3. Current Driver Status
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
} | tee -a "$OUTPUT_FILE"

# 4. Installed Packages
print_header "Installed NVIDIA Packages"
{
    if command -v dpkg &> /dev/null; then
        echo "=== Debian/Ubuntu packages ==="
        dpkg -l | grep -i nvidia || echo "No NVIDIA packages found"
    elif command -v pacman &> /dev/null; then
        echo "=== Arch packages ==="
        pacman -Q | grep -i nvidia || echo "No NVIDIA packages found"
    fi
} | tee -a "$OUTPUT_FILE"

# 5. Blacklist Configuration
print_header "Driver Blacklist Configuration"
{
    if [ -f /etc/modprobe.d/blacklist-nouveau.conf ]; then
        echo "=== /etc/modprobe.d/blacklist-nouveau.conf ==="
        cat /etc/modprobe.d/blacklist-nouveau.conf
    else
        print_warning "Nouveau not blacklisted"
    fi
    
    echo ""
    echo "=== All blacklist files ==="
    grep -r "blacklist" /etc/modprobe.d/ 2>/dev/null | grep -i "nouveau\|nvidia" || echo "None found"
} | tee -a "$OUTPUT_FILE"

# 6. X Server Configuration
print_header "X Server Configuration"
{
    echo "=== X Display ==="
    echo "DISPLAY: $DISPLAY"
    
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

# 7. Display Manager Status
print_header "Display Manager Status"
{
    echo "=== Active Display Manager ==="
    systemctl status display-manager --no-pager 2>&1 | head -20
    
    echo ""
    echo "=== Enabled Display Managers ==="
    systemctl list-unit-files | grep -E "lightdm|gdm|sddm|xdm|kdm" || echo "None found"
} | tee -a "$OUTPUT_FILE"

# 8. Recent Logs
print_header "Recent Relevant Logs"
{
    echo "=== Kernel Messages (NVIDIA/Nouveau) ==="
    dmesg | grep -i "nvidia\|nouveau" | tail -50
    
    echo ""
    echo "=== System Journal (last boot) ==="
    journalctl -b | grep -i "nvidia\|nouveau" | tail -30
    
    if [ -f /var/log/Xorg.0.log ]; then
        echo ""
        echo "=== X Server Log (errors/warnings) ==="
        grep -E "(EE)|(WW)" /var/log/Xorg.0.log | tail -30
    fi
} | tee -a "$OUTPUT_FILE"

# 9. OpenGL Information
print_header "OpenGL Information"
{
    if command -v glxinfo &> /dev/null; then
        echo "=== GLX Info ==="
        glxinfo | grep -E "OpenGL version|OpenGL renderer|OpenGL vendor"
    else
        print_warning "glxinfo not installed (install mesa-utils)"
    fi
} | tee -a "$OUTPUT_FILE"

# 10. GRUB Configuration
print_header "GRUB Configuration"
{
    if [ -f /etc/default/grub ]; then
        echo "=== /etc/default/grub ==="
        grep -E "GRUB_CMDLINE_LINUX" /etc/default/grub
    fi
} | tee -a "$OUTPUT_FILE"

# 11. Kernel Headers
print_header "Kernel Headers"
{
    if command -v dpkg &> /dev/null; then
        dpkg -l | grep linux-headers | grep "$(uname -r | cut -d'-' -f1)"
    elif command -v pacman &> /dev/null; then
        pacman -Q | grep linux-headers
    fi
} | tee -a "$OUTPUT_FILE"

# 12. Common Issues Check
print_header "Common Issues Analysis"
{
    ISSUES_FOUND=0
    
    # Check if nouveau is loaded
    if lsmod | grep -q nouveau; then
        print_error "Nouveau driver is loaded - this conflicts with NVIDIA"
        echo "  Fix: Blacklist nouveau in /etc/modprobe.d/blacklist-nouveau.conf"
        ((ISSUES_FOUND++))
    fi
    
    # Check if nvidia module is loaded but nvidia-smi fails
    if lsmod | grep -q nvidia && ! command -v nvidia-smi &> /dev/null; then
        print_warning "NVIDIA kernel module loaded but nvidia-smi not available"
        echo "  Fix: Install nvidia-utils package"
        ((ISSUES_FOUND++))
    fi
    
    # Check for missing kernel headers
    if ! command -v dpkg &> /dev/null || ! dpkg -l | grep -q "linux-headers-$(uname -r)"; then
        if ! command -v pacman &> /dev/null || ! pacman -Q | grep -q "linux-headers"; then
            print_warning "Kernel headers may not be installed"
            echo "  Fix: Install linux-headers for your kernel version"
            ((ISSUES_FOUND++))
        fi
    fi
    
    # Check X server logs for errors
    if [ -f /var/log/Xorg.0.log ] && grep -q "(EE)" /var/log/Xorg.0.log; then
        print_warning "X server errors detected in log"
        echo "  Check: /var/log/Xorg.0.log for details"
        ((ISSUES_FOUND++))
    fi
    
    # Check display manager status
    if ! systemctl is-active --quiet display-manager; then
        print_error "Display manager is not running"
        echo "  Fix: Check display manager configuration and logs"
        ((ISSUES_FOUND++))
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
    echo "Next steps:"
    echo "1. Review the issues found above"
    echo "2. Check the full log file for detailed information"
    echo "3. Refer to the main README.md for solutions"
    echo ""
    echo "Quick checks:"
    echo "  - GPU detected: $(lspci | grep -q VGA && echo 'Yes' || echo 'No')"
    echo "  - NVIDIA loaded: $(lsmod | grep -q nvidia && echo 'Yes' || echo 'No')"
    echo "  - Nouveau loaded: $(lsmod | grep -q nouveau && echo 'Yes (CONFLICT!)' || echo 'No (good)')"
    echo "  - Display manager: $(systemctl is-active display-manager 2>/dev/null || echo 'not running')"
} | tee -a "$OUTPUT_FILE"

echo ""
echo -e "${GREEN}Diagnostic complete!${NC}"
echo "Report saved to: $OUTPUT_FILE"
