# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an NVIDIA driver installation toolkit for Linux, focused on security-oriented distributions. It provides automated bash scripts and documentation for installing, diagnosing, and removing NVIDIA drivers, with specific handling for dual-GPU (Intel + NVIDIA) systems.

**Target hardware**: NVIDIA GeForce GT 1030 (GP108 architecture)
**Primary OS**: Parrot OS 7.1 (Debian 12 base, KDE Plasma, SDDM, Wayland)
**Also tested on**: BlackArch Linux (Arch-based), Kali Linux (Debian Testing base)

## Repository Structure

The repo is organized as versioned iterations of the toolkit:

- `1.0_NVIDIA-Driver-Install/` - Initial version of scripts and docs
- `1.1_NVIDIA-Driver-Install/` - Improved version with additional docs and examples
- `1.1b_NVIDIA-Driver-Install_dual-gpu-fix/` - Standalone fix for dual-GPU (Intel iGPU + NVIDIA dGPU) display routing issue
- `00systemConfig_Info/` - Reference system configuration snapshots (EDID, OpenGL, Vulkan, Wayland, X-Server info)

Each versioned directory contains the same core structure:
```
scripts/
  nvidia-install.sh    # Automated install (root required, interactive prompts)
  nvidia-remove.sh     # Complete driver removal with cleanup
  nvidia-diagnose.sh   # Diagnostic report generator (outputs timestamped .log files)
docs/                  # Troubleshooting and distro-specific guides
examples/              # Reference config files (xorg.conf, blacklist-nouveau, grub, mkinitcpio)
```

## Script Architecture

All three core scripts share a common pattern:
- Bash with `set -e`, colored output via ANSI escape codes
- Root check at entry (`$EUID -ne 0`)
- Distro detection via `/etc/debian_version` (Debian path) or `/etc/arch-release` (Arch path)
- Interactive `read -p` prompts for destructive or optional operations
- Package manager abstraction: `apt` for Debian-based, `pacman` for Arch-based

**nvidia-install.sh** flow: detect GPU -> backup configs -> install kernel headers -> blacklist nouveau -> remove old drivers -> install from repos -> optional xorg.conf generation -> optional GRUB nvidia-drm.modeset=1 -> verify

**nvidia-remove.sh** flow: stop display manager -> unload kernel modules (nvidia_drm, nvidia_modeset, nvidia_uvm, nvidia) -> purge packages -> clean configs -> update initramfs -> optional GRUB cleanup

**dual-gpu-fix.sh** addresses a specific issue where the monitor is connected to the NVIDIA card but X server defaults to Intel iGPU. It auto-detects the NVIDIA PCI BusID, creates xorg.conf with explicit BusID, optionally blacklists i915, and creates a systemd service (`nvidia-primary.service`) for xrandr provider setup.

## Key System Paths Referenced

- `/etc/modprobe.d/blacklist-nouveau.conf` - Nouveau blacklist config
- `/etc/X11/xorg.conf` and `/etc/X11/xorg.conf.d/` - X server configuration
- `/etc/default/grub` - GRUB boot parameters
- `/var/log/Xorg.0.log` - X server log
- `/root/nvidia-backup-*` - Config backups created by install script

## Working with These Scripts

All scripts require `sudo` and are interactive (use `read -p` for confirmation prompts). They cannot be run non-interactively without modification. Diagnostic logs are written to the same directory as the script with timestamped filenames like `nvidia-diagnostic-YYYYMMDD-HHMMSS.log`.

When modifying scripts, maintain the dual distro-detection pattern (Debian vs Arch) and preserve the interactive safety prompts before destructive operations.
