# NVIDIA Driver Installation Toolkit

Automated bash scripts for installing, diagnosing, and removing NVIDIA drivers on Linux, focused on security-oriented distributions with dual-GPU (Intel + NVIDIA) support.

**Target hardware**: NVIDIA GeForce GT 1030 (GP108)
**Primary OS**: Parrot OS 7.1 (Debian 12, KDE Plasma, LightDM, Wayland)
**Also tested on**: Kali Linux

## Features

- Automated install targeting LightDM + KDE Plasma Wayland
- `--config-only` mode to reconfigure without reinstalling drivers
- Dual-GPU detection and configuration (Intel iGPU + NVIDIA dGPU)
- NVIDIA kernel module options for Wayland (modeset, fbdev, PreserveVideoMemory)
- dpkg broken-package repair with essential-package protection
- Comprehensive diagnostics with timestamped log + JSON output
- Post-reboot verification script
- Complete driver removal with config cleanup and nouveau fallback
- Shared error-handling library with structured failure logging

## Quick Start

```bash
# Install (LightDM + KDE Plasma Wayland)
sudo ./nvidia-toolkit/scripts/nvidia-install.sh

# Reconfigure only (drivers already installed)
sudo ./nvidia-toolkit/scripts/nvidia-install.sh --config-only

# Diagnose
sudo ./nvidia-toolkit/scripts/nvidia-diagnose.sh

# Verify (after reboot)
sudo ./nvidia-toolkit/scripts/nvidia-verify.sh

# Remove
sudo ./nvidia-toolkit/scripts/nvidia-remove.sh
```

All scripts are interactive and require root.

## Repository Structure

```
nvidia-toolkit/
  scripts/
    nvidia-install.sh       # Automated install v1.4
    nvidia-remove.sh        # Complete removal
    nvidia-diagnose.sh      # Diagnostic report generator
    nvidia-verify.sh        # Post-reboot verification
    error-handler.sh        # Shared failure logging library
  docs/                     # Troubleshooting and distro-specific guides
  examples/                 # Reference config files
  GETTING-STARTED.md        # Setup walkthrough
  README.md                 # Detailed toolkit documentation
```

See `nvidia-toolkit/README.md` for full documentation, troubleshooting, and recovery procedures.
