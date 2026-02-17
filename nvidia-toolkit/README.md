# NVIDIA Driver Installation Toolkit v1.4

## Overview
Comprehensive toolkit for installing and troubleshooting NVIDIA drivers on Debian-based Linux systems, with focus on security-focused distributions. Version 1.4 targets **LightDM + KDE Plasma + Wayland**, with full dual-GPU support and robust error handling.

## What's New in v1.4

- **LightDM + Wayland Focus**: Configures LightDM as display manager with KDE Plasma Wayland as the default session
- **Config-Only Mode**: `--config-only` flag to reconfigure system without reinstalling drivers
- **NVIDIA Module Options**: Creates `/etc/modprobe.d/nvidia-wayland.conf` with modeset, fbdev, and PreserveVideoMemoryAllocations
- **Early Module Loading**: Creates `/etc/modules-load.d/nvidia.conf` for boot-time NVIDIA module loading
- **Single Initramfs Rebuild**: All modprobe.d changes consolidated into one initramfs rebuild at the end
- **Post-Reboot Verification**: New `nvidia-verify.sh` script for verifying installation after reboot
- **Robust GRUB Handling**: `_grub_add_param` helper with validation and `grub-mkconfig` fallback
- **Improved Error Handler**: Dynamic distro identification, `/tmp` log fallback, fixed ERR trap context

## Target Hardware
- **GPU**: NVIDIA GPUs (tested with GeForce GT 1030, GP108 architecture)
- **Architecture**: Supports legacy and current driver branches
- **Common Issues**: Display manager conflicts, ACPI errors, boot failures, dual-GPU routing

## Supported Distributions
- Parrot OS 7.1 (Debian 12 base, KDE Plasma, LightDM)
- Kali Linux (Debian Testing base)
- Standard Debian/Ubuntu derivatives

## Project Structure

```
nvidia-toolkit/
├── README.md                          # This file
├── GETTING-STARTED.md                 # Quick start guide
├── scripts/
│   ├── nvidia-install.sh              # Automated install (LightDM + KDE Plasma Wayland)
│   ├── nvidia-remove.sh               # Complete removal with cleanup
│   ├── nvidia-diagnose.sh             # Session-aware diagnostic tool
│   ├── nvidia-verify.sh               # Post-reboot verification
│   └── error-handler.sh               # Shared failure logging library
├── docs/
│   ├── WAYLAND-SUPPORT.md             # Wayland setup and troubleshooting
│   ├── COMMAND-CHEATSHEET.md          # All commands in one place
│   ├── QUICK-TROUBLESHOOTING.md       # Emergency fixes
│   └── DISTRO-SPECIFIC-NOTES.md       # Per-distro guidance
└── examples/
    ├── environment.example             # Wayland env vars (GBM_BACKEND etc.)
    ├── sddm-wayland.conf.example       # SDDM Wayland session config (reference)
    ├── xorg.conf.example               # X server config (with dual-GPU BusID)
    ├── grub.example                    # GRUB configuration
    └── blacklist-nouveau.conf          # Nouveau blacklist
```

## Quick Start

### Automated Installation
```bash
cd nvidia-toolkit
sudo ./scripts/nvidia-install.sh
```

The installer will:
1. Detect your GPU and check for dual-GPU configuration
2. Create a backup of current configs
3. Install prerequisites (kernel headers, LightDM, Plasma workspace)
4. Blacklist nouveau and remove old NVIDIA drivers
5. Install NVIDIA driver packages + Wayland EGL support
6. Configure NVIDIA kernel module options (modeset, fbdev, PreserveVideoMemory)
7. Configure X server for LightDM greeter
8. Configure LightDM with KDE Plasma Wayland as default session
9. Set up dual-GPU (if applicable): Intel blacklist, cleanup old services
10. Configure GRUB parameters and rebuild initramfs
11. Verify installation

### Config-Only Mode
```bash
# Reconfigure system when drivers are already installed
sudo ./scripts/nvidia-install.sh --config-only
```

Skips driver install/removal, only reconfigures: modules, GRUB, LightDM, dual-GPU, initramfs.

### Quick Diagnostic
```bash
sudo ./scripts/nvidia-diagnose.sh
```

### Post-Reboot Verification
```bash
sudo ./scripts/nvidia-verify.sh
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

### Method 3: Official NVIDIA .run Installer
```bash
sudo systemctl stop display-manager
chmod +x NVIDIA-Linux-*.run
sudo ./NVIDIA-Linux-*.run
sudo reboot
```

## Wayland Configuration

The installer configures the following for Wayland:

| Component | File | Purpose |
|-----------|------|---------|
| Module options | `/etc/modprobe.d/nvidia-wayland.conf` | modeset=1, fbdev=1, PreserveVideoMemory |
| Early loading | `/etc/modules-load.d/nvidia.conf` | Load NVIDIA modules at boot |
| Environment | `/etc/environment` | GBM_BACKEND, __GLX_VENDOR_LIBRARY_NAME |
| LightDM | `/etc/lightdm/lightdm.conf.d/50-nvidia-wayland.conf` | Default session: plasma (Wayland) |
| Greeter setup | `/usr/local/bin/nvidia-lightdm-setup.sh` | xrandr provider setup for X11 greeter |
| GRUB | `/etc/default/grub` | nvidia-drm.modeset=1, fbdev=1, PreserveVideoMemory |

See `docs/WAYLAND-SUPPORT.md` for detailed Wayland guidance.

## Dual-GPU Support

If your system has both an Intel iGPU and NVIDIA dGPU, the installer:

- Creates `/etc/X11/xorg.conf` with NVIDIA BusID for the LightDM greeter (X11)
- Relies on `nvidia-drm.modeset=1` for DRM-level GPU selection in the Wayland session
- Removes old `nvidia-primary.service` (X11-only, not needed for Wayland)
- Optionally blacklists Intel i915 to force NVIDIA-only operation

## Verification Commands

### After Installation (post-reboot)
```bash
# Run the verification script
sudo ./scripts/nvidia-verify.sh

# Or verify manually:
echo $XDG_SESSION_TYPE                 # should say "wayland"
nvidia-smi                             # driver loaded
cat /sys/module/nvidia_drm/parameters/modeset  # should say "Y"
cat /sys/module/nvidia_drm/parameters/fbdev    # should say "Y"
eglinfo | head -20                     # EGL info
wayland-info                           # Wayland compositor info
```

## Troubleshooting Decision Tree

```
Boot Issue?
├── Black screen, no TTY → GRUB issue/kernel panic
│   └── Solution: Boot from live USB, chroot, fix GRUB
├── Black screen, TTY accessible → Driver/compositor issue
│   └── Solution: TTY login, check display manager + session logs
├── GUI crashes after login → Display manager or Wayland issue
│   ├── Check: journalctl -b | grep kwin_wayland
│   ├── Check: journalctl -u lightdm -b
│   └── Fallback: switch to X11 session at login screen
└── Dual-GPU wrong output → Display routing issue
    ├── Greeter (X11): Check xorg.conf BusID
    └── Session (Wayland): Check /sys/class/drm/card0/device/vendor
```

## Known Issues Database

### Issue 1: GUI Boot Failure After Driver Installation
- Black screen on boot, TTY accessible
- Check display manager status and Wayland/X logs
- See `docs/QUICK-TROUBLESHOOTING.md`

### Issue 2: ACPI Communication Errors
- Common on Parrot OS 7
- Fix: Add `noapic` or `acpi=off` to GRUB
- See `examples/grub.example`

### Issue 3: Wayland Session Won't Start
- Missing `nvidia-drm.modeset=1` in GRUB
- Missing `GBM_BACKEND=nvidia-drm` in `/etc/environment`
- Missing `libnvidia-egl-wayland1` package
- Missing `nvidia-drm.fbdev=1` (kernel 6.x+)
- See `docs/WAYLAND-SUPPORT.md`

### Issue 4: Dual-GPU Wrong Display Output
- Monitor connected to NVIDIA but display routes through Intel
- Greeter (X11): Need xorg.conf with BusID
- Session (Wayland): May need to blacklist i915
- See `docs/QUICK-TROUBLESHOOTING.md`

### Issue 5: Suspend/Resume Fails on Wayland
- Missing `NVreg_PreserveVideoMemoryAllocations=1`
- nvidia-suspend/resume/hibernate services not enabled
- The installer configures both automatically

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
5. Set `nvidia-drm.modeset=1` in GRUB (required for Wayland)
6. Document working configuration
7. Have recovery plan ready (live USB)
8. Use `nvidia-verify.sh` after reboot to confirm everything works

## Resources

- [Debian Wiki: NVIDIA](https://wiki.debian.org/NvidiaGraphicsDrivers)
- [NVIDIA Unix Drivers](https://www.nvidia.com/en-us/drivers/unix/)
- [KDE Plasma Wayland](https://community.kde.org/Plasma/Wayland)

---

**Note**: This toolkit is based on practical experience with NVIDIA GT 1030 on Parrot OS 7, Kali Linux, and related Debian-based distributions. Your specific hardware and software configuration may require adjustments.
