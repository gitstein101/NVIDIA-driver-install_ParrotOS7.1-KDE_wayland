# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an NVIDIA driver installation toolkit for Linux, focused on security-oriented distributions. It provides automated bash scripts and documentation for installing, diagnosing, and removing NVIDIA drivers, with specific handling for dual-GPU (Intel + NVIDIA) systems.

**Target hardware**: NVIDIA GeForce GT 1030 (GP108 architecture)
**Primary OS**: Parrot OS 7.1 (Debian 12 base, KDE Plasma, SDDM, Wayland)
**Also tested on**: Kali Linux (Debian Testing base)

## Repository Structure

```
1.3_NVIDIA-Driver-Install/       # Current toolkit (v1.3)
  scripts/
    nvidia-install.sh            # Automated install (root required, interactive prompts)
    nvidia-remove.sh             # Complete driver removal with cleanup
    nvidia-diagnose.sh           # Diagnostic report generator (outputs timestamped .log files)
    error-handler.sh             # Shared failure logging library
  docs/
    COMMAND-CHEATSHEET.md        # Quick reference for common commands
    DISTRO-SPECIFIC-NOTES.md     # Per-distro guidance (Parrot, Kali, Ubuntu/Debian)
    QUICK-TROUBLESHOOTING.md     # Common issues and fixes
    WAYLAND-SUPPORT.md           # Wayland-specific configuration guide
  examples/                      # Reference config files (xorg.conf, blacklist-nouveau, grub, sddm-wayland, etc.)
  GETTING-STARTED.md             # Setup walkthrough
  README.md                      # Toolkit overview
```

Prior versions (v1.0–v1.2) have been removed but are preserved in git history.

## Script Architecture

All three core scripts share a common pattern:
- Bash with `set -e`, colored output via ANSI escape codes
- Root check at entry (`$EUID -ne 0`)
- Distro detection via `/etc/debian_version` (Debian-based only)
- Interactive `read -p` prompts for destructive or optional operations
- Uses `apt` for package management

**nvidia-install.sh** flow: detect GPU -> repair broken dpkg state -> backup configs -> install kernel headers -> blacklist nouveau -> remove old drivers -> install from repos -> detect session type (X11/Wayland/Both) -> configure display manager (SDDM/LightDM/GDM) -> optional dual-GPU setup -> GRUB nvidia-drm.modeset=1 -> verify

**nvidia-remove.sh** flow: stop display manager -> unload kernel modules (nvidia_drm, nvidia_modeset, nvidia_uvm, nvidia) -> purge packages -> clean configs (including Wayland, LightDM, dual-GPU service) -> update initramfs -> optional GRUB cleanup

**nvidia-diagnose.sh** flow: detect session type (X11/Wayland) -> check GPU, modules, packages -> inspect display manager configs (SDDM, LightDM, GDM) -> check Wayland env vars -> detect dual-GPU -> generate timestamped report

**error-handler.sh**: shared library sourced by other scripts. Provides step tracking, failure logging with timestamped log files, config file snapshots, and structured JSON diagnostic output.

## Key System Paths Referenced

- `/etc/modprobe.d/blacklist-nouveau.conf` - Nouveau blacklist config
- `/etc/X11/xorg.conf` and `/etc/X11/xorg.conf.d/` - X server configuration
- `/etc/default/grub` - GRUB boot parameters
- `/etc/environment` - Wayland environment variables (GBM_BACKEND, __GLX_VENDOR_LIBRARY_NAME)
- `/etc/sddm.conf.d/10-wayland.conf` - SDDM Wayland session config
- `/etc/lightdm/lightdm.conf.d/50-nvidia.conf` - LightDM NVIDIA config
- `/usr/local/bin/nvidia-lightdm-setup.sh` - LightDM display setup script
- `/var/log/Xorg.0.log` - X server log
- `/root/nvidia-backup-*` - Config backups created by install script

## Working with These Scripts

All scripts require `sudo` and are interactive (use `read -p` for confirmation prompts). They cannot be run non-interactively without modification. Diagnostic logs are written to the same directory as the script with timestamped filenames like `nvidia-diagnostic-YYYYMMDD-HHMMSS.log`.

When modifying scripts, preserve the interactive safety prompts before destructive operations.
