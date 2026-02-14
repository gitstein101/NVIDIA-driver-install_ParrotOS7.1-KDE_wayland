# NVIDIA Driver Installation Project - Getting Started

## Quick Start

This project provides comprehensive tools and documentation for installing NVIDIA drivers on Linux, specifically tested on security-focused distributions like Parrot OS 7, BlackArch, and Kali Linux.

### For the Impatient

**Automated Installation** (Debian-based):
```bash
cd NVIDIA-Driver-Install
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
NVIDIA-Driver-Install/
├── README.md                    # Main documentation (START HERE)
├── GETTING-STARTED.md          # This file
├── scripts/
│   ├── nvidia-install.sh       # Automated installation
│   ├── nvidia-remove.sh        # Complete removal tool
│   └── nvidia-diagnose.sh      # Diagnostic tool
├── docs/
│   ├── QUICK-TROUBLESHOOTING.md   # Emergency fixes
│   └── DISTRO-SPECIFIC-NOTES.md   # Per-distro guidance
└── examples/
    ├── xorg.conf.example          # X server config
    ├── blacklist-nouveau.conf     # Nouveau blacklist
    ├── grub.example               # GRUB configuration
    └── mkinitcpio.conf.example    # Arch initramfs config
```

## What to Read First

1. **If you just want to install**: Start with `README.md` → Recommended Installation Method section
2. **If something is broken**: Go to `docs/QUICK-TROUBLESHOOTING.md`
3. **If you need distro-specific info**: Check `docs/DISTRO-SPECIFIC-NOTES.md`

## Common Scenarios

### Scenario 1: Fresh Installation

```bash
# 1. Read the main README
cat README.md

# 2. Run diagnostic to see current state
sudo ./scripts/nvidia-diagnose.sh

# 3. Run automated installer
sudo ./scripts/nvidia-install.sh

# 4. Reboot
sudo reboot
```

### Scenario 2: Black Screen After Installation

```bash
# From TTY (Ctrl+Alt+F2):
cd /path/to/NVIDIA-Driver-Install

# Quick reference
cat docs/QUICK-TROUBLESHOOTING.md

# Remove and try again
sudo ./scripts/nvidia-remove.sh
sudo reboot
```

### Scenario 3: Troubleshooting Existing Installation

```bash
# Generate diagnostic report
sudo ./scripts/nvidia-diagnose.sh

# Review the report
cat nvidia-diagnostic-*.log

# Check distribution-specific issues
cat docs/DISTRO-SPECIFIC-NOTES.md
```

### Scenario 4: Different Distribution

Each distribution has quirks. Check distro-specific notes:

```bash
# Find your distribution section
cat docs/DISTRO-SPECIFIC-NOTES.md | grep -A 50 "Parrot OS 7"
cat docs/DISTRO-SPECIFIC-NOTES.md | grep -A 50 "BlackArch"
cat docs/DISTRO-SPECIFIC-NOTES.md | grep -A 50 "Kali Linux"
```

## Understanding the Scripts

### nvidia-install.sh
- Creates backup of current config
- Installs kernel headers
- Blacklists nouveau
- Installs NVIDIA drivers from repos
- Optionally configures X server
- Updates GRUB if needed
- **Safety First**: Tests before committing changes

### nvidia-remove.sh
- Stops display manager
- Unloads NVIDIA modules
- Removes all NVIDIA packages
- Cleans configuration files
- Updates initramfs
- **Use for**: Complete cleanup or troubleshooting

### nvidia-diagnose.sh
- Detects GPU hardware
- Checks driver status
- Analyzes configuration files
- Reviews system logs
- Identifies common issues
- Generates comprehensive report
- **Use for**: Before asking for help or submitting bug reports

## Example Configuration Files

Located in `examples/` directory:

- **xorg.conf.example**: Copy to `/etc/X11/xorg.conf` or `/etc/X11/xorg.conf.d/20-nvidia.conf`
- **blacklist-nouveau.conf**: Copy to `/etc/modprobe.d/blacklist-nouveau.conf`
- **grub.example**: Reference for `/etc/default/grub` modifications
- **mkinitcpio.conf.example**: For Arch-based systems (`/etc/mkinitcpio.conf`)

## Quick Reference Commands

### Check If NVIDIA Is Working
```bash
nvidia-smi                      # Should show GPU info
lsmod | grep nvidia             # Should show loaded modules
glxinfo | grep "OpenGL"         # Should show NVIDIA renderer
```

### Check Logs for Issues
```bash
journalctl -b | grep nvidia     # System logs
dmesg | grep -i nvidia          # Kernel messages
cat /var/log/Xorg.0.log         # X server log
```

### Display Manager Control
```bash
systemctl status display-manager    # Check status
systemctl restart display-manager   # Restart
systemctl stop display-manager      # Stop (for fixes)
```

## Common Issues and Quick Fixes

| Issue | Quick Fix |
|-------|-----------|
| Black screen after boot | Boot to TTY (Ctrl+Alt+F2), run `nvidia-remove.sh` |
| Nouveau conflicts | See `examples/blacklist-nouveau.conf` |
| Display manager won't start | Try switching: `sudo systemctl enable lightdm` |
| ACPI errors | See GRUB parameters in `examples/grub.example` |
| Works until kernel update | Install DKMS version (see distro notes) |

## Hardware Compatibility

**Tested Hardware**:
- NVIDIA GeForce GT 1030

**Should Work With**:
- Most NVIDIA GPUs from GTX 600 series onwards
- Professional Quadro cards
- Compute-focused Tesla cards

**Kernel**: Tested on 5.x and 6.x series kernels

## Distribution Support

**Fully Tested**:
- Parrot OS 7 (Debian 12 base)
- BlackArch Linux (Arch base)
- Kali Linux (Debian Testing base)

**Should Work On**:
- Ubuntu and derivatives
- Debian 11+ (Bullseye, Bookworm)
- Arch Linux and derivatives
- Manjaro

## Getting Help

1. **Run diagnostic first**:
   ```bash
   sudo ./scripts/nvidia-diagnose.sh
   ```

2. **Check your distribution's section** in `docs/DISTRO-SPECIFIC-NOTES.md`

3. **Review quick troubleshooting** in `docs/QUICK-TROUBLESHOOTING.md`

4. **Check logs**:
   ```bash
   journalctl -b | grep -i nvidia
   cat /var/log/Xorg.0.log | grep "(EE)"
   ```

5. When asking for help, provide:
   - Output of `nvidia-diagnose.sh`
   - Distribution and version
   - GPU model
   - What you tried
   - Exact error messages

## Safety Tips

✅ **DO**:
- Read the documentation before starting
- Run diagnostic before making changes
- Test in TTY before rebooting
- Keep a backup/recovery plan
- Have a live USB ready

❌ **DON'T**:
- Skip nouveau blacklisting
- Mix different installation methods
- Ignore warning messages
- Forget to update initramfs
- Reboot without testing first

## Recovery Tools

Always have these ready:
1. **Live USB** with your distribution
2. **TTY access knowledge** (Ctrl+Alt+F2)
3. **Recovery mode access** (GRUB menu)
4. **This project** on a USB drive or accessible location

## Updates and Maintenance

**After Kernel Updates** (Debian-based):
```bash
sudo apt install linux-headers-$(uname -r)
# Driver should auto-rebuild if using DKMS
```

**After Kernel Updates** (Arch-based):
```bash
sudo pacman -S linux-headers
sudo mkinitcpio -P
```

## Version Information

This project is based on real-world troubleshooting experience with:
- NVIDIA GT 1030
- Parrot OS 7 (primary development)
- BlackArch Linux
- Kali Linux
- Various Debian and Arch derivatives

Last updated: February 2026

## Additional Resources

- [Arch Wiki: NVIDIA](https://wiki.archlinux.org/title/NVIDIA)
- [Debian Wiki: NVIDIA](https://wiki.debian.org/NvidiaGraphicsDrivers)
- [Ubuntu NVIDIA Guide](https://help.ubuntu.com/community/BinaryDriverHowto/Nvidia)
- [NVIDIA Unix Drivers](https://www.nvidia.com/en-us/drivers/unix/)

## Contributing

Found an issue or have improvements? Document them! This project thrives on real-world experience.

---

**Remember**: Every system is unique. These scripts and guides are based on common patterns, but your mileage may vary. Always test before committing changes, and keep recovery tools handy.

**Good luck, and may your drivers load successfully!**
