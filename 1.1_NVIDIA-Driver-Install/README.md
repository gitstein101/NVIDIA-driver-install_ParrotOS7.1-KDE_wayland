# NVIDIA Driver Installation Project

## Overview
Comprehensive guide for installing and troubleshooting NVIDIA drivers on Linux systems, with focus on security-focused distributions and resolving common compatibility issues.

## Target Hardware
- **GPU**: NVIDIA GT 1030
- **Architecture**: Supports legacy and current driver branches
- **Common Issues**: Display manager conflicts, ACPI errors, boot failures

## Supported Distributions
- Parrot OS 7 (Debian-based)
- BlackArch Linux (Arch-based)
- Kali Linux (Debian-based)
- Standard Debian/Ubuntu derivatives

## Known Issues Database

### Issue 1: GUI Boot Failure After Driver Installation
**Symptoms**:
- Black screen on boot
- TTY accessible (Ctrl+Alt+F2-F6)
- Display manager fails to start
- X server configuration errors

**Common Causes**:
- Nouveau driver conflicts
- Incorrect driver version for GPU architecture
- Display manager configuration issues
- Missing kernel modules

### Issue 2: ACPI Communication Errors
**Symptoms**:
- ACPI BIOS errors during boot
- GPU not properly detected
- Power management failures

**Root Causes**:
- Kernel parameter conflicts
- BIOS compatibility issues
- Driver-kernel version mismatch

### Issue 3: GRUB/Bootloader Problems
**Symptoms**:
- GRUB menu doesn't appear
- Boot loops
- Cannot access recovery mode

**Related to**:
- Incorrect GRUB configuration after driver install
- Missing fallback kernel entries

## Installation Methods

### Method 1: Package Manager (Recommended)
**For Debian/Parrot/Kali**:
```bash
# Update system
sudo apt update && sudo apt upgrade

# Remove any existing NVIDIA packages
sudo apt remove --purge '^nvidia-.*'
sudo apt remove --purge '^libnvidia-.*'

# Check GPU and recommended driver
ubuntu-drivers devices
# OR
nvidia-detect

# Install recommended driver
sudo apt install nvidia-driver nvidia-settings

# Reboot
sudo reboot
```

**For Arch/BlackArch**:
```bash
# Update system
sudo pacman -Syu

# Remove nouveau (if present)
sudo pacman -R xf86-video-nouveau

# Install NVIDIA driver
sudo pacman -S nvidia nvidia-utils nvidia-settings

# Regenerate initramfs
sudo mkinitcpio -P

# Reboot
sudo reboot
```

### Method 2: Official NVIDIA .run Installer
**When to use**: Package manager method fails, or need specific driver version

```bash
# Download driver from nvidia.com
# Stop display manager
sudo systemctl stop lightdm  # or gdm, sddm, etc.

# Make installer executable
chmod +x NVIDIA-Linux-*.run

# Run installer
sudo ./NVIDIA-Linux-*.run

# Reboot
sudo reboot
```

### Method 3: DKMS (Dynamic Kernel Module Support)
**Best for**: Systems with frequent kernel updates

```bash
# Install DKMS packages
sudo apt install nvidia-driver nvidia-dkms

# DKMS will automatically rebuild modules on kernel updates
```

## Pre-Installation Checklist

1. **Backup Current System**
   - Create system snapshot if using Timeshift/Snapper
   - Note current working configuration

2. **Identify GPU Model**
   ```bash
   lspci -k | grep -A 2 -E "(VGA|3D)"
   ```

3. **Check Current Driver**
   ```bash
   lsmod | grep -E "nvidia|nouveau"
   ```

4. **Verify Kernel Version**
   ```bash
   uname -r
   ```

5. **Document Display Manager**
   ```bash
   systemctl status display-manager
   ```

## Nouveau Blacklisting

Create/edit blacklist configuration:

```bash
sudo nano /etc/modprobe.d/blacklist-nouveau.conf
```

Add:
```
blacklist nouveau
options nouveau modeset=0
```

Update initramfs:
```bash
# Debian/Ubuntu/Parrot/Kali
sudo update-initramfs -u

# Arch/BlackArch
sudo mkinitcpio -P
```

## Recovery Procedures

### Recovery Method 1: TTY Access
1. Boot to TTY (Ctrl+Alt+F2)
2. Login with credentials
3. Remove problematic drivers:
   ```bash
   sudo apt remove --purge nvidia-*
   # OR
   sudo pacman -R nvidia nvidia-utils
   ```
4. Reinstall display manager if needed
5. Reboot

### Recovery Method 2: Recovery Mode
1. Access GRUB menu (hold Shift during boot)
2. Select "Advanced options"
3. Choose "Recovery mode"
4. Select "Root shell with networking"
5. Execute recovery commands
6. Reboot

### Recovery Method 3: Chroot from Live USB
1. Boot from live USB
2. Mount root partition:
   ```bash
   sudo mount /dev/sdXY /mnt
   sudo mount --bind /dev /mnt/dev
   sudo mount --bind /proc /mnt/proc
   sudo mount --bind /sys /mnt/sys
   sudo chroot /mnt
   ```
3. Fix driver issues
4. Exit and reboot

## Display Manager Specific Issues

### LightDM
**Config**: `/etc/lightdm/lightdm.conf`

Common fix:
```bash
sudo systemctl restart lightdm
# If fails, check logs:
journalctl -u lightdm -b
```

### GDM (GNOME)
**Config**: `/etc/gdm3/daemon.conf`

Wayland conflicts:
```bash
# Disable Wayland temporarily
sudo nano /etc/gdm3/daemon.conf
# Uncomment: WaylandEnable=false
```

### SDDM (KDE Plasma)
**Config**: `/etc/sddm.conf`

Common issue on Parrot OS 7:
```bash
sudo systemctl status sddm
# Check configuration
sddm --example-config
```

### XDM (Minimal)
Fallback option:
```bash
sudo apt install xdm
sudo systemctl enable xdm
sudo systemctl start xdm
```

## Kernel Parameters

### Useful Boot Parameters
Add to GRUB command line or `/etc/default/grub`:

```bash
# Disable nouveau at boot
nouveau.modeset=0

# NVIDIA DRM
nvidia-drm.modeset=1

# ACPI fixes
acpi=off          # Disable ACPI (last resort)
nomodeset         # Disable kernel mode setting
noapic            # Disable APIC
```

Edit GRUB config:
```bash
sudo nano /etc/default/grub
# Add to GRUB_CMDLINE_LINUX_DEFAULT
sudo update-grub
```

## X Server Configuration

### Generate xorg.conf
```bash
sudo nvidia-xconfig
```

### Manual X Configuration
Create `/etc/X11/xorg.conf.d/20-nvidia.conf`:

```
Section "Device"
    Identifier     "NVIDIA Graphics"
    Driver         "nvidia"
    VendorName     "NVIDIA Corporation"
    BoardName      "GeForce GT 1030"
EndSection
```

## Verification Commands

### After Installation
```bash
# Check driver loaded
nvidia-smi

# Verify module
lsmod | grep nvidia

# Check X driver
glxinfo | grep "OpenGL renderer"

# Test OpenGL
glxgears
```

## Troubleshooting Decision Tree

```
Boot Issue?
├── Black screen, no TTY → GRUB issue/kernel panic
│   └── Solution: Boot from live USB, chroot, fix GRUB
├── Black screen, TTY accessible → Driver/X server issue
│   └── Solution: TTY login, check display manager
└── GUI crashes after login → Display manager conflict
    └── Solution: Switch display manager, check Wayland
```

## Distribution-Specific Notes

### Parrot OS 7
- Debian 12 base
- KDE Plasma default
- SDDM display manager
- Known ACPI issues with NVIDIA
- Recommend: nvidia-driver package from repos

### BlackArch Linux
- Arch Linux base
- Multiple DE options
- Various display managers
- Rolling release = frequent kernel updates
- Recommend: nvidia-dkms for auto-rebuilds

### Kali Linux
- Debian-based
- Multiple DE options
- XFCE default uses LightDM
- Generally good NVIDIA support
- Recommend: nvidia-driver from repos

## Best Practices

1. **Always update system first**
2. **Use package manager when possible**
3. **Blacklist nouveau before installing NVIDIA**
4. **Keep kernel headers installed**
5. **Document working configuration**
6. **Have recovery plan ready**
7. **Test in TTY before rebooting**
8. **Monitor system logs during installation**

## Common Log Locations

```bash
# System logs
journalctl -b              # Current boot
journalctl -b -1           # Previous boot

# X server logs
cat /var/log/Xorg.0.log

# Display manager logs
journalctl -u lightdm
journalctl -u gdm
journalctl -u sddm

# Kernel messages
dmesg | grep -i nvidia
dmesg | grep -i nouveau
```

## Emergency Contacts & Resources

- NVIDIA Linux Driver Download: https://www.nvidia.com/en-us/drivers/unix/
- Arch Wiki NVIDIA: https://wiki.archlinux.org/title/NVIDIA
- Debian Wiki NVIDIA: https://wiki.debian.org/NvidiaGraphicsDrivers
- Ubuntu NVIDIA Guide: https://help.ubuntu.com/community/BinaryDriverHowto/Nvidia

## Script Collection

Scripts are stored in the `/scripts` directory:
- `nvidia-install.sh` - Automated installation
- `nvidia-remove.sh` - Complete removal
- `nvidia-diagnose.sh` - Diagnostic tool
- `recovery-boot.sh` - Emergency recovery

## Testing Checklist

After installation, verify:
- [ ] System boots to GUI
- [ ] `nvidia-smi` shows GPU info
- [ ] `glxinfo` shows NVIDIA renderer
- [ ] `glxgears` runs smoothly
- [ ] Display manager stable
- [ ] Multiple reboots successful
- [ ] Suspend/resume works (if applicable)

## Version History

- v1.0 - Initial documentation based on real-world troubleshooting experience
- Focus: GT 1030 on security distributions
- Primary issues addressed: Boot failures, display manager conflicts, ACPI errors

---

**Note**: This documentation is based on practical experience with NVIDIA GT 1030 on Parrot OS 7, BlackArch Linux, and related distributions. Your specific hardware and software configuration may require adjustments.
