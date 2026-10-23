#!/usr/bin/env bash
# flash-usb.sh - write the built image to a USB drive or SD card.
# Usage: sudo ./flash-usb.sh flexos.img /dev/sdX
# WARNING: everything on the target device is erased.

set -euo pipefail

IMG="${1:-}"
DEV="${2:-}"

[[ $EUID -eq 0 ]] || { echo "Run as root (sudo)."; exit 1; }
[[ -f "$IMG" ]] || { echo "Usage: $0 <image> <device, e.g. /dev/sdb>"; exit 1; }
[[ -b "$DEV" ]] || { echo "$DEV is not a block device."; exit 1; }

# Refuse to write to a partition or to the disk that holds the running system
if [[ "$(lsblk -no TYPE "$DEV" | head -n1)" != "disk" ]]; then
  echo "$DEV is not a whole disk (use /dev/sdb, not /dev/sdb1)."; exit 1
fi
ROOT_DISK="/dev/$(lsblk -no PKNAME "$(findmnt -n -o SOURCE /)" 2>/dev/null | head -n1)"
if [[ "$DEV" == "$ROOT_DISK" ]]; then
  echo "$DEV holds your running system. Refusing."; exit 1
fi

echo "Target device:"
lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINTS "$DEV"
echo
read -r -p "Type the device path ($DEV) to confirm erasing it: " ANSWER
[[ "$ANSWER" == "$DEV" ]] || { echo "Aborted."; exit 1; }

# Unmount anything on it
for p in $(lsblk -lno PATH "$DEV" | tail -n +2); do
  umount "$p" 2>/dev/null || true
done

dd if="$IMG" of="$DEV" bs=4M status=progress conv=fsync
sync
partprobe "$DEV" || true
echo "Done. Safe to remove the drive. The root partition grows to fill it on first boot."
