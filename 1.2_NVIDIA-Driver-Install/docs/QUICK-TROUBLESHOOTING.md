# NVIDIA Driver Quick Troubleshooting Guide

## Emergency Recovery (Black Screen)

### Option 1: TTY Access (FASTEST)
1. Press `Ctrl+Alt+F2` (or F3-F6)
2. Login with your credentials
3. Remove driver:
   ```bash
   sudo apt remove --purge nvidia-*
   # OR
   sudo pacman -R nvidia nvidia-utils
   ```
4. Reboot: `sudo reboot`

### Option 2: Recovery Mode
1. Boot menu: Hold `Shift` during startup
2. Select "Advanced options"
3. Choose "Recovery mode"
4. Select "Root shell with networking"
5. Run removal commands
6. Reboot

### Option 3: Live USB Chroot
```bash
# Boot from live USB
sudo mount /dev/sdXY /mnt
sudo mount --bind /dev /mnt/dev
sudo mount --bind /proc /mnt/proc
sudo mount --bind /sys /mnt/sys
sudo chroot /mnt
# Run fixes here
exit
sudo reboot
```

## Common Issues & Quick Fixes

### Issue: Black screen on boot, TTY accessible (X11)
**Cause**: Display manager or X server misconfigured
```bash
# Check display manager status
sudo systemctl status display-manager

# Restart it
sudo systemctl restart lightdm  # or gdm, sddm

# Check X server log
cat /var/log/Xorg.0.log | grep "(EE)"
```

### Issue: Wayland Black Screen
**Cause**: Wayland compositor fails to start (different from X11 — no Xorg.0.log)

```bash
# From TTY (Ctrl+Alt+F2):

# Check kwin_wayland / compositor logs
journalctl -b | grep kwin_wayland

# Check DRM/GBM errors
journalctl -b | grep -i "drm\|gbm\|nvidia"

# Check SDDM logs
journalctl -u sddm -b

# Common fixes:
# 1. Ensure nvidia-drm.modeset=1 is in GRUB
grep nvidia-drm /etc/default/grub

# 2. Ensure environment variables are set
grep -E "GBM_BACKEND|__GLX_VENDOR" /etc/environment

# 3. Ensure EGL-Wayland library is installed
dpkg -l | grep egl-wayland   # Debian
pacman -Q egl-wayland        # Arch

# 4. Fall back to X11 session temporarily
# Edit /etc/sddm.conf.d/10-wayland.conf and set DisplayServer=x11
# Or remove the file entirely
sudo rm /etc/sddm.conf.d/10-wayland.conf
sudo systemctl restart display-manager
```

### Issue: Dual-GPU Display Routing (Wrong GPU Active)
**Symptom**: Monitor connected to NVIDIA card but display routes through Intel iGPU

**For X11 sessions**:
```bash
# Check which providers are active
xrandr --listproviders

# Route output through NVIDIA
xrandr --setprovideroutputsource modesetting NVIDIA-0
xrandr --auto

# Permanent fix: Run nvidia-install.sh with dual-GPU support
# It creates /etc/X11/xorg.conf with NVIDIA BusID
```

**For Wayland sessions**:
```bash
# Check which GPU is primary DRM device
cat /sys/class/drm/card0/device/vendor
# 0x10de = NVIDIA (good), 0x8086 = Intel (wrong GPU)

# If Intel is primary, blacklist it:
echo "blacklist i915" | sudo tee /etc/modprobe.d/blacklist-intel.conf
sudo update-initramfs -u
sudo reboot
```

### Issue: Nouveau conflicts
**Symptom**: NVIDIA and nouveau both trying to load
```bash
# Blacklist nouveau
sudo nano /etc/modprobe.d/blacklist-nouveau.conf

# Add these lines:
blacklist nouveau
options nouveau modeset=0

# Update initramfs
sudo update-initramfs -u  # Debian/Ubuntu
sudo mkinitcpio -P        # Arch

# Reboot
sudo reboot
```

### Issue: NVIDIA module won't load
```bash
# Check if it's blacklisted
grep nvidia /etc/modprobe.d/*

# Check dmesg for errors
dmesg | grep -i nvidia

# Manually load module
sudo modprobe nvidia
```

### Issue: nvidia-smi: command not found
**Cause**: nvidia-utils not installed
```bash
# Debian/Ubuntu
sudo apt install nvidia-utils

# Arch
sudo pacman -S nvidia-utils
```

### Issue: Display manager won't start
```bash
# Check which DM is enabled
systemctl list-unit-files | grep -E "lightdm|gdm|sddm"

# Enable a different one
sudo systemctl disable sddm
sudo systemctl enable lightdm
sudo systemctl start lightdm
```

### Issue: GRUB menu doesn't appear
```bash
# Edit GRUB timeout
sudo nano /etc/default/grub
# Change: GRUB_TIMEOUT=5
# Change: GRUB_TIMEOUT_STYLE=menu

sudo update-grub
```

### Issue: Kernel update broke driver
**Symptom**: Works until kernel updates, then breaks
**Solution**: Use DKMS
```bash
# Debian/Ubuntu
sudo apt install nvidia-dkms

# Arch
sudo pacman -S nvidia-dkms
```

### Issue: Performance issues / Screen tearing (X11)
```bash
# Add to /etc/X11/xorg.conf.d/20-nvidia.conf
Section "Device"
    Identifier     "NVIDIA Card"
    Driver         "nvidia"
    Option         "TripleBuffer" "True"
    Option         "metamodes" "nvidia-auto-select +0+0 {ForceFullCompositionPipeline=On}"
EndSection
```

### Issue: Screen tearing (Wayland)
```bash
# Verify modeset is enabled
cat /sys/module/nvidia_drm/parameters/modeset
# Should output: Y

# If not, add to GRUB and reboot
sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="nvidia-drm.modeset=1 /' /etc/default/grub
sudo update-grub
sudo reboot
```

### Issue: Cursor invisible or corrupted (Wayland)
```bash
# For wlroots-based compositors (Sway, Hyprland)
echo "WLR_NO_HARDWARE_CURSORS=1" | sudo tee -a /etc/environment
# Then log out and back in
```

## Distribution-Specific Quick Fixes

### Parrot OS 7 / Kali Linux
```bash
# Recommended method
sudo apt update
sudo apt install nvidia-driver nvidia-settings
sudo reboot
```

### BlackArch Linux
```bash
# Install with DKMS for rolling release
sudo pacman -S nvidia-dkms nvidia-utils nvidia-settings
sudo mkinitcpio -P
sudo reboot
```

### Ubuntu / Debian
```bash
# Use driver manager
sudo ubuntu-drivers autoinstall
# OR
sudo apt install nvidia-driver-535  # or latest version
```

## Verification Commands

### X11 Session
```bash
lspci | grep -i vga                   # Check GPU detected
lsmod | grep nvidia                   # Check driver loaded
nvidia-smi                            # Check NVIDIA working
glxinfo | grep "OpenGL renderer"      # Check OpenGL
glxgears                              # Test 3D
xrandr --listproviders                # Check display providers
```

### Wayland Session
```bash
echo $XDG_SESSION_TYPE                 # Should say "wayland"
nvidia-smi                            # Check NVIDIA working
eglinfo | head -20                     # Check EGL
wayland-info                           # Check compositor
kscreen-doctor --outputs               # KDE display info
```

### Both Sessions
```bash
lsmod | grep nvidia                    # NVIDIA modules loaded
cat /sys/module/nvidia_drm/parameters/modeset  # Modeset enabled
```

## Log Files to Check

### X11 Issues
```bash
grep "(EE)" /var/log/Xorg.0.log       # X server errors
journalctl -u sddm -b                 # SDDM logs
dmesg | grep -i nvidia                 # Kernel messages
```

### Wayland Issues
```bash
journalctl -b | grep kwin_wayland     # KWin compositor logs
journalctl -b | grep -i "drm\|gbm"   # DRM/GBM errors
journalctl -u sddm -b                 # SDDM logs
dmesg | grep -i nvidia                 # Kernel messages
```

## ACPI Errors (Parrot OS 7 Common)

If you see ACPI errors:
```bash
# Add to GRUB_CMDLINE_LINUX_DEFAULT in /etc/default/grub
acpi=off        # Last resort only
noapic          # Disable APIC
nomodeset       # Disable KMS

# Update GRUB
sudo update-grub
```

## Quick Decision Tree

```
GPU not working?
├─ What session type?
│  ├─ X11
│  │  ├─ Check /var/log/Xorg.0.log
│  │  ├─ Check xrandr --listproviders
│  │  └─ Dual-GPU? Check xorg.conf BusID
│  └─ Wayland
│     ├─ Check journalctl -b | grep kwin_wayland
│     ├─ Check nvidia-drm.modeset=1 in boot params
│     ├─ Check /etc/environment for GBM_BACKEND
│     └─ Dual-GPU? Check /sys/class/drm/card0/device/vendor
├─ Can access TTY?
│  ├─ Yes → Remove driver from TTY
│  └─ No → Boot recovery mode
├─ Display manager running?
│  ├─ No → Start/restart display-manager
│  └─ Yes → Check session-specific logs (see above)
├─ Nouveau loaded?
│  └─ Yes → Blacklist nouveau
└─ After kernel update?
   └─ Install nvidia-dkms
```

## Before You Reinstall

Try these first:
1. `sudo nvidia-xconfig` — Regenerate X config (X11 only)
2. Check `/etc/environment` for correct Wayland vars
3. Switch display managers (LightDM usually most reliable)
4. Boot with `nomodeset` to get to desktop, then fix
5. Check session-specific logs (Xorg.0.log for X11, journalctl for Wayland)
6. Verify kernel headers installed: `dpkg -l | grep linux-headers`

## Safe Testing Procedure

```bash
# Don't reboot blindly, test first:
sudo systemctl restart display-manager

# If that works, then reboot
# If it fails, you're still in TTY and can fix it
```

## Nuclear Option (Complete Reset)

```bash
# Remove everything NVIDIA
sudo apt remove --purge '^nvidia-.*' '^libnvidia-.*'
sudo apt autoremove
rm -rf ~/.nvidia* ~/.cache/nvidia
sudo rm -f /etc/X11/xorg.conf
sudo rm -f /etc/X11/xorg.conf.d/*nvidia*
sudo rm -f /etc/modprobe.d/*nvidia*
sudo rm -f /etc/modprobe.d/blacklist-intel.conf
sudo rm -f /etc/sddm.conf.d/10-wayland.conf
sudo sed -i '/^GBM_BACKEND=/d' /etc/environment
sudo sed -i '/^__GLX_VENDOR_LIBRARY_NAME=/d' /etc/environment

# Remove dual-GPU service
sudo systemctl disable nvidia-primary 2>/dev/null
sudo rm -f /etc/systemd/system/nvidia-primary.service
sudo rm -f /usr/local/bin/nvidia-primary.sh

# Start fresh
sudo reboot
```

## When to Use Each Method

| Symptom | Method |
|---------|--------|
| Black screen, can access TTY | TTY removal + reinstall |
| Black screen, no TTY | Recovery mode or Live USB |
| Boots but crashes on login | Display manager issue |
| Nouveau conflicts | Blacklist nouveau |
| Works then breaks after update | Install DKMS version |
| Performance issues (X11) | Configure X server |
| Performance issues (Wayland) | Check nvidia-drm.modeset |
| ACPI errors | Add kernel parameters |
| Wrong GPU active (dual-GPU) | Configure BusID (X11) or blacklist i915 (Wayland) |
| Wayland black screen | Check env vars + journalctl |

## Remember

- **Always have a backup plan** (Live USB ready)
- **Test before rebooting** (restart display-manager first)
- **Check logs** before asking for help
- **Document what works** for your specific setup
- **Keep kernel headers updated**
- **DKMS is your friend** on rolling release
- **nvidia-drm.modeset=1** is required for Wayland

---

**Pro Tip**: Before ANY driver change:
```bash
sudo systemctl set-default multi-user.target
```
This prevents auto-starting GUI. Then after successful install:
```bash
sudo systemctl set-default graphical.target
```
