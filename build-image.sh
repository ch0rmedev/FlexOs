#!/usr/bin/env bash
# build-image.sh - builds a bootable, persistent, ChromeOS-style Linux disk image.
#
# Result: a raw disk image with a GPT partition table that boots via
#   - legacy BIOS (SeaBIOS on Chromebooks: Ctrl+L in dev mode)
#   - UEFI (removable path, works with MrChromebox UEFI firmware and normal PCs)
# Contains Debian + XFCE + Chromium + Flatpak with Flathub + GNOME Software.
#
# Run as root on an x86_64 Debian/Ubuntu machine with internet access:
#   sudo apt install debootstrap parted dosfstools e2fsprogs gdisk util-linux
#   sudo ./build-image.sh
#
# Options (environment variables):
#   IMG=flexos.img  SIZE=8G  SUITE=trixie  OS_USER=user  OS_PASS=changeme
#   HOSTNAME_=flexos  TZ_=America/New_York

set -euo pipefail

IMG="${IMG:-flexos.img}"
SIZE="${SIZE:-8G}"
SUITE="${SUITE:-trixie}"
MIRROR="${MIRROR:-http://deb.debian.org/debian}"
OS_USER="${OS_USER:-user}"
OS_PASS="${OS_PASS:-changeme}"
HOSTNAME_="${HOSTNAME_:-flexos}"
TZ_="${TZ_:-America/New_York}"
MNT="$(pwd)/build-mnt"

[[ $EUID -eq 0 ]] || { echo "Run as root (sudo)."; exit 1; }
[[ "$(uname -m)" == "x86_64" ]] || { echo "This build targets x86_64 (Intel/AMD) Chromebooks only."; exit 1; }
for c in debootstrap parted losetup mkfs.vfat mkfs.ext4 blkid chroot; do
  command -v "$c" >/dev/null || { echo "Missing tool: $c"; exit 1; }
done

LOOP=""
cleanup() {
  set +e
  for d in dev/pts dev proc sys; do umount -l "$MNT/$d" 2>/dev/null; done
  umount "$MNT/boot/efi" 2>/dev/null
  umount "$MNT" 2>/dev/null
  [[ -n "$LOOP" ]] && losetup -d "$LOOP" 2>/dev/null
}
trap cleanup EXIT

echo "==> Creating $SIZE image with GPT partition table"
rm -f "$IMG"
truncate -s "$SIZE" "$IMG"
parted -s "$IMG" mklabel gpt \
  mkpart biosboot 1MiB 2MiB \
  set 1 bios_grub on \
  mkpart ESP fat32 2MiB 258MiB \
  set 2 esp on \
  mkpart root ext4 258MiB 100%

LOOP="$(losetup -Pf --show "$IMG")"
sleep 1
mkfs.vfat -F32 -n FLEXEFI "${LOOP}p2"
mkfs.ext4 -F -L flexroot "${LOOP}p3"

mkdir -p "$MNT"
mount "${LOOP}p3" "$MNT"
mkdir -p "$MNT/boot/efi"
mount "${LOOP}p2" "$MNT/boot/efi"

echo "==> Bootstrapping Debian $SUITE (this takes a while)"
debootstrap --arch=amd64 --components=main,contrib,non-free,non-free-firmware \
  "$SUITE" "$MNT" "$MIRROR"

ROOT_UUID="$(blkid -s UUID -o value "${LOOP}p3")"
EFI_UUID="$(blkid -s UUID -o value "${LOOP}p2")"

cat > "$MNT/etc/fstab" <<EOF
UUID=$ROOT_UUID  /          ext4  defaults,noatime,errors=remount-ro  0 1
UUID=$EFI_UUID   /boot/efi  vfat  umask=0077,nofail                   0 2
EOF

cat > "$MNT/etc/apt/sources.list" <<EOF
deb $MIRROR $SUITE main contrib non-free non-free-firmware
deb $MIRROR $SUITE-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security $SUITE-security main contrib non-free non-free-firmware
EOF

echo "$HOSTNAME_" > "$MNT/etc/hostname"
cp /etc/resolv.conf "$MNT/etc/resolv.conf"

# ---- files dropped into the image --------------------------------------
mkdir -p "$MNT/usr/local/sbin" "$MNT/etc/systemd/system" "$MNT/etc/lightdm/lightdm.conf.d"

cat > "$MNT/usr/local/sbin/flexos-growroot" <<'EOF'
#!/bin/sh
# On first boot, grow the root partition to fill the USB drive / SD card.
set -e
ROOT_DEV="$(findmnt -n -o SOURCE /)"
DISK="/dev/$(lsblk -no PKNAME "$ROOT_DEV")"
PART="$(cat "/sys/class/block/$(basename "$ROOT_DEV")/partition")"
sgdisk -e "$DISK" || true            # move backup GPT header to end of the device
growpart "$DISK" "$PART" || true
resize2fs "$ROOT_DEV"
touch /var/lib/flexos-grown
EOF
chmod +x "$MNT/usr/local/sbin/flexos-growroot"

cat > "$MNT/etc/systemd/system/flexos-growroot.service" <<'EOF'
[Unit]
Description=Grow root partition to fill the device (first boot)
ConditionPathExists=!/var/lib/flexos-grown
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/flexos-growroot

[Install]
WantedBy=multi-user.target
EOF

cat > "$MNT/etc/lightdm/lightdm.conf.d/50-flexos-autologin.conf" <<EOF
[Seat:*]
autologin-user=$OS_USER
autologin-session=xfce
EOF

# ---- configuration done inside the chroot -------------------------------
cat > "$MNT/tmp/setup.sh" <<'EOF'
#!/bin/bash
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive
export LANG=C.UTF-8

apt-get update
apt-get install -y --no-install-recommends \
  linux-image-amd64 initramfs-tools systemd-sysv \
  grub2-common grub-common grub-pc-bin grub-efi-amd64-bin efibootmgr \
  gdisk cloud-guest-utils e2fsprogs dosfstools locales sudo ca-certificates

apt-get install -y \
  firmware-linux firmware-iwlwifi firmware-realtek firmware-atheros firmware-misc-nonfree \
  network-manager network-manager-gnome \
  xorg xserver-xorg-input-libinput lightdm xfce4 xfce4-whiskermenu-plugin xfce4-terminal \
  pipewire-audio pavucontrol udisks2 gvfs gvfs-backends thunar-volman \
  chromium fonts-noto fonts-noto-color-emoji \
  flatpak gnome-software gnome-software-plugin-flatpak xdg-desktop-portal-gtk \
  gdebi file-roller

# Flathub, system-wide, so GNOME Software shows it out of the box
flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# Chromium as the default browser
update-alternatives --set x-www-browser /usr/bin/chromium || true
update-alternatives --set gnome-www-browser /usr/bin/chromium || true

# Locale / time zone
sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8
ln -sf "/usr/share/zoneinfo/$TZ_" /etc/localtime
echo "$TZ_" > /etc/timezone

# User
useradd -m -s /bin/bash -G sudo,audio,video,plugdev,netdev "$OS_USER"
echo "$OS_USER:$OS_PASS" | chpasswd

systemctl enable NetworkManager lightdm flexos-growroot.service

# Bootloader: BIOS (SeaBIOS) and UEFI-removable, both on the same GPT disk
echo 'GRUB_DISABLE_OS_PROBER=true' >> /etc/default/grub
grub-install --target=i386-pc --recheck "$LOOP"
grub-install --target=x86_64-efi --efi-directory=/boot/efi --removable --no-nvram
update-grub
# Make sure the config points at the UUID, not the build-time loop device
sed -i "s|root=/dev/loop[0-9]*p3|root=UUID=$ROOT_UUID|g" /boot/grub/grub.cfg
update-initramfs -u -k all

apt-get clean
rm -f /tmp/setup.sh
EOF
chmod +x "$MNT/tmp/setup.sh"

mount --bind /dev "$MNT/dev"
mount --bind /dev/pts "$MNT/dev/pts"
mount -t proc proc "$MNT/proc"
mount -t sysfs sys "$MNT/sys"

chroot "$MNT" env OS_USER="$OS_USER" OS_PASS="$OS_PASS" TZ_="$TZ_" \
  LOOP="$LOOP" ROOT_UUID="$ROOT_UUID" /tmp/setup.sh

echo "==> Done. Image: $IMG"
echo "    Flash it with:  sudo ./flash-usb.sh $IMG /dev/sdX"
echo "    Login: $OS_USER / $OS_PASS (change the password after first boot)"
