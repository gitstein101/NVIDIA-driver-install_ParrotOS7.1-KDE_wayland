# NVIDIA Wayland Support Guide

## Overview

Starting with driver version 495+, NVIDIA provides first-class Wayland support via the DRM/KMS subsystem and EGL streaming. This guide covers setup, verification, and troubleshooting for NVIDIA on Wayland, with focus on KDE Plasma (SDDM).

## Requirements

- **NVIDIA driver**: Version 495 or newer (525+ recommended)
- **Kernel parameter**: `nvidia-drm.modeset=1` (mandatory)
- **EGL Wayland library**: `libnvidia-egl-wayland1`
- **Compositor**: KDE Plasma 5.25+ / GNOME 41+ / Sway 1.8+

## Required Environment Variables

These must be set system-wide in `/etc/environment`:

```bash
# Use NVIDIA GBM backend for Wayland
GBM_BACKEND=nvidia-drm

# Use NVIDIA for GLX in Wayland
__GLX_VENDOR_LIBRARY_NAME=nvidia
```

The `nvidia-install.sh` script sets these automatically when you choose "Wayland" or "Both" session types.

## KDE Plasma Wayland Setup

### SDDM Configuration

For Wayland-only sessions, configure SDDM in `/etc/sddm.conf.d/10-wayland.conf`:

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

# Check KWin compositor
echo $KWIN_COMPOSE
# Should be empty or "wayland"

# Check running compositor
pgrep -a kwin_wayland
```

## GRUB Configuration

`nvidia-drm.modeset=1` is **mandatory** for Wayland. Add it to `/etc/default/grub`:

```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash nvidia-drm.modeset=1"
```

Then update GRUB:

```bash
sudo update-grub
```

## Dual-GPU Systems on Wayland

On Wayland, display routing is handled by the DRM subsystem — **no xorg.conf or xrandr is needed**.

When `nvidia-drm.modeset=1` is set:
- The kernel uses the NVIDIA DRM driver for output
- The Wayland compositor (kwin_wayland) selects the GPU via DRM
- No manual BusID configuration required

If your monitor is physically connected to the NVIDIA card and `nvidia-drm.modeset=1` is set, it should work automatically.

### If the Wrong GPU is Selected

On some dual-GPU systems, the kernel may still default to the Intel iGPU:

1. Check which GPU is card0:
   ```bash
   cat /sys/class/drm/card0/device/vendor
   # 0x10de = NVIDIA, 0x8086 = Intel
   ```

2. If Intel is card0, you can blacklist it:
   ```bash
   echo "blacklist i915" | sudo tee /etc/modprobe.d/blacklist-intel.conf
   sudo update-initramfs -u
   sudo reboot
   ```

## Troubleshooting

### Black Screen on Wayland Login

Unlike X11, there is **no Xorg.0.log** to check. Instead:

```bash
# Check kwin_wayland logs
journalctl -b | grep kwin_wayland

# Check DRM/GPU logs
journalctl -b | grep -i "drm\|nvidia\|gbm"

# Check SDDM logs
journalctl -u sddm -b
```

Common causes:
- Missing `nvidia-drm.modeset=1` in GRUB
- Missing `GBM_BACKEND=nvidia-drm` in `/etc/environment`
- Missing `libnvidia-egl-wayland1` package
- Driver version too old (< 495)

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
   ```bash
   # Settings > Display and Monitor > Compositor
   # Rendering backend should be "OpenGL" or "EGL"
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

# 2. Modeset enabled
cat /sys/module/nvidia_drm/parameters/modeset

# 3. Environment variables set
echo $GBM_BACKEND
echo $__GLX_VENDOR_LIBRARY_NAME

# 4. EGL-Wayland library installed
dpkg -l | grep egl-wayland

# 5. Wayland session active
echo $XDG_SESSION_TYPE
echo $WAYLAND_DISPLAY

# 6. GPU rendering
glxinfo | grep "OpenGL renderer"  # Via XWayland
```

## Switching Between X11 and Wayland

If you configured "Both" during installation:

1. Log out
2. At the SDDM login screen, click the session selector (bottom-left)
3. Choose "Plasma (Wayland)" or "Plasma (X11)"
4. Log in

To set a default session:

```bash
# For SDDM - set in /etc/sddm.conf.d/
[General]
Session=plasma.desktop          # X11
# or
Session=plasmawayland.desktop   # Wayland
```

## Known Limitations

- **NVIDIA driver < 495**: No Wayland support at all
- **NVIDIA driver 495-524**: Basic Wayland support, some issues
- **NVIDIA driver 525+**: Full GBM support, recommended
- **Screen recording**: Some tools (OBS with X11 capture) don't work natively; use PipeWire
- **VRR/FreeSync**: Support is compositor-dependent (KDE Plasma 5.27+ supports it)
- **Multi-monitor**: Some edge cases with mixed DPI on Wayland
