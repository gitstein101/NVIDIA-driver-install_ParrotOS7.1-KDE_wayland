# Distribution-Specific NVIDIA Installation Notes

## Parrot OS 7 (Debian 12 Based)

### System Details
- **Base**: Debian 12 (Bookworm)
- **Default DE**: KDE Plasma
- **Display Manager**: LightDM (recommended by toolkit v1.4; Parrot ships with SDDM)
- **Package Manager**: APT
- **Init System**: systemd

### Known Issues

#### 1. Display Manager + NVIDIA Conflicts
**Problem**: Display manager fails to start after NVIDIA driver installation, black screen on boot.

**Symptoms**:
- Black screen after GRUB
- TTY accessible (Ctrl+Alt+F2)
- `systemctl status display-manager` shows failed state
- `/var/log/Xorg.0.log` shows driver errors

**Solutions**:

**Option A: Use the Installer (Recommended)**
The `nvidia-install.sh` v1.4 script installs and configures LightDM automatically, disabling conflicting display managers.

**Option B: Switch to LightDM Manually**
```bash
sudo apt install lightdm
sudo systemctl disable sddm
sudo systemctl enable lightdm
sudo systemctl start lightdm
```

**Option C: Reconfigure SDDM**
```bash
sudo systemctl stop sddm
sudo nvidia-xconfig
sudo systemctl start sddm
```

#### 2. ACPI BIOS Errors
**Problem**: Boot shows ACPI communication errors with NVIDIA hardware.

**Symptoms**:
```
ACPI BIOS Error (bug): Could not resolve symbol...
ACPI Error: AE_NOT_FOUND
```

**Solutions**:

**Temporary Fix** (for testing):
```bash
# Edit GRUB at boot (press 'e' in GRUB menu)
# Add to linux line: acpi=off
```

**Permanent Fix**:
```bash
sudo nano /etc/default/grub
# Modify: GRUB_CMDLINE_LINUX_DEFAULT="quiet acpi=off"
# OR try less aggressive: GRUB_CMDLINE_LINUX_DEFAULT="quiet noapic"
sudo update-grub
sudo reboot
```

**Note**: `acpi=off` disables power management features. Try `noapic` first.

#### 3. KDE Plasma Wayland Session
**Problem**: Historically, NVIDIA + Wayland had poor support, and the recommendation was to disable Wayland. With driver 495+ and `nvidia-drm.modeset=1`, Wayland now works well.

**Automated Setup (Recommended)**:
```bash
# The v1.4 installer configures everything for LightDM + KDE Plasma Wayland:
sudo ./scripts/nvidia-install.sh

# Or reconfigure only (if drivers already installed):
sudo ./scripts/nvidia-install.sh --config-only
```

**Manual Wayland Setup on Parrot OS 7**:
```bash
# 1. Ensure driver 495+ is installed
nvidia-smi --query-gpu=driver_version --format=csv,noheader

# 2. Set required GRUB parameters
# In /etc/default/grub:
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash nvidia-drm.modeset=1 nvidia-drm.fbdev=1 nvidia.NVreg_PreserveVideoMemoryAllocations=1"
sudo update-grub

# 3. Set environment variables
sudo tee -a /etc/environment << EOF
GBM_BACKEND=nvidia-drm
__GLX_VENDOR_LIBRARY_NAME=nvidia
EOF

# 4. Install EGL-Wayland support
sudo apt install libnvidia-egl-wayland1 egl-wayland

# 5. Create NVIDIA module options
sudo tee /etc/modprobe.d/nvidia-wayland.conf << EOF
options nvidia_drm modeset=1 fbdev=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1
EOF

# 6. Enable power management services
sudo systemctl enable nvidia-suspend nvidia-resume nvidia-hibernate

# 7. Reboot and select "Plasma (Wayland)" at login
sudo reboot
```

**If Wayland doesn't work**, fall back to X11:
```bash
# Select "Plasma (X11)" at the login screen session selector
# Or from TTY:
sudo systemctl restart display-manager
```

### Recommended Installation Method

```bash
# 1. Update system
sudo apt update && sudo apt full-upgrade

# 2. Install kernel headers
sudo apt install linux-headers-$(uname -r)

# 3. Remove any existing NVIDIA
sudo apt remove --purge '^nvidia-.*'

# 4. Blacklist nouveau
sudo bash -c "cat > /etc/modprobe.d/blacklist-nouveau.conf << EOF
blacklist nouveau
options nouveau modeset=0
EOF"

# 5. Update initramfs
sudo update-initramfs -u

# 6. Install NVIDIA driver
sudo apt install nvidia-driver nvidia-settings

# 7. Reboot
sudo reboot
```

### Troubleshooting Parrot OS 7

**If GUI won't start (X11)**:
```bash
# Access TTY: Ctrl+Alt+F2
journalctl -u lightdm -b  # Check display manager logs
cat /var/log/Xorg.0.log | grep "(EE)"  # Check X errors

# Try restarting display manager
sudo systemctl restart display-manager
```

**If GUI won't start (Wayland)**:
```bash
# Access TTY: Ctrl+Alt+F2
journalctl -b | grep kwin_wayland     # Check compositor
journalctl -b | grep -i "drm\|gbm"   # Check DRM
journalctl -u lightdm -b              # Check LightDM

# Fall back to X11 session at login screen, or remove and reinstall:
sudo ./scripts/nvidia-remove.sh
sudo reboot
```

**If NVIDIA not detected**:
```bash
nvidia-detect  # Shows recommended driver
lspci | grep VGA  # Confirm GPU is visible
```

---

## Kali Linux

### System Details
- **Base**: Debian Testing (currently)
- **Default DE**: XFCE (also supports KDE, GNOME)
- **Display Manager**: LightDM (XFCE), SDDM (KDE), GDM (GNOME)
- **Package Manager**: APT

### Known Issues

#### 1. Multiple Desktop Environments
**Problem**: Different DEs handle NVIDIA differently.

**Solutions**:

**XFCE** (most stable):
```bash
sudo apt install kali-desktop-xfce nvidia-driver
# LightDM works well with NVIDIA
```

**KDE** (same issues as Parrot OS):
```bash
sudo apt install kali-desktop-kde nvidia-driver
# May need to switch from SDDM to LightDM for X11
# Or configure Wayland (see Parrot OS 7 Wayland section above)
```

**GNOME**:
```bash
sudo apt install kali-desktop-gnome nvidia-driver
# GDM supports Wayland natively with NVIDIA 495+
# Ensure nvidia-drm.modeset=1 is set
```

#### 2. Testing/Unstable Branch Updates
**Problem**: Kali uses Debian Testing, which can introduce instability.

**Solution**: Pin packages when working configuration found
```bash
sudo apt-mark hold nvidia-driver nvidia-utils
# To unhold later:
sudo apt-mark unhold nvidia-driver nvidia-utils
```

#### 3. KDE Plasma Wayland on Kali
Same setup as Parrot OS 7 — use the v1.4 installer or see the manual Wayland section above. Key steps:
1. Install `libnvidia-egl-wayland1`
2. Set `nvidia-drm.modeset=1` and `nvidia-drm.fbdev=1` in GRUB
3. Set `GBM_BACKEND=nvidia-drm` in `/etc/environment`
4. Create `/etc/modprobe.d/nvidia-wayland.conf` with modeset and PreserveVideoMemory options
5. Select "Plasma (Wayland)" at login screen

### Recommended Installation Method

```bash
# 1. Update
sudo apt update && sudo apt full-upgrade

# 2. Install headers
sudo apt install linux-headers-$(uname -r)

# 3. Detect and install
sudo apt install nvidia-detect
nvidia-detect  # Shows recommended driver

# 4. Install driver
sudo apt install nvidia-driver firmware-misc-nonfree

# 5. Reboot
sudo reboot
```

### Kali-Specific Tools Compatibility

**Aircrack-ng with NVIDIA**:
```bash
# No issues, works normally
```

**Hashcat with NVIDIA**:
```bash
# Should work after driver install
hashcat -I  # Verify GPU detected
```

**John the Ripper with NVIDIA**:
```bash
# OpenCL support
sudo apt install nvidia-opencl-icd
```

---

## Ubuntu / Standard Debian

### Recommended (Easiest) Method

**Ubuntu**:
```bash
sudo ubuntu-drivers autoinstall
sudo reboot
```

**Debian**:
```bash
# Enable non-free repos
sudo apt edit-sources
# Add: contrib non-free non-free-firmware

sudo apt update
sudo apt install nvidia-detect
nvidia-detect
sudo apt install nvidia-driver
sudo reboot
```

---

## Comparative Table

| Feature | Parrot OS 7 | Kali Linux | Ubuntu / Debian |
|---------|-------------|------------|-----------------|
| Base | Debian 12 | Debian Testing | Debian Stable / Ubuntu |
| Package Manager | APT | APT | APT |
| Kernel Updates | Stable | Semi-rolling | Stable |
| NVIDIA Complexity | Medium | Medium | Low |
| Recommended Driver | nvidia-driver | nvidia-driver | nvidia-driver |
| Main Issue | DM conflicts | DE variety | Minimal |
| Stability | High | Medium-High | High |
| Best Display Manager | LightDM | LightDM | GDM / LightDM |
| Wayland Support | Good (KDE Plasma) | Good | Good |

---

## Quick Commands Reference

### Package Management

| Task | Command |
|------|---------|
| Update | `sudo apt update` |
| Upgrade | `sudo apt upgrade` |
| Install | `sudo apt install pkg` |
| Remove | `sudo apt remove pkg` |
| Search | `apt search pkg` |
| List installed | `dpkg -l \| grep nvidia` |

### initramfs

| Task | Command |
|------|---------|
| Update | `sudo update-initramfs -u` |
| Update all | `sudo update-initramfs -u -k all` |

### GRUB

| Task | Command |
|------|---------|
| Update | `sudo update-grub` |

---

## Summary Recommendations

### For Parrot OS 7:
- Use `nvidia-install.sh` v1.4 for automated setup (LightDM + KDE Plasma Wayland)
- `nvidia-drm.modeset=1` is mandatory (Wayland) / recommended (X11)
- `nvidia-drm.fbdev=1` recommended on kernel 6.x+
- KDE Plasma Wayland works well with driver 495+ (555+ for explicit sync)
- Add ACPI workarounds if needed
- Install `libnvidia-egl-wayland1` for Wayland

### For Kali Linux:
- Use `nvidia-driver` package
- XFCE desktop most stable for X11
- KDE Plasma works well with Wayland
- Consider pinning packages
- Enable contrib non-free repos

### For All:
- Always blacklist nouveau
- Keep kernel headers installed
- Set `nvidia-drm.modeset=1` in GRUB
- Test before rebooting
- Document working configuration
- See `docs/WAYLAND-SUPPORT.md` for Wayland-specific guidance
