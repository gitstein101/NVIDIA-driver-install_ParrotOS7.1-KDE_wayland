# NVIDIA Wayland Support Guide

## Overview

Starting with driver version 495+, NVIDIA provides first-class Wayland support via the DRM/KMS subsystem and GBM. This guide covers setup, verification, and troubleshooting for NVIDIA on Wayland, with focus on KDE Plasma with LightDM.

The `nvidia-install.sh` v1.4 script configures all of this automatically.

## Requirements

- **NVIDIA driver**: Version 495 or newer (525+ recommended, 555+ for explicit sync)
- **Kernel parameters**: `nvidia-drm.modeset=1` (mandatory), `nvidia-drm.fbdev=1` (recommended on kernel 6.x+)
- **EGL Wayland library**: `libnvidia-egl-wayland1`
- **Compositor**: KDE Plasma 5.25+ / GNOME 41+ / Sway 1.8+
- **Module option**: `NVreg_PreserveVideoMemoryAllocations=1` (required for suspend/resume)

## What the Installer Configures

The v1.4 installer creates the following Wayland configuration:

### NVIDIA Module Options
File: `/etc/modprobe.d/nvidia-wayland.conf`
```
options nvidia_drm modeset=1 fbdev=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1
```

### Early Module Loading
File: `/etc/modules-load.d/nvidia.conf`
```
nvidia
nvidia_modeset
nvidia_uvm
nvidia_drm
```

### Environment Variables
File: `/etc/environment`
```bash
GBM_BACKEND=nvidia-drm
__GLX_VENDOR_LIBRARY_NAME=nvidia
```

### GRUB Parameters
File: `/etc/default/grub`
```
nvidia-drm.modeset=1 nvidia-drm.fbdev=1 nvidia.NVreg_PreserveVideoMemoryAllocations=1
```

### LightDM Configuration
File: `/etc/lightdm/lightdm.conf.d/50-nvidia-wayland.conf`
```ini
[Seat:*]
display-setup-script=/usr/local/bin/nvidia-lightdm-setup.sh
user-session=plasma
```

The greeter runs under X11 (with an xrandr display setup script), while the user session launches KDE Plasma Wayland.

### Power Management Services
The installer enables these systemd services for suspend/resume:
- `nvidia-suspend.service`
- `nvidia-resume.service`
- `nvidia-hibernate.service`

## KDE Plasma Wayland Setup

### LightDM Configuration (Default)

The installer configures LightDM with KDE Plasma Wayland as the default session. The LightDM greeter runs under X11, and the user session starts KDE Plasma Wayland via `/usr/share/wayland-sessions/plasma.desktop`.

### SDDM Configuration (Alternative)

If you prefer SDDM, configure it in `/etc/sddm.conf.d/10-wayland.conf`:

```ini
[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell

[Wayland]
CompositorCommand=kwin_wayland --drm --no-lockscreen --no-global-shortcuts --locale1
```

For dual-session (X11 + Wayland available at login):

```ini
[General]
DisplayServer=x11
```

This keeps the SDDM greeter on X11 but allows you to select a Wayland session (e.g., "Plasma (Wayland)") from the login screen.

### Verifying KDE Wayland

After logging in:

```bash
# Check session type
echo $XDG_SESSION_TYPE
# Should output: wayland

# Check running compositor
pgrep -a kwin_wayland

# Check DRM modeset
cat /sys/module/nvidia_drm/parameters/modeset  # Should say "Y"

# Check fbdev
cat /sys/module/nvidia_drm/parameters/fbdev    # Should say "Y"
```

## GRUB Configuration

The following kernel parameters are set by the installer:

| Parameter | Purpose | Required? |
|-----------|---------|-----------|
| `nvidia-drm.modeset=1` | Enable NVIDIA DRM kernel modesetting | **Mandatory** |
| `nvidia-drm.fbdev=1` | Enable framebuffer console on kernel 6.x+ | Recommended |
| `nvidia.NVreg_PreserveVideoMemoryAllocations=1` | Preserve VRAM on suspend/resume | Required for suspend |

To manually add them:

```bash
sudo nano /etc/default/grub
# Add to GRUB_CMDLINE_LINUX_DEFAULT
sudo update-grub
```

## Dual-GPU Systems on Wayland

On Wayland, display routing is handled by the DRM subsystem — **no xorg.conf or xrandr is needed for the user session**.

When `nvidia-drm.modeset=1` is set:
- The kernel uses the NVIDIA DRM driver for output
- The Wayland compositor (kwin_wayland) selects the GPU via DRM
- No manual BusID configuration required for the session

The installer creates an `xorg.conf` with NVIDIA BusID for the **LightDM greeter only** (which runs under X11).

### If the Wrong GPU is Selected

On some dual-GPU systems, the kernel may still default to the Intel iGPU:

1. Check which GPU is card0:
   ```bash
   cat /sys/class/drm/card0/device/vendor
   # 0x10de = NVIDIA, 0x8086 = Intel
   ```

2. If Intel is card0, blacklist it:
   ```bash
   echo "blacklist i915" | sudo tee /etc/modprobe.d/blacklist-intel.conf
   sudo update-initramfs -u
   sudo reboot
   ```

   The installer offers this option during dual-GPU setup.

## Explicit Sync Support

Explicit sync eliminates Wayland flickering on NVIDIA. Requirements:
- **Kernel**: 6.8 or newer
- **Driver**: 555 or newer

The diagnostic script (`nvidia-diagnose.sh`) checks for explicit sync support automatically.

## Troubleshooting

### Black Screen on Wayland Login

Unlike X11, there is **no Xorg.0.log** to check. Instead:

```bash
# Check kwin_wayland logs
journalctl -b | grep kwin_wayland

# Check DRM/GPU logs
journalctl -b | grep -i "drm\|nvidia\|gbm"

# Check LightDM logs
journalctl -u lightdm -b
```

Common causes:
- Missing `nvidia-drm.modeset=1` in GRUB
- Missing `GBM_BACKEND=nvidia-drm` in `/etc/environment`
- Missing `libnvidia-egl-wayland1` package
- Driver version too old (< 495)
- Missing `nvidia-drm.fbdev=1` on kernel 6.x+

### Suspend/Resume Fails

```bash
# Check PreserveVideoMemoryAllocations
cat /sys/module/nvidia/parameters/PreserveVideoMemoryAllocations
# Should output: 1

# Check power management services
systemctl is-enabled nvidia-suspend nvidia-resume nvidia-hibernate

# If not enabled:
sudo systemctl enable nvidia-suspend nvidia-resume nvidia-hibernate
```

### Cursor Issues (Invisible or Corrupted)

Some compositors have hardware cursor issues with NVIDIA:

```bash
# Add to /etc/environment
WLR_NO_HARDWARE_CURSORS=1
```

Note: This is mainly for wlroots-based compositors (Sway, Hyprland). KDE Plasma usually handles cursors correctly.

### Screen Tearing on Wayland

Wayland compositors should prevent tearing by design. If you still see tearing:

1. Verify `nvidia-drm.modeset=1` is active:
   ```bash
   cat /sys/module/nvidia_drm/parameters/modeset
   # Should output: Y
   ```

2. For KDE, check compositor settings:
   ```
   Settings > Display and Monitor > Compositor
   Rendering backend should be "OpenGL" or "EGL"
   ```

### Firefox / Electron Apps Show Black Window

These apps may need explicit Wayland support:

```bash
# Firefox: enable Wayland in about:config
# Set widget.use-xdg-desktop-portal.file-picker to 1
# Or launch with:
MOZ_ENABLE_WAYLAND=1 firefox

# Electron apps (VS Code, Discord, etc.)
--ozone-platform=wayland
```

### XWayland for Legacy X11 Apps

X11 applications run through XWayland automatically. If an X11 app doesn't render:

```bash
# Check if XWayland is running
pgrep Xwayland

# Force an app to use XWayland
GDK_BACKEND=x11 some-application
QT_QPA_PLATFORM=xcb some-qt-application
```

## Verification Commands

### Quick Verification

```bash
# Session type
echo $XDG_SESSION_TYPE

# NVIDIA driver loaded
nvidia-smi

# DRM modeset and fbdev
cat /sys/module/nvidia_drm/parameters/modeset
cat /sys/module/nvidia_drm/parameters/fbdev

# EGL info (Wayland)
eglinfo | head -20

# Wayland compositor info
wayland-info

# KDE-specific screen info
kscreen-doctor --outputs
```

### Full Verification Checklist

```bash
# 1. Driver loaded
lsmod | grep nvidia_drm

# 2. Modeset and fbdev enabled
cat /sys/module/nvidia_drm/parameters/modeset   # Y
cat /sys/module/nvidia_drm/parameters/fbdev      # Y

# 3. PreserveVideoMemoryAllocations
cat /sys/module/nvidia/parameters/PreserveVideoMemoryAllocations  # 1

# 4. Environment variables set
echo $GBM_BACKEND                    # nvidia-drm
echo $__GLX_VENDOR_LIBRARY_NAME      # nvidia

# 5. EGL-Wayland library installed
dpkg -l | grep egl-wayland

# 6. Wayland session active
echo $XDG_SESSION_TYPE               # wayland
echo $WAYLAND_DISPLAY                # wayland-0 or similar

# 7. Power management services
systemctl is-enabled nvidia-suspend nvidia-resume nvidia-hibernate

# 8. GPU rendering
glxinfo | grep "OpenGL renderer"     # Via XWayland
```

## Switching Between X11 and Wayland

At the LightDM login screen, you can select your session type:
1. Log out
2. At the login screen, look for a session selector
3. Choose "Plasma (Wayland)" or "Plasma (X11)"
4. Log in

## Known Limitations

- **NVIDIA driver < 495**: No Wayland support at all
- **NVIDIA driver 495-524**: Basic Wayland support, some issues
- **NVIDIA driver 525+**: Full GBM support, recommended
- **NVIDIA driver 555+**: Explicit sync support (eliminates flickering)
- **Screen recording**: Some tools (OBS with X11 capture) don't work natively; use PipeWire
- **VRR/FreeSync**: Support is compositor-dependent (KDE Plasma 5.27+ supports it)
- **Multi-monitor**: Some edge cases with mixed DPI on Wayland
