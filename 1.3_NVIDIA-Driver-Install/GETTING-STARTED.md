# NVIDIA Driver Installation Project v1.3 - Getting Started

## Quick Start

This project provides comprehensive tools and documentation for installing NVIDIA drivers on Linux, specifically tested on security-focused distributions like Parrot OS 7, BlackArch, and Kali Linux.

**New in v1.3**: LightDM support, automatic dpkg repair, and multi-display-manager awareness. Choose between X11, Wayland, or both sessions during installation. Dual-GPU systems (Intel + NVIDIA) are handled automatically.

### For the Impatient

**Automated Installation** (interactive — will ask you to choose X11/Wayland/Both):
```bash
cd 1.3_NVIDIA-Driver-Install
sudo ./scripts/nvidia-install.sh
```

**Quick Diagnostic**:
```bash
sudo ./scripts/nvidia-diagnose.sh
```

**Emergency Removal**:
```bash
sudo ./scripts/nvidia-remove.sh
```

## Project Structure

```
1.3_NVIDIA-Driver-Install/
├── README.md                          # Main documentation (START HERE)
├── GETTING-STARTED.md                 # This file
├── scripts/
│   ├── nvidia-install.sh              # Automated install (X11/Wayland/Both + dual-GPU)
│   ├── nvidia-remove.sh               # Complete removal with Wayland cleanup
│   └── nvidia-diagnose.sh             # Session-aware diagnostic tool
├── docs/
│   ├── WAYLAND-SUPPORT.md             # Wayland setup and troubleshooting
│   ├── COMMAND-CHEATSHEET.md          # All commands in one place
│   ├── QUICK-TROUBLESHOOTING.md       # Emergency fixes
│   └── DISTRO-SPECIFIC-NOTES.md       # Per-distro guidance
└── examples/
    ├── environment.example             # Wayland env vars
    ├── sddm-wayland.conf.example       # SDDM Wayland config
    ├── xorg.conf.example               # X server config (with dual-GPU BusID)
    ├── grub.example                    # GRUB configuration
    ├── blacklist-nouveau.conf          # Nouveau blacklist
    └── mkinitcpio.conf.example         # Arch initramfs config
```

## What to Read First

1. **If you just want to install**: Start with `README.md` > Quick Start section
2. **If something is broken**: Go to `docs/QUICK-TROUBLESHOOTING.md`
3. **If you need Wayland help**: Check `docs/WAYLAND-SUPPORT.md`
4. **If you need distro-specific info**: Check `docs/DISTRO-SPECIFIC-NOTES.md`

## Choosing Your Session Type

During installation, you'll be asked to choose a display session:

| Choice | Best For | What It Configures |
|--------|----------|--------------------|
| **X11** | Maximum compatibility, legacy apps | xorg.conf, glx, xrandr |
| **Wayland** | Modern desktops (KDE Plasma 5.25+) | GBM_BACKEND, SDDM Wayland, EGL |
| **Both** | Flexibility — choose at login | X11 + Wayland configs, session selector |

**Not sure?** Choose **Both**. You can select X11 or Wayland at the SDDM login screen.

## Common Scenarios

### Scenario 1: Fresh Installation (Single GPU)

```bash
# 1. Run diagnostic to see current state
sudo ./scripts/nvidia-diagnose.sh

# 2. Run automated installer
sudo ./scripts/nvidia-install.sh
# → Choose your session type (X11 / Wayland / Both)

# 3. Reboot
sudo reboot

# 4. Verify
nvidia-smi
```

### Scenario 2: Fresh Installation (Dual-GPU: Intel + NVIDIA)

```bash
# Same as above — the installer auto-detects dual-GPU
sudo ./scripts/nvidia-install.sh
# → It will detect Intel + NVIDIA and configure routing automatically
# → For X11: creates xorg.conf with NVIDIA BusID
# → For Wayland: relies on nvidia-drm.modeset=1

sudo reboot
```

### Scenario 3: Black Screen After Installation

**X11 session**:
```bash
# From TTY (Ctrl+Alt+F2):
cat /var/log/Xorg.0.log | grep "(EE)"
sudo ./scripts/nvidia-remove.sh
sudo reboot
```

**Wayland session**:
```bash
# From TTY (Ctrl+Alt+F2):
journalctl -b | grep kwin_wayland
# Quick fix: fall back to X11
sudo rm /etc/sddm.conf.d/10-wayland.conf
sudo systemctl restart display-manager
```

### Scenario 4: Troubleshooting Existing Installation

```bash
# Generate diagnostic report (now includes Wayland + dual-GPU checks)
sudo ./scripts/nvidia-diagnose.sh

# Review the report
cat nvidia-diagnostic-*.log

# Check distribution-specific issues
cat docs/DISTRO-SPECIFIC-NOTES.md
```

### Scenario 5: Switching from X11 to Wayland

```bash
# 1. Ensure driver 495+ is installed
nvidia-smi --query-gpu=driver_version --format=csv,noheader

# 2. Re-run installer and choose "Wayland" or "Both"
sudo ./scripts/nvidia-install.sh

# 3. Reboot and select "Plasma (Wayland)" at login screen
```

## Understanding the Scripts

### nvidia-install.sh
- Detects GPU and checks for dual-GPU setup
- Prompts for session type: X11 / Wayland / Both
- Creates backup of current config
- Installs kernel headers and NVIDIA driver
- Blacklists nouveau
- Configures chosen session (X11: xorg.conf, Wayland: env vars + SDDM)
- Configures dual-GPU routing (if applicable)
- Always sets `nvidia-drm.modeset=1` in GRUB

### nvidia-remove.sh
- Stops display manager and unloads NVIDIA modules
- Removes all NVIDIA packages
- Cleans X server configuration
- Cleans Wayland configuration (env vars, SDDM config)
- Removes dual-GPU service (nvidia-primary)
- Removes Intel blacklist
- Updates initramfs

### nvidia-diagnose.sh
- Detects session type (X11/Wayland) and active compositor
- Checks Wayland environment variables
- Detects and reports dual-GPU configuration
- Checks DRM primary GPU device
- Runs all standard checks (modules, packages, logs, X config)
- Generates comprehensive timestamped report

## Example Configuration Files

Located in `examples/` directory:

- **environment.example**: Copy to `/etc/environment` — Wayland env vars
- **sddm-wayland.conf.example**: Copy to `/etc/sddm.conf.d/10-wayland.conf`
- **xorg.conf.example**: Copy to `/etc/X11/xorg.conf` (includes dual-GPU BusID section)
- **blacklist-nouveau.conf**: Copy to `/etc/modprobe.d/blacklist-nouveau.conf`
- **grub.example**: Reference for `/etc/default/grub`
- **mkinitcpio.conf.example**: For Arch-based systems

## Quick Reference Commands

### Check If NVIDIA Is Working
```bash
nvidia-smi                             # GPU info (both sessions)
lsmod | grep nvidia                    # Module loaded (both sessions)
glxinfo | grep "OpenGL"               # X11 session
eglinfo | head -20                     # Wayland session
echo $XDG_SESSION_TYPE                 # Check session type
```

### Check Logs for Issues
```bash
# X11
cat /var/log/Xorg.0.log | grep "(EE)"

# Wayland
journalctl -b | grep kwin_wayland

# Both
journalctl -b | grep nvidia
dmesg | grep -i nvidia
```

### Display Manager Control
```bash
systemctl status display-manager       # Check status
systemctl restart display-manager      # Restart
systemctl stop display-manager         # Stop (for fixes)
```

## Common Issues and Quick Fixes

| Issue | Quick Fix |
|-------|-----------|
| Black screen after boot (X11) | Boot to TTY, run `nvidia-remove.sh` |
| Black screen after boot (Wayland) | Remove `/etc/sddm.conf.d/10-wayland.conf`, restart DM |
| Nouveau conflicts | See `examples/blacklist-nouveau.conf` |
| Display manager won't start | Try switching: `sudo systemctl enable lightdm` |
| ACPI errors | See GRUB parameters in `examples/grub.example` |
| Works until kernel update | Install DKMS version (see distro notes) |
| Wrong GPU active (dual-GPU) | X11: check BusID. Wayland: blacklist i915 |
| Wayland cursor issues | Add `WLR_NO_HARDWARE_CURSORS=1` to `/etc/environment` |

## Hardware Compatibility

**Tested Hardware**: NVIDIA GeForce GT 1030

**Should Work With**: Most NVIDIA GPUs from GTX 600 series onwards

**Kernel**: Tested on 5.x and 6.x series kernels

## Safety Tips

**DO**:
- Read the documentation before starting
- Run diagnostic before making changes
- Test with `systemctl restart display-manager` before rebooting
- Keep a live USB ready
- Choose "Both" if unsure about X11 vs Wayland

**DON'T**:
- Skip nouveau blacklisting
- Mix different installation methods
- Ignore warning messages
- Forget to update initramfs
- Reboot without testing first

## Getting Help

1. Run diagnostic: `sudo ./scripts/nvidia-diagnose.sh`
2. Check `docs/QUICK-TROUBLESHOOTING.md`
3. Check `docs/WAYLAND-SUPPORT.md` (for Wayland issues)
4. Check `docs/DISTRO-SPECIFIC-NOTES.md`
5. When asking for help, provide the diagnostic report output

## Version Information

- **v1.3** — LightDM support, dpkg repair, multi-DM awareness, improved error handling
- Based on real-world troubleshooting with NVIDIA GT 1030 on Parrot OS 7, BlackArch, and Kali Linux

Last updated: February 2026

## Additional Resources

- [Arch Wiki: NVIDIA](https://wiki.archlinux.org/title/NVIDIA)
- [Debian Wiki: NVIDIA](https://wiki.debian.org/NvidiaGraphicsDrivers)
- [KDE Plasma Wayland](https://community.kde.org/Plasma/Wayland)
- [NVIDIA Unix Drivers](https://www.nvidia.com/en-us/drivers/unix/)
