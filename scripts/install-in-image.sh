#!/usr/bin/env bash
set -euo pipefail

board=$1
cd /tmp/rk628-image
case "$board" in
  pi4) platform=kvmd-platform-v2-hdmi-rpi4 ;;
  pi5) platform=kvmd-platform-v2-hdmiusb-rpi5 ;;
  *) exit 2 ;;
esac
pacman -Q "$platform"
cp -p /boot/config.txt boot-config.original
cp -p /boot/cmdline.txt boot-cmdline.original
mkdir -p /etc/pacman.d/hooks
test ! -e /etc/pacman.d/hooks/30-systemd-tmpfiles.hook
test ! -L /etc/pacman.d/hooks/30-systemd-tmpfiles.hook
ln -s /dev/null /etc/pacman.d/hooks/30-systemd-tmpfiles.hook
trap 'rm -f /etc/pacman.d/hooks/30-systemd-tmpfiles.hook' EXIT
# Upgrade as one transaction so headers, kernel and userspace libraries agree.
pacman --noconfirm --ask=4 -Syu --needed \
  base-devel bc bison flex libelf openssl pahole python linux-rpi-headers-pikvm \
  dkms dtc kmod v4l-utils alsa-utils libdrm janus-gateway-pikvm alsa-lib opus \
  speexdsp libjpeg-turbo libevent libbsd libgpiod x264 ffmpeg
test -f /boot/config.txt || cp boot-config.original /boot/config.txt
test -f /boot/cmdline.txt || cp boot-cmdline.original /boot/cmdline.txt

read -r _ kernel_version < <(pacman -Q linux-rpi-pikvm)
read -r _ headers_version < <(pacman -Q linux-rpi-headers-pikvm)
test "$kernel_version" = "$headers_version"
mapfile -t headers < <(pacman -Qlq linux-rpi-headers-pikvm | sed -n 's|/build/Makefile$|/build|p')
test "${#headers[@]}" -eq 1
kernel=$(cat "${headers[0]}/include/config/kernel.release")
test -s "/usr/lib/modules/$kernel/build/Module.symvers"

package=$(sed -n 's/^PACKAGE_NAME="\([^"]*\)"$/\1/p' driver/dkms.conf)
version=$(sed -n 's/^PACKAGE_VERSION="\([^"]*\)"$/\1/p' driver/dkms.conf)
[[ $package == rk628-rpi-dkms && $version =~ ^[A-Za-z0-9.+~-]+$ ]]
dkms_source="/usr/src/$package-$version"
test ! -e "$dkms_source"
install -d /usr/src
cp -a driver "$dkms_source"
dkms add -m "$package" -v "$version"
dkms install -m "$package" -v "$version" -k "$kernel"
test -s "/boot/overlays/rk628-$board.dtbo"
install -Dm644 driver/udev/99-rk628.rules /etc/udev/rules.d/99-rk628.rules
depmod "$kernel"
for module in video-rk628 rk628-csi rk628-hdmirx-class; do
  vermagic=$(modinfo -k "$kernel" -F vermagic "$module")
  test "${vermagic%% *}" = "$kernel"
done

options=(WITH_LIBX264=1 WITH_JANUS=1 WITH_GPIO=1 WITH_SYSTEMD=1 WITH_V4P=1)
make -C ustreamer -j"$(nproc)" "${options[@]}"
make -C ustreamer "${options[@]}" PREFIX=/usr install
features=$(/usr/bin/ustreamer --features)
for feature in WITH_LIBX264 WITH_JANUS WITH_GPIO WITH_SYSTEMD WITH_V4P; do
  grep -Fx "+ $feature" <<<"$features"
done
test -s /usr/lib/ustreamer/janus/libjanus_ustreamer.so
sed -i '/^\[options\]$/a IgnorePkg = ustreamer' /etc/pacman.conf

if [[ $board == pi4 ]]; then
  install -m 644 edid.hex /etc/kvmd/tc358743-edid.hex
fi
python configure.py / config "$board"
install -Dm644 config/webrtc.conf /etc/sysctl.d/99-rk628-pikvm.conf
usermod -aG video kvmd-janus
kvmd -m >/dev/null
systemctl --root=/ enable kvmd-janus.service kvmd-media.service

{
  printf 'Installed kernel release: %s\n' "$kernel"
  pacman -Q linux-rpi-pikvm linux-rpi-headers-pikvm kvmd janus-gateway-pikvm "$platform"
  df -h / /boot >&2
} > packages.txt
pacman --noconfirm -Scc
# DKMS may generate a signing key. Keep the public certificate only.
rm -f /var/lib/dkms/mok.key
