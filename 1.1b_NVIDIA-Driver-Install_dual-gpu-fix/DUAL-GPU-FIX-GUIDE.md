# Dual GPU Fix - Manual Instructions

## Your Situation

**Problem**: System boots to TTY instead of GUI
**Cause**: You have TWO graphics cards:
- Intel HD Graphics (integrated) - PCI 00:02.0
- NVIDIA GeForce GT 1030 (discrete) - PCI 01:00.0

Your monitor is likely connected to the NVIDIA card, but X server is trying to use Intel. LightDM is running, but you can't see it because the output is going to the wrong GPU.

## Quick Fix Options

### Option 1: Quick Test (From TTY1)

Try this first to see if it works:

```bash
# Stop display manager
sudo systemctl stop lightdm

# Create basic xorg config pointing to NVIDIA
sudo mkdir -p /etc/X11/xorg.conf.d
sudo tee /etc/X11/xorg.conf.d/10-nvidia-primary.conf << 'EOF'
Section "Device"
    Identifier     "NVIDIA Card"
    Driver         "nvidia"
    VendorName     "NVIDIA Corporation"
    BusID          "PCI:1:0:0"
EndSection
EOF

# Restart display manager
sudo systemctl start lightdm
```

Now check if GUI appears on your monitor.

### Option 2: Use the Automated Script

```bash
# Download or copy dual-gpu-fix.sh to your system
sudo ./dual-gpu-fix.sh
```

The script will:
1. Detect your NVIDIA GPU BusID automatically
2. Create proper xorg.conf
3. Configure GRUB
4. Set up automatic GPU switching on boot

### Option 3: Complete Manual Configuration

If you want to do it manually:

**Step 1: Find Your NVIDIA BusID**
```bash
lspci | grep -i vga
# You'll see something like:
# 01:00.0 VGA compatible controller: NVIDIA Corporation GP108 [GeForce GT 1030]
```

**Step 2: Create xorg.conf**
```bash
sudo nano /etc/X11/xorg.conf
```

Add this content (replace BusID if yours is different):
```
Section "ServerLayout"
    Identifier     "Layout0"
    Screen      0  "Screen0" 0 0
EndSection

Section "Device"
    Identifier     "Device0"
    Driver         "nvidia"
    VendorName     "NVIDIA Corporation"
    BoardName      "GeForce GT 1030"
    BusID          "PCI:1:0:0"
EndSection

Section "Screen"
    Identifier     "Screen0"
    Device         "Device0"
    DefaultDepth    24
EndSection
```

**Step 3: Restart Display Manager**
```bash
sudo systemctl restart lightdm
```

### Option 4: Disable Intel Graphics (Nuclear Option)

If nothing else works, disable Intel completely:

```bash
# Blacklist Intel driver
sudo tee /etc/modprobe.d/blacklist-intel.conf << 'EOF'
blacklist i915
blacklist intel_agp
EOF

# Update initramfs
sudo update-initramfs -u

# Reboot
sudo reboot
```

## Verification After Fix

Once you get GUI back, verify NVIDIA is being used:

```bash
# Check which GPU X server is using
glxinfo | grep "OpenGL renderer"
# Should show: NVIDIA GeForce GT 1030

# Check display providers
xrandr --listproviders
# Should show NVIDIA as a provider

# Verify NVIDIA is working
nvidia-smi
```

## Alternative: Switch Monitor Connection

**Hardware solution**: If you have another video port on your motherboard (from Intel graphics), try connecting your monitor there temporarily to see the display. Then you can configure the system to use NVIDIA from the GUI.

## Why This Happened

Your NVIDIA driver installation was successful, but:
1. System has two GPUs (Intel + NVIDIA)
2. X server defaulted to Intel graphics
3. Your monitor is connected to NVIDIA port
4. Display output is going to wrong GPU = black screen
5. But system IS working (TTY accessible, LightDM running)

## Troubleshooting

**If xorg.conf doesn't work:**
```bash
# Check X server log
cat /var/log/Xorg.0.log | grep "(EE)"

# Try using nvidia-xconfig to generate config
sudo nvidia-xconfig --busid=PCI:1:0:0
```

**If still booting to TTY:**
```bash
# Check if display manager started
systemctl status lightdm

# Try starting X manually as your user
startx
```

**Wrong BusID?**
```bash
# List all PCI devices with decimal and hex
lspci -nn | grep -i vga

# NVIDIA shows as 01:00.0
# In X config, this becomes: PCI:1:0:0 (remove leading zeros)
```

## Quick Reference Commands

```bash
# Stop display manager (to make changes)
sudo systemctl stop lightdm

# Check what driver X is using
grep "Driver" /var/log/Xorg.0.log

# Force restart display manager
sudo systemctl restart lightdm

# If all else fails, start X manually
startx
```

## Expected Outcome

After applying the fix:
- System boots to GUI (not TTY)
- LightDM shows login screen
- GPU is NVIDIA GeForce GT 1030
- `nvidia-smi` works
- 3D acceleration works

## Still Stuck?

If none of these work:

1. Run the diagnostic again:
   ```bash
   sudo ./nvidia-diagnose.sh
   ```

2. Check if LightDM is actually running:
   ```bash
   systemctl status lightdm
   ps aux | grep lightdm
   ```

3. Try a different display manager:
   ```bash
   sudo apt install gdm3
   sudo systemctl disable lightdm
   sudo systemctl enable gdm3
   sudo reboot
   ```

---

**TL;DR**: Your NVIDIA driver works! You just need to tell X server to use NVIDIA instead of Intel for display output. Run the `dual-gpu-fix.sh` script or manually create the xorg.conf with the NVIDIA BusID.
