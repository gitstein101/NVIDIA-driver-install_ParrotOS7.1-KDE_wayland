# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an NVIDIA driver installation toolkit for Linux, focused on security-oriented distributions. It provides automated bash scripts and documentation for installing, diagnosing, and removing NVIDIA drivers, with specific handling for dual-GPU (Intel + NVIDIA) systems.

**Target hardware**: NVIDIA GeForce GT 1030 (GP108 architecture)
**Primary OS**: Parrot OS 7.1 (Debian 12 base, KDE Plasma, LightDM, Wayland)
**Also tested on**: Kali Linux (Debian Testing base)

## Repository Structure

```
nvidia-toolkit/
  scripts/
    nvidia-install.sh            # Automated install v1.4 (LightDM + KDE Plasma + Wayland)
    nvidia-remove.sh             # Complete driver removal with cleanup
    nvidia-diagnose.sh           # Diagnostic report generator (outputs timestamped .log + .json)
    nvidia-verify.sh             # Post-reboot verification script
    error-handler.sh             # Shared failure logging library (sourced by install/remove)
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

All core scripts share a common pattern:
- Bash with `set -euo pipefail`, colored output via ANSI escape codes
- Root check at entry (`$EUID -ne 0`)
- Debian-based guard via `/etc/debian_version` (rejects non-Debian systems)
- Interactive `read -p` prompts for destructive or optional operations
- Uses `apt`/`dpkg` for package management

**nvidia-install.sh** (v1.4) flow: detect GPU -> detect dual-GPU -> backup configs -> install prerequisites (kernel headers, LightDM, Plasma) -> blacklist nouveau -> remove old drivers -> install NVIDIA from repos + Wayland EGL packages -> configure NVIDIA kernel module options (modeset, fbdev, PreserveVideoMemory) -> configure X server (for LightDM greeter) -> configure LightDM for KDE Plasma Wayland session -> optional dual-GPU setup (Intel blacklist, cleanup old nvidia-primary.service) -> GRUB parameters + single initramfs rebuild -> verify

- Supports `--config-only` mode to reconfigure without reinstalling drivers
- Uses `_grub_add_param` helper for robust GRUB parameter injection
- Single initramfs rebuild at step 12 consolidates all modprobe.d changes
- Integrates error-handler.sh for step tracking and failure logging

**nvidia-remove.sh** flow: warn if graphical session -> stop display manager + nvidia-persistenced -> unload kernel modules (with process detection and kill) -> purge packages (4-phase: purge, repair dpkg, force-remove broken, autoremove with retry) -> clean X configs -> clean Wayland configs (env vars, SDDM) -> remove dual-GPU service/Intel blacklist -> update initramfs -> load nouveau fallback -> restart display manager -> optional GRUB cleanup

**nvidia-diagnose.sh** flow: system info -> session type detection (Wayland/X11/compositor) -> GPU hardware (dual-GPU aware, DRM card vendor) -> driver status (modules, nvidia-smi, drm.modeset) -> installed packages -> blacklist configs -> X server configs -> Wayland configs (SDDM, LightDM, GDM) -> display manager status -> dual-GPU service -> recent logs (dmesg, journal, Xorg, KWin) -> OpenGL/EGL/Vulkan info -> GRUB config -> kernel headers -> Wayland deep checks (fbdev, PreserveVideoMemory, power services, GBM vs EGL Streams, explicit sync) -> common issues analysis -> recent failure logs -> JSON report

**error-handler.sh**: shared library sourced by install and remove scripts. Provides:
- Step tracking (`set_step`, `step_done`, `record_change`)
- ERR/EXIT/INT trap handlers with failure context capture
- Structured failure log generation with system state snapshot
- Fallback to `/tmp` if primary log location is unwritable
- Dynamic distro identification via `/etc/os-release` PRETTY_NAME

## Key System Paths Referenced

- `/etc/modprobe.d/blacklist-nouveau.conf` - Nouveau blacklist config
- `/etc/modprobe.d/blacklist-intel.conf` - Intel iGPU blacklist (dual-GPU)
- `/etc/modprobe.d/nvidia-wayland.conf` - NVIDIA module options (modeset, fbdev, PreserveVideoMemory)
- `/etc/modules-load.d/nvidia.conf` - Early NVIDIA module loading
- `/etc/X11/xorg.conf` and `/etc/X11/xorg.conf.d/` - X server configuration
- `/etc/default/grub` - GRUB boot parameters
- `/etc/environment` - Wayland environment variables (GBM_BACKEND, __GLX_VENDOR_LIBRARY_NAME)
- `/etc/lightdm/lightdm.conf.d/50-nvidia-wayland.conf` - LightDM NVIDIA + Wayland config
- `/usr/local/bin/nvidia-lightdm-setup.sh` - LightDM greeter display setup script
- `/var/log/Xorg.0.log` - X server log
- `/root/nvidia-backup-*` - Config backups created by install script

## Working with These Scripts

All scripts require `sudo` and are interactive (use `read -p` for confirmation prompts). They cannot be run non-interactively without modification. Diagnostic logs are written to the same directory as the script with timestamped filenames like `nvidia-diagnostic-YYYYMMDD-HHMMSS.log` and `.json`. These output files are gitignored.

When modifying scripts, preserve the interactive safety prompts before destructive operations.
