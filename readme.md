# NVIDIA Driver Installation Toolkit

Automated bash scripts for installing, diagnosing, and removing NVIDIA drivers on Linux, focused on security-oriented distributions with dual-GPU (Intel + NVIDIA) support.

**Target hardware**: NVIDIA GeForce GT 1030 (GP108)
**Primary OS**: Parrot OS 7.1 (Debian 12, KDE Plasma, SDDM, Wayland)
**Also tested on**: Kali Linux

## Features

- Automated install with X11, Wayland, or dual-session support
- Dual-GPU detection and configuration (Intel iGPU + NVIDIA dGPU)
- Multi-display-manager awareness (SDDM, LightDM, GDM)
- dpkg broken-package repair before installation
- Session-aware diagnostics with timestamped log output
- Complete driver removal with config cleanup
- Shared error-handling library with failure logging

## Quick Start

```bash
# Install
sudo ./1.3_NVIDIA-Driver-Install/scripts/nvidia-install.sh

# Diagnose
sudo ./1.3_NVIDIA-Driver-Install/scripts/nvidia-diagnose.sh

# Remove
sudo ./1.3_NVIDIA-Driver-Install/scripts/nvidia-remove.sh
```

All scripts are interactive and require root.

## Repository Structure

```
1.3_NVIDIA-Driver-Install/
  scripts/
    nvidia-install.sh       # Automated install
    nvidia-remove.sh        # Complete removal
    nvidia-diagnose.sh      # Diagnostic report generator
    error-handler.sh        # Shared failure logging library
  docs/                     # Troubleshooting and distro-specific guides
  examples/                 # Reference config files
  GETTING-STARTED.md        # Setup walkthrough
  README.md                 # Detailed toolkit documentation
00systemConfig_Info/        # Reference system config snapshots
```

See `1.3_NVIDIA-Driver-Install/README.md` for full documentation, troubleshooting, and recovery procedures.
