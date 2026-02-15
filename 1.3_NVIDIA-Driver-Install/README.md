# NVIDIA Driver Installation Project v1.3

## Overview
Comprehensive toolkit for installing and troubleshooting NVIDIA drivers on Linux systems, with focus on security-focused distributions. Version 1.3 adds **LightDM support**, **dpkg broken-package repair**, and **improved error handling**.

## What's New in v1.3

- **LightDM Support**: Auto-detects active display manager (SDDM, LightDM, GDM) and configures each appropriately. Creates NVIDIA display setup script for LightDM.
- **dpkg Repair**: Automatically detects and repairs broken dpkg package state before installing prerequisites, with essential-package protection.
- **Improved Error Handling**: Kernel header install failures now prompt the user instead of aborting. Better fallback behavior throughout.
- **Multi-DM Awareness**: Installer configures all installed display managers, not just the active one, for easier switching.

## Target Hardware
- **GPU**: NVIDIA GPUs (tested with GeForce GT 1030, GP108 architecture)
- **Architecture**: Supports legacy and current driver branches
- **Common Issues**: Display manager conflicts, ACPI errors, boot failures, dual-GPU routing

## Supported Distributions
- Parrot OS 7 (Debian 12 base, KDE Plasma, SDDM)
- BlackArch Linux (Arch-based, rolling release)
- Kali Linux (Debian Testing base)
- Standard Debian/Ubuntu derivatives

## Project Structure

```
1.3_NVIDIA-Driver-Install/
├── README.md                          # This file
├── GETTING-STARTED.md                 # Quick start guide
├── scripts/
│   ├── nvidia-install.sh              # Automated install (X11/Wayland/Both + dual-GPU)
│   ├── nvidia-remove.sh               # Complete removal with Wayland cleanup
│   └── nvidia-diagnose.sh             # Session-aware diagnostic tool
├── docs/
│   ├── WAYLAND-SUPPORT.md             # Wayland setup and troubleshooting
│   ├── COMMAND-CHEATSHEET.md          # All commands in one place
│   ├── QUICK-TROUBLESHOOTING.md       # Emergency fixes (X11 + Wayland)
│   └── DISTRO-SPECIFIC-NOTES.md       # Per-distro guidance
└── examples/
    ├── environment.example             # Wayland env vars (GBM_BACKEND etc.)
    ├── sddm-wayland.conf.example       # SDDM Wayland session config
    ├── xorg.conf.example               # X server config (with dual-GPU BusID)
    ├── grub.example                    # GRUB configuration
    ├── blacklist-nouveau.conf          # Nouveau blacklist
    └── mkinitcpio.conf.example         # Arch initramfs config
```

## Quick Start

### Automated Installation
```bash
cd 1.3_NVIDIA-Driver-Install
sudo ./scripts/nvidia-install.sh
```

The installer will:
1. Detect your GPU (and check for dual-GPU)
2. Ask you to choose: **X11**, **Wayland**, or **Both**
3. Install the driver and configure your chosen session
4. Handle dual-GPU routing automatically (if applicable)

### Quick Diagnostic
```bash
sudo ./scripts/nvidia-diagnose.sh
```

### Emergency Removal
```bash
sudo ./scripts/nvidia-remove.sh
```

## Installation Methods

### Method 1: Automated Script (Recommended)
```bash
sudo ./scripts/nvidia-install.sh
```

### Method 2: Package Manager (Manual)

**Debian/Parrot/Kali**:
```bash
sudo apt update && sudo apt upgrade
sudo apt remove --purge '^nvidia-.*'
sudo apt install nvidia-driver nvidia-settings
sudo reboot
```

**Arch/BlackArch**:
```bash
sudo pacman -Syu
sudo pacman -S nvidia-dkms nvidia-utils nvidia-settings
sudo mkinitcpio -P
sudo reboot
```

### Method 3: Official NVIDIA .run Installer
```bash
sudo systemctl stop display-manager
chmod +x NVIDIA-Linux-*.run
sudo ./NVIDIA-Linux-*.run
sudo reboot
```

## Wayland vs X11

| Feature | X11 | Wayland |
|---------|-----|---------|
| Compatibility | Maximum | Growing (most apps work) |
| Configuration | xorg.conf, xrandr | Environment vars, DRM |
| Dual-GPU | xorg.conf BusID | Kernel DRM handles it |
| Screen tearing | Needs ForceFullCompositionPipeline | None by design |
| Screen recording | Mature tools | PipeWire-based |
| KDE Plasma | Full support | Full support (5.25+) |
| Requirement | nvidia-drm.modeset=1 recommended | nvidia-drm.modeset=1 required |

See `docs/WAYLAND-SUPPORT.md` for detailed Wayland guidance.

## Dual-GPU Support

If your system has both an Intel iGPU and NVIDIA dGPU (common in desktops where the monitor connects to the NVIDIA card), the installer:

- **X11**: Creates `/etc/X11/xorg.conf` with the NVIDIA BusID, sets up an xrandr provider service
- **Wayland**: Relies on `nvidia-drm.modeset=1` for DRM-level GPU selection (no xorg.conf needed)
- **Optional**: Can blacklist Intel i915 to force NVIDIA-only operation

## Verification Commands

### After Installation
```bash
# Common (both sessions)
nvidia-smi
lsmod | grep nvidia

# X11 session
glxinfo | grep "OpenGL renderer"
xrandr --listproviders

# Wayland session
echo $XDG_SESSION_TYPE      # should say "wayland"
eglinfo | head -20
wayland-info
```

## Troubleshooting Decision Tree

```
Boot Issue?
├── What session type?
│   ├── X11 → Check /var/log/Xorg.0.log
│   └── Wayland → Check journalctl -b | grep kwin_wayland
├── Black screen, no TTY → GRUB issue/kernel panic
│   └── Solution: Boot from live USB, chroot, fix GRUB
├── Black screen, TTY accessible → Driver/compositor issue
│   └── Solution: TTY login, check display manager + session logs
├── GUI crashes after login → Display manager conflict
│   └── Solution: Switch display manager or session type
└── Dual-GPU wrong output → Display routing issue
    ├── X11: Check xorg.conf BusID
    └── Wayland: Check /sys/class/drm/card0/device/vendor
```

## Known Issues Database

### Issue 1: GUI Boot Failure After Driver Installation
- Black screen on boot, TTY accessible
- Check display manager status and X/Wayland logs
- See `docs/QUICK-TROUBLESHOOTING.md`

### Issue 2: ACPI Communication Errors
- Common on Parrot OS 7
- Fix: Add `noapic` or `acpi=off` to GRUB
- See `examples/grub.example`

### Issue 3: Wayland Session Won't Start
- Missing `nvidia-drm.modeset=1` in GRUB
- Missing `GBM_BACKEND=nvidia-drm` in `/etc/environment`
- Missing `libnvidia-egl-wayland1` package
- See `docs/WAYLAND-SUPPORT.md`

### Issue 4: Dual-GPU Wrong Display Output
- Monitor connected to NVIDIA but display routes through Intel
- X11: Need xorg.conf with BusID
- Wayland: May need to blacklist i915
- See `docs/QUICK-TROUBLESHOOTING.md`

## Recovery Procedures

### Recovery Method 1: TTY Access
1. Boot to TTY (Ctrl+Alt+F2)
2. Login with credentials
3. Run: `sudo ./scripts/nvidia-remove.sh`
4. Reboot

### Recovery Method 2: Recovery Mode
1. Access GRUB menu (hold Shift during boot)
2. Select "Advanced options" > "Recovery mode"
3. Select "Root shell with networking"
4. Execute recovery commands

### Recovery Method 3: Chroot from Live USB
```bash
sudo mount /dev/sdXY /mnt
sudo mount --bind /dev /mnt/dev
sudo mount --bind /proc /mnt/proc
sudo mount --bind /sys /mnt/sys
sudo chroot /mnt
# Fix driver issues
exit && sudo reboot
```

## Best Practices

1. Always update system first
2. Use package manager when possible
3. Blacklist nouveau before installing NVIDIA
4. Keep kernel headers installed
5. Set `nvidia-drm.modeset=1` in GRUB (required for Wayland, recommended for X11)
6. Document working configuration
7. Have recovery plan ready (live USB)
8. Test with `systemctl restart display-manager` before rebooting

## Version History

- **v1.3** - LightDM support, dpkg repair, multi-DM awareness, improved error handling
- **v1.2** - Wayland session support, integrated dual-GPU handling, session-aware diagnostics
- **v1.1** - Improved X server configuration with fallback
- **v1.1b** - Standalone dual-GPU fix script (merged into v1.2)
- **v1.0** - Initial documentation and scripts

## Resources

- [Arch Wiki: NVIDIA](https://wiki.archlinux.org/title/NVIDIA)
- [Debian Wiki: NVIDIA](https://wiki.debian.org/NvidiaGraphicsDrivers)
- [NVIDIA Unix Drivers](https://www.nvidia.com/en-us/drivers/unix/)
- [KDE Plasma Wayland](https://community.kde.org/Plasma/Wayland)

---

**Note**: This toolkit is based on practical experience with NVIDIA GT 1030 on Parrot OS 7, BlackArch Linux, and related distributions. Your specific hardware and software configuration may require adjustments.
