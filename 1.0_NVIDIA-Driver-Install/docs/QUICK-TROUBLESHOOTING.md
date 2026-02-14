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

### Issue: Black screen on boot, TTY accessible
**Cause**: Display manager or X server misconfigured
```bash
# Check display manager status
sudo systemctl status display-manager

# Restart it
sudo systemctl restart lightdm  # or gdm, sddm

# Check X server log
cat /var/log/Xorg.0.log | grep "(EE)"
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

### Issue: Performance issues / Screen tearing
```bash
# Add to /etc/X11/xorg.conf.d/20-nvidia.conf
Section "Device"
    Identifier     "NVIDIA Card"
    Driver         "nvidia"
    Option         "TripleBuffer" "True"
    Option         "metamodes" "nvidia-auto-select +0+0 {ForceFullCompositionPipeline=On}"
EndSection
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

```bash
# Check GPU detected
lspci | grep -i vga

# Check driver loaded
lsmod | grep nvidia

# Check NVIDIA working
nvidia-smi

# Check OpenGL
glxinfo | grep "OpenGL renderer"

# Test 3D
glxgears
```

## Log Files to Check

```bash
# System journal
journalctl -b | grep -i nvidia

# X server errors
grep "(EE)" /var/log/Xorg.0.log

# Kernel messages
dmesg | grep -i nvidia

# Display manager logs
journalctl -u lightdm  # or gdm, sddm
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

## One-Liner Checks

```bash
# Quick status check
nvidia-smi && echo "NVIDIA OK" || echo "NVIDIA FAILED"

# Check what's using the GPU
lsmod | grep -E "nvidia|nouveau"

# See which driver Xorg is using
grep "Driver" /var/log/Xorg.0.log | grep -i "nvidia\|nouveau"

# Check if display manager is running
systemctl is-active display-manager
```

## Before You Reinstall

Try these first:
1. `sudo nvidia-xconfig` - Regenerate X config
2. Switch display managers (LightDM usually most reliable)
3. Boot with `nomodeset` to get to desktop, then fix
4. Check `/var/log/Xorg.0.log` for actual error
5. Verify kernel headers installed: `dpkg -l | grep linux-headers`

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
| Performance issues | Configure X server |
| ACPI errors | Add kernel parameters |

## Emergency Contact Script

Save as `/usr/local/bin/nvidia-emergency`:
```bash
#!/bin/bash
sudo systemctl stop display-manager
sudo apt remove --purge nvidia-*
sudo update-initramfs -u
echo "NVIDIA removed. Reboot to use nouveau fallback."
```

## Remember

- **Always have a backup plan** (Live USB ready)
- **Test before rebooting** (restart display-manager first)
- **Check logs** before asking for help
- **Document what works** for your specific setup
- **Keep kernel headers updated**
- **DKMS is your friend** on rolling release

## Quick Decision Tree

```
GPU not working?
├─ Can access TTY? 
│  ├─ Yes → Remove driver from TTY
│  └─ No → Boot recovery mode
├─ Display manager running?
│  ├─ No → Start/restart display-manager
│  └─ Yes → Check X server logs
├─ Nouveau loaded?
│  └─ Yes → Blacklist nouveau
└─ After kernel update?
   └─ Install nvidia-dkms
```

---

**Pro Tip**: Before ANY driver change:
```bash
sudo systemctl set-default multi-user.target
```
This prevents auto-starting GUI. Then after successful install:
```bash
sudo systemctl set-default graphical.target
```
