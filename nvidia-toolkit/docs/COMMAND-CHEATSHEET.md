# NVIDIA Driver Command Cheatsheet

## Emergency Quick Reference

### Access TTY When GUI Fails
```bash
Ctrl + Alt + F2    # Switch to TTY2
Ctrl + Alt + F1    # Back to GUI (if working)
Ctrl + Alt + F7    # Alternative GUI terminal
```

### Emergency Driver Removal (One-Liner)
```bash
sudo apt remove --purge '^nvidia-.*' && sudo reboot
```

## Installation Commands

```bash
# Update system
sudo apt update && sudo apt upgrade

# Install kernel headers
sudo apt install linux-headers-$(uname -r)

# Blacklist nouveau
echo -e "blacklist nouveau\noptions nouveau modeset=0" | sudo tee /etc/modprobe.d/blacklist-nouveau.conf
sudo update-initramfs -u

# Install NVIDIA driver
sudo apt install nvidia-driver nvidia-settings

# Reboot
sudo reboot
```

## Diagnostic Commands

### GPU Detection
```bash
lspci | grep -i vga                    # Detect GPU
lspci -k | grep -A 2 -E "(VGA|3D)"    # GPU with driver info
nvidia-smi                             # NVIDIA System Management
```

### Driver Status
```bash
lsmod | grep nvidia                    # Check if NVIDIA loaded
lsmod | grep nouveau                   # Check if nouveau loaded
nvidia-smi --query-gpu=driver_version --format=csv,noheader
modinfo nvidia                         # Driver module info
```

### Package Status
```bash
dpkg -l | grep nvidia                  # List NVIDIA packages
apt search nvidia-driver               # Available drivers
```

### System Logs
```bash
dmesg | grep -i nvidia                 # Kernel messages
journalctl -b | grep -i nvidia         # System journal (current boot)
journalctl -b -1 | grep -i nvidia      # Previous boot
cat /var/log/Xorg.0.log | grep "(EE)"  # X server errors
```

### Display Manager
```bash
systemctl status display-manager       # Check DM status
systemctl list-unit-files | grep -E "lightdm|gdm|sddm"  # List DMs
ps aux | grep -E "X|wayland"          # Check running display server
```

## Wayland Verification Commands

### Session Type
```bash
echo $XDG_SESSION_TYPE                 # Should say "wayland" or "x11"
echo $WAYLAND_DISPLAY                  # Set if in Wayland session
echo $DISPLAY                          # Set if X11 (or XWayland)
```

### Wayland-Specific Diagnostics
```bash
wayland-info                           # Wayland compositor info
eglinfo | head -20                     # EGL rendering info
kscreen-doctor --outputs               # KDE display info

# Check environment variables
echo $GBM_BACKEND                      # Should be "nvidia-drm"
echo $__GLX_VENDOR_LIBRARY_NAME        # Should be "nvidia"
```

### Compositor Check
```bash
pgrep -a kwin_wayland                  # KDE Wayland compositor
pgrep -a kwin_x11                      # KDE X11 compositor
pgrep -a mutter                        # GNOME compositor
pgrep Xwayland                         # XWayland bridge
```

### DRM/Modeset Status
```bash
cat /sys/module/nvidia_drm/parameters/modeset  # Should be "Y"
cat /proc/cmdline | grep nvidia-drm    # Check boot params
```

## Dual-GPU Commands

### Detect GPUs
```bash
lspci | grep -i "vga\|3d"             # List all GPU devices
lspci -k | grep -A 3 "VGA"            # GPUs with driver info
```

### Check Primary GPU (DRM)
```bash
cat /sys/class/drm/card0/device/vendor # Primary GPU vendor
cat /sys/class/drm/card1/device/vendor # Secondary GPU vendor
# 0x10de = NVIDIA, 0x8086 = Intel, 0x1002 = AMD
```

### X11 Provider Setup (Dual-GPU)
```bash
xrandr --listproviders                 # List display providers
xrandr --setprovideroutputsource modesetting NVIDIA-0  # Route output
xrandr --auto                          # Auto-configure outputs
```

### Dual-GPU Service
```bash
systemctl status nvidia-primary        # Check service status
systemctl enable nvidia-primary        # Enable at boot
systemctl disable nvidia-primary       # Disable
```

## Session Type Switching

### At Login Screen (SDDM)
```
1. Click session selector (bottom-left of login screen)
2. Choose "Plasma (Wayland)" or "Plasma (X11)"
3. Log in
```

### Set Default Session
```bash
# SDDM config: /etc/sddm.conf.d/10-wayland.conf
[General]
Session=plasmawayland.desktop    # Default to Wayland
# or
Session=plasma.desktop           # Default to X11
```

### Force X11 from TTY
```bash
export DISPLAY=:0
startx
# or
sudo systemctl restart display-manager
```

## Configuration Commands

### Blacklist Nouveau
```bash
# Create blacklist file
sudo tee /etc/modprobe.d/blacklist-nouveau.conf << EOF
blacklist nouveau
options nouveau modeset=0
EOF

# Update initramfs
sudo update-initramfs -u

# Verify
cat /etc/modprobe.d/blacklist-nouveau.conf
```

### Generate X Configuration
```bash
sudo nvidia-xconfig                    # Generate xorg.conf
sudo nvidia-xconfig --query-gpu-info   # Query GPU info
```

### GRUB Configuration
```bash
# Edit GRUB
sudo nano /etc/default/grub

# Required kernel parameter:
# GRUB_CMDLINE_LINUX_DEFAULT="quiet splash nvidia-drm.modeset=1"

# Update GRUB
sudo update-grub
```

### Display Manager Control
```bash
# Status
systemctl status display-manager

# Start/Stop/Restart
sudo systemctl start display-manager
sudo systemctl stop display-manager
sudo systemctl restart display-manager

# Enable/Disable
sudo systemctl enable display-manager
sudo systemctl disable display-manager

# Switch display manager
sudo systemctl disable sddm
sudo systemctl enable lightdm
sudo systemctl start lightdm
```

## Removal Commands

### Complete NVIDIA Removal
```bash
sudo systemctl stop display-manager
sudo apt remove --purge '^nvidia-.*' '^libnvidia-.*'
sudo apt autoremove
sudo rm -f /etc/X11/xorg.conf
sudo rm -f /etc/X11/xorg.conf.d/*nvidia*
sudo update-initramfs -u
sudo reboot
```

### Unload NVIDIA Modules
```bash
sudo rmmod nvidia_drm
sudo rmmod nvidia_modeset
sudo rmmod nvidia_uvm
sudo rmmod nvidia
```

## Testing Commands

### Verify Installation (X11)
```bash
nvidia-smi                             # GPU info and driver version
nvidia-settings                        # Open NVIDIA control panel
glxinfo | grep "OpenGL"               # Check OpenGL info
glxgears                              # Test OpenGL (simple benchmark)
```

### Verify Installation (Wayland)
```bash
nvidia-smi                             # GPU info (works on both)
eglinfo | head -20                     # EGL rendering info
wayland-info                           # Compositor details
kscreen-doctor --outputs               # KDE display outputs
```

### Test 3D Acceleration
```bash
glxinfo | grep "direct rendering"     # Should say "yes"
glxinfo | grep "OpenGL renderer"      # Should show NVIDIA
vblank_mode=0 glxgears               # Uncapped FPS test
```

## File Locations

### Configuration Files
```bash
/etc/X11/xorg.conf                    # Main X config (optional)
/etc/X11/xorg.conf.d/                 # Modular X configs
/etc/modprobe.d/blacklist-nouveau.conf # Nouveau blacklist
/etc/modprobe.d/blacklist-intel.conf   # Intel blacklist (dual-GPU)
/etc/default/grub                      # GRUB configuration
/etc/environment                       # Wayland env vars (GBM_BACKEND etc.)
/etc/sddm.conf.d/10-wayland.conf      # SDDM Wayland config
```

### Log Files
```bash
/var/log/Xorg.0.log                   # X server log
/var/log/kern.log                     # Kernel log (Debian)
/var/log/syslog                       # System log
~/.local/share/xorg/Xorg.0.log       # User X log
```

### Driver Files
```bash
/usr/lib/xorg/modules/drivers/nvidia_drv.so  # NVIDIA X driver
/lib/modules/$(uname -r)/kernel/drivers/video/nvidia*.ko  # Kernel modules
```

## Recovery Commands

### Boot to Recovery Mode
```bash
# During GRUB menu:
# 1. Select "Advanced options"
# 2. Select "Recovery mode"
# 3. Select "Root shell with networking"
```

### Boot with Safe Graphics
```bash
# At GRUB, press 'e' to edit
# Add to linux line: nomodeset
# Press Ctrl+X to boot
```

### Chroot from Live USB
```bash
sudo mount /dev/sdXY /mnt             # Mount root partition
sudo mount --bind /dev /mnt/dev
sudo mount --bind /proc /mnt/proc
sudo mount --bind /sys /mnt/sys
sudo chroot /mnt
# Fix issues here
exit
sudo umount -R /mnt
sudo reboot
```

## Useful Aliases (Add to ~/.bashrc)

```bash
alias nv-check='nvidia-smi && echo "NVIDIA OK" || echo "NVIDIA FAILED"'
alias nv-status='lsmod | grep nvidia && echo "Module loaded" || echo "Module not loaded"'
alias nv-logs='dmesg | grep -i nvidia | tail -20'
alias nv-session='echo "Session: $XDG_SESSION_TYPE | Display: ${WAYLAND_DISPLAY:-$DISPLAY}"'
alias dm-status='systemctl status display-manager'
alias dm-restart='sudo systemctl restart display-manager'
```

## Kernel Parameters Reference

### Common Parameters
```bash
nvidia-drm.modeset=1      # Enable NVIDIA DRM kernel modesetting (REQUIRED for Wayland)
nvidia-drm.modeset=0      # Disable NVIDIA DRM kernel modesetting
nomodeset                 # Disable kernel modesetting (safe mode)
nouveau.modeset=0         # Disable nouveau modesetting
acpi=off                  # Disable ACPI (last resort)
noapic                    # Disable APIC
```

### Add Kernel Parameters Temporarily
```bash
# At GRUB menu, press 'e'
# Find line starting with 'linux'
# Add parameters at end
# Press Ctrl+X to boot
```

### Add Kernel Parameters Permanently
```bash
sudo nano /etc/default/grub
# Modify: GRUB_CMDLINE_LINUX_DEFAULT="quiet splash YOUR_PARAMS"
sudo update-grub
sudo reboot
```

## One-Liner Checks

```bash
# Quick system overview
echo "GPU: $(lspci | grep VGA)" && echo "NVIDIA Loaded: $(lsmod | grep -q nvidia && echo Yes || echo No)" && echo "Driver Version: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null || echo Not installed)" && echo "Session: ${XDG_SESSION_TYPE:-unknown}"

# Check for conflicts
(lsmod | grep nouveau && echo "WARNING: Nouveau is loaded!") || echo "Nouveau: OK (not loaded)"

# Display manager check
echo "Display Manager: $(systemctl is-active display-manager)"

# Full diagnostic one-liner
echo "=== Quick Diagnostic ===" && lspci | grep VGA && echo && lsmod | grep -E "nvidia|nouveau" && echo && nvidia-smi 2>/dev/null && echo && echo "Session: $XDG_SESSION_TYPE" && systemctl status display-manager --no-pager | head -3
```

## Quick Fixes Cheatsheet

| Problem | Command |
|---------|---------|
| Black screen (X11) | `Ctrl+Alt+F2` then `sudo systemctl restart display-manager` |
| Black screen (Wayland) | `Ctrl+Alt+F2` then check `journalctl -b \| grep kwin_wayland` |
| Nouveau conflict | `sudo rmmod nouveau && sudo modprobe nvidia` |
| Missing nvidia-smi | `sudo apt install nvidia-utils` |
| X won't start | `sudo nvidia-xconfig && sudo systemctl restart display-manager` |
| After kernel update | `sudo apt install linux-headers-$(uname -r)` |
| Wayland env vars missing | Check `/etc/environment` for GBM_BACKEND and __GLX_VENDOR_LIBRARY_NAME |
| Wrong GPU on dual-GPU | Check xorg.conf BusID (X11) or blacklist i915 (Wayland) |

## Performance Tuning

```bash
# Check current power state
nvidia-smi -q -d POWER

# Set persistence mode
sudo nvidia-smi -pm 1

# Set power limit (example: 75W)
sudo nvidia-smi -pl 75

# Check GPU utilization
watch -n 1 nvidia-smi
```

---

**Pro Tips**:
- Always `sudo update-initramfs -u` after config changes
- Test with `sudo systemctl restart display-manager` before rebooting
- Keep a live USB handy
- `nvidia-drm.modeset=1` is required for Wayland — always set it
- Document what works for YOUR specific setup
