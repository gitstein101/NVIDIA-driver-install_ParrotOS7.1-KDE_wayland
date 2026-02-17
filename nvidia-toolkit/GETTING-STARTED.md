# NVIDIA Driver Installation Toolkit v1.4 - Getting Started

## Quick Start

This toolkit provides comprehensive tools and documentation for installing NVIDIA drivers on Debian-based Linux distributions, specifically tested on security-focused distributions like Parrot OS 7 and Kali Linux.

**v1.4**: Targets LightDM + KDE Plasma Wayland. Includes `--config-only` mode, NVIDIA module option configuration, early module loading, post-reboot verification, and robust error handling with structured failure logs.

### For the Impatient

**Automated Installation** (interactive — configures LightDM + KDE Plasma Wayland):
```bash
cd nvidia-toolkit
sudo ./scripts/nvidia-install.sh
```

**Reconfigure Only** (drivers already installed):
```bash
sudo ./scripts/nvidia-install.sh --config-only
```

**Quick Diagnostic**:
```bash
sudo ./scripts/nvidia-diagnose.sh
```

**Post-Reboot Verification**:
```bash
sudo ./scripts/nvidia-verify.sh
```

**Emergency Removal**:
```bash
sudo ./scripts/nvidia-remove.sh
```

## Project Structure

```
nvidia-toolkit/
├── README.md                          # Main documentation (START HERE)
├── GETTING-STARTED.md                 # This file
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
    ├── environment.example             # Wayland env vars
    ├── sddm-wayland.conf.example       # SDDM Wayland config (reference)
    ├── xorg.conf.example               # X server config (with dual-GPU BusID)
    ├── grub.example                    # GRUB configuration
    └── blacklist-nouveau.conf          # Nouveau blacklist
```

## What to Read First

1. **If you just want to install**: Start with `README.md` > Quick Start section
2. **If something is broken**: Go to `docs/QUICK-TROUBLESHOOTING.md`
3. **If you need Wayland help**: Check `docs/WAYLAND-SUPPORT.md`
4. **If you need distro-specific info**: Check `docs/DISTRO-SPECIFIC-NOTES.md`

## What the Installer Does

The v1.4 installer configures your system for **LightDM + KDE Plasma Wayland**:

| Step | What It Does |
|------|--------------|
| 1-2 | Detect GPU hardware and dual-GPU configuration |
| 3 | Create backup of current configs to `/root/nvidia-backup-*` |
| 4 | Install prerequisites (kernel headers, LightDM, Plasma) |
| 5 | Blacklist nouveau driver |
| 6 | Remove old NVIDIA drivers (with dpkg repair) |
| 7 | Install NVIDIA driver packages + Wayland EGL support |
| 8 | Configure NVIDIA kernel module options (modeset, fbdev, PreserveVideoMemory) |
| 9 | Configure X server for LightDM greeter |
| 10 | Configure LightDM for KDE Plasma Wayland session |
| 11 | Configure dual-GPU for Wayland (if applicable) |
| 12 | Configure GRUB parameters + rebuild initramfs |
| 13 | Verify installation |

With `--config-only`, steps 4-7 are replaced by a verification that drivers are already installed.

## Common Scenarios

### Scenario 1: Fresh Installation (Single GPU)

```bash
# 1. Run diagnostic to see current state
sudo ./scripts/nvidia-diagnose.sh

# 2. Run automated installer
sudo ./scripts/nvidia-install.sh

# 3. Reboot
sudo reboot

# 4. Verify
sudo ./scripts/nvidia-verify.sh
```

### Scenario 2: Fresh Installation (Dual-GPU: Intel + NVIDIA)

```bash
# Same as above — the installer auto-detects dual-GPU
sudo ./scripts/nvidia-install.sh
# → Detects Intel + NVIDIA and configures:
#   - xorg.conf with NVIDIA BusID (for LightDM greeter)
#   - Offers to blacklist Intel i915 for NVIDIA-only operation
#   - Removes old nvidia-primary.service (not needed for Wayland)

sudo reboot
sudo ./scripts/nvidia-verify.sh
```

### Scenario 3: Drivers Installed, Need Reconfiguration

```bash
# Skip driver install, only reconfigure system
sudo ./scripts/nvidia-install.sh --config-only
sudo reboot
sudo ./scripts/nvidia-verify.sh
```

### Scenario 4: Black Screen After Installation

```bash
# From TTY (Ctrl+Alt+F2):

# Check LightDM / compositor logs
journalctl -u lightdm -b
journalctl -b | grep kwin_wayland

# Quick fix: remove driver and start fresh
sudo ./scripts/nvidia-remove.sh
sudo reboot
```

### Scenario 5: Troubleshooting Existing Installation

```bash
# Generate diagnostic report (includes Wayland + dual-GPU + failure log checks)
sudo ./scripts/nvidia-diagnose.sh

# Review the reports
cat nvidia-diagnostic-*.log       # Human-readable
cat nvidia-diagnostic-*.json      # Machine-parseable
```

## Understanding the Scripts

### nvidia-install.sh
- Detects GPU and checks for dual-GPU setup
- Installs prerequisites (kernel headers, LightDM, Plasma workspace)
- Blacklists nouveau and removes old NVIDIA drivers
- Installs NVIDIA driver packages + Wayland EGL support
- Creates `/etc/modprobe.d/nvidia-wayland.conf` (modeset, fbdev, PreserveVideoMemory)
- Creates `/etc/modules-load.d/nvidia.conf` for early module loading
- Configures LightDM with KDE Plasma Wayland as default session
- Handles dual-GPU via xorg.conf BusID (greeter) and DRM (Wayland session)
- Sets GRUB parameters and rebuilds initramfs once at the end
- Integrates error-handler.sh for step tracking and failure logging

### nvidia-remove.sh
- Warns if running from graphical session (risk of black screen)
- Stops display manager and nvidia-persistenced
- Unloads NVIDIA kernel modules (with process detection and kill)
- Removes all NVIDIA packages (4-phase: purge, dpkg repair, force-remove broken, autoremove)
- Cleans X server, Wayland, and dual-GPU configuration
- Updates initramfs and loads nouveau fallback driver
- Attempts to restart display manager
- Optional GRUB parameter cleanup

### nvidia-diagnose.sh
- Detects session type (X11/Wayland) and active compositor
- Checks GPU hardware with dual-GPU and DRM primary device awareness
- Inspects NVIDIA driver status (modules, nvidia-smi, drm.modeset, fbdev)
- Checks Wayland deep configuration (PreserveVideoMemory, power services, explicit sync)
- Runs common issues analysis with actionable fix suggestions
- Scans for recent failure logs from error-handler.sh
- Generates timestamped `.log` (human-readable) and `.json` (machine-parseable) reports

### nvidia-verify.sh
- Post-reboot verification of NVIDIA installation
- Checks driver loading, module parameters, session type, display manager

### error-handler.sh
- Shared library sourced by install and remove scripts
- Provides step tracking, failure logging, and system state snapshots
- ERR/EXIT/INT trap handlers with failure context capture
- Falls back to `/tmp` if primary log location is unwritable

## Example Configuration Files

Located in `examples/` directory:

- **environment.example**: Copy to `/etc/environment` — Wayland env vars
- **sddm-wayland.conf.example**: Reference for SDDM Wayland config (toolkit uses LightDM)
- **xorg.conf.example**: Copy to `/etc/X11/xorg.conf` (includes dual-GPU BusID section)
- **blacklist-nouveau.conf**: Copy to `/etc/modprobe.d/blacklist-nouveau.conf`
- **grub.example**: Reference for `/etc/default/grub`

## Quick Reference Commands

### Check If NVIDIA Is Working
```bash
nvidia-smi                             # GPU info (both sessions)
lsmod | grep nvidia                    # Module loaded (both sessions)
echo $XDG_SESSION_TYPE                 # Check session type
eglinfo | head -20                     # Wayland session
cat /sys/module/nvidia_drm/parameters/modeset  # Should say "Y"
cat /sys/module/nvidia_drm/parameters/fbdev    # Should say "Y"
```

### Check Logs for Issues
```bash
# Wayland
journalctl -b | grep kwin_wayland
journalctl -u lightdm -b

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
| Black screen after boot | Boot to TTY, run `nvidia-remove.sh` |
| Nouveau conflicts | See `examples/blacklist-nouveau.conf` |
| Display manager won't start | Check `journalctl -u lightdm -b` |
| ACPI errors | See GRUB parameters in `examples/grub.example` |
| Works until kernel update | Install DKMS version (see distro notes) |
| Wrong GPU active (dual-GPU) | Greeter: check xorg.conf BusID. Session: blacklist i915 |
| Suspend/resume fails | Check PreserveVideoMemoryAllocations and nvidia-suspend service |

## Hardware Compatibility

**Tested Hardware**: NVIDIA GeForce GT 1030

**Should Work With**: Most NVIDIA GPUs from GTX 600 series onwards

**Kernel**: Tested on 5.x and 6.x series kernels

## Safety Tips

**DO**:
- Read the documentation before starting
- Run diagnostic before making changes
- Use `--config-only` when drivers are already installed
- Keep a live USB ready
- Use `nvidia-verify.sh` after reboot

**DON'T**:
- Skip nouveau blacklisting
- Mix different installation methods
- Ignore warning messages
- Forget to update initramfs
- Reboot without reviewing the installer's verification output

## Getting Help

1. Run diagnostic: `sudo ./scripts/nvidia-diagnose.sh`
2. Check `docs/QUICK-TROUBLESHOOTING.md`
3. Check `docs/WAYLAND-SUPPORT.md` (for Wayland issues)
4. Check `docs/DISTRO-SPECIFIC-NOTES.md`
5. When asking for help, provide the diagnostic `.log` and `.json` reports

## Additional Resources

- [Debian Wiki: NVIDIA](https://wiki.debian.org/NvidiaGraphicsDrivers)
- [KDE Plasma Wayland](https://community.kde.org/Plasma/Wayland)
- [NVIDIA Unix Drivers](https://www.nvidia.com/en-us/drivers/unix/)
