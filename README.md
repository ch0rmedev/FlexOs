# FlexOS: a Chrome OS-style Linux system you can boot from USB/SD

A Debian-based system with a simple desktop, Chromium, Linux app support,
Flatpak + Flathub (via GNOME Software), a GPT partition table, and a persistent
(writable) root filesystem.

This is **not** Chrome OS or Chromium OS. Chrome OS can't be rebuilt with Linux
app stores bolted on in any simple way, so this kit builds a normal Linux
distribution that feels similar: Chromium, a bottom panel and app menu, auto-login,
and an app store.

## What's in the image

- Partition table: GPT with three partitions
  1. 1 MiB BIOS boot partition (for legacy/SeaBIOS boot)
  2. 256 MiB EFI System Partition (FAT32)
  3. ext4 root, which expands to fill the USB drive or SD card on first boot
- Bootloader: GRUB for both legacy BIOS and UEFI (removable path)
- Desktop: XFCE with the Whisker app menu, LightDM auto-login
- Apps: Chromium, terminal, file manager, GNOME Software
- Flatpak with the Flathub remote already added system-wide
- `apt` works too, and `.deb` files open with gdebi
- Wi-Fi/Bluetooth firmware packages for common Chromebook chips
- Default login: `user` / `changeme` (change it after first boot)

## Build (x86_64 Debian/Ubuntu machine, needs root and internet)

```
sudo apt install debootstrap parted dosfstools e2fsprogs gdisk util-linux
sudo ./build-image.sh            # produces flexos.img (8 GB by default)
SIZE=16G sudo -E ./build-image.sh   # bigger image, if you want
```

## Flash

```
lsblk                            # find your USB drive or SD card
sudo ./flash-usb.sh flexos.img /dev/sdX
```

You can also use balenaEtcher or `dd`. The script has safety checks and asks
you to confirm the device.

## Booting on a Chromebook

Important: **recovery mode can't boot this.** Recovery mode only accepts
Google-signed recovery images, and Ctrl+U USB boot expects a Chrome OS-signed
kernel. This image uses a standard Linux kernel, so you have two routes.

### Route A: Developer Mode + legacy boot (no hardware changes)

1. Enter recovery mode (Esc + Refresh + Power), then press Ctrl+D to turn on
   Developer Mode. This wipes the Chromebook's local data.
2. Boot Chrome OS, open a shell (Ctrl+Alt+F2 or Ctrl+Alt+Forward, log in as
   `chronos`) and run:
   `sudo crossystem dev_boot_legacy=1`
   (some models also have an `enable_dev_boot_legacy` helper)
3. Insert the USB/SD card, reboot, and press **Ctrl+L** at the developer screen
   to boot from it via SeaBIOS.

Many Intel Chromebooks have SeaBIOS legacy boot, but some newer models don't.
If Ctrl+L isn't available, use Route B.

### Route B: UEFI firmware (most reliable, needs hardware step)

Install MrChromebox's UEFI firmware (mrchromebox.tech). It requires disabling
firmware write protection and carries some risk of bricking. Afterwards the
Chromebook boots this image like a normal PC (the image has the UEFI fallback
loader).

### Not supported

- ARM Chromebooks (this image is x86_64 only)
- School/work-managed Chromebooks that block Developer Mode
- Some Chromebook hardware (newer audio, touchscreens, keyboard backlight) may
  need extra drivers or tweaks; see chromebook-linux-audio and similar projects.

## Status

The scripts have not been run end-to-end or tested on a real Chromebook. Treat
the first build as a test: expect to tweak package names or boot settings.
Back up anything important before enabling Developer Mode.
